import Foundation
import Network
import Observation

@Observable
final class Host {
    let code = String(Int.random(in: 10000...99999))

    private var listener: NWListener?
    private let serviceID = UUID()
    private let onStatus: (String) -> Void
    private let canvas: CanvasModel
    private var peers: [UUID: PeerConnection] = [:]
    private var readyGuests: Set<UUID> = []
    private let hostID = UUID()
    private var guestDrawer: UUID?
    private var nextDrawer: UUID?

    private(set) var hasStarted = false
    private(set) var isPaused = false
    private(set) var lobbyError: String?
    private var waitingForDrawer = false

    var playerCount: Int { 1 + readyGuests.count }
    var canDraw: Bool { hasStarted && !isPaused && guestDrawer == nil }
    var canTakeTurn: Bool { hasStarted && !isPaused && guestDrawer != nil && nextDrawer == nil }
    var canPause: Bool { hasStarted && !isPaused && nextDrawer == nil }
    var canResume: Bool { isPaused && !waitingForDrawer }

    init(canvas: CanvasModel, onStatus: @escaping (String) -> Void) throws {
        self.canvas = canvas
        self.onStatus = onStatus
        try openLobby()
    }

    private func openLobby() throws {
        let listener = try NWListener(using: .tcp)
        let name = PeerConnection.sessionNamePrefix(for: code) + serviceID.uuidString
        listener.service = NWListener.Service(name: name, type: PeerConnection.serviceType)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, self.listener === listener else { return }
            switch state {
            case .ready:
                self.onStatus("Waiting for players…")
            case .waiting(let error), .failed(let error):
                self.onStatus("Host unavailable: \(error.localizedDescription)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            guard let self, let listener, self.listener === listener else {
                connection.cancel()
                return
            }

            let id = UUID()
            self.peers[id] = PeerConnection(connection, onReady: { [weak self, weak listener] in
                guard let self, let listener, self.listener === listener else { return }
                self.readyGuests.insert(id)
                self.broadcastLobby()
            }, onMessage: { [weak self] message in
                self?.receive(message, from: id)
            }, onEnd: { [weak self] _ in
                self?.removeGuest(id)
            })
        }
        listener.start(queue: .main)
    }

    deinit {
        listener?.cancel()
    }

    func startGame() {
        guard !hasStarted, playerCount > 1 else { return }
        hasStarted = true
        closeLobbyAndPlay()
    }

    func pauseToAddPlayer() {
        guard canPause else { return }
        lobbyError = nil
        do {
            try openLobby()
        } catch {
            lobbyError = "Couldn’t reopen the lobby: \(error.localizedDescription)"
            return
        }

        isPaused = true
        waitingForDrawer = guestDrawer != nil
        if !waitingForDrawer {
            canvas.finishCurrentStroke()
        }
        onStatus("Opening the lobby…")
        broadcast(.pauseGame)
        broadcastLobby()
    }

    func resumeGame() {
        guard canResume else { return }
        isPaused = false
        closeLobbyAndPlay()
    }

    private func closeLobbyAndPlay() {
        listener?.cancel()
        listener = nil
        peers = peers.filter { readyGuests.contains($0.key) }
        broadcast(.startGame(canvas.snapshot))
    }

    func publishSnapshot(immediate: Bool) {
        guard canDraw else { return }
        for id in readyGuests {
            peers[id]?.publishSnapshot(canvas.snapshot, immediate: immediate)
        }
    }

    func requestTurn() {
        guard canTakeTurn else { return }
        requestTurn(for: hostID)
    }

    private func requestTurn(for id: UUID) {
        guard nextDrawer == nil else {
            peers[id]?.send(.turnUnavailable)
            return
        }
        if let guestDrawer {
            guard guestDrawer != id else { return }
            nextDrawer = id
            peers[guestDrawer]?.send(.yieldTurn)
        } else {
            canvas.finishCurrentStroke()
            grantTurn(to: id)
        }
    }

    private func grantTurn(to id: UUID) {
        nextDrawer = nil
        guestDrawer = readyGuests.contains(id) ? id : nil
        broadcast(.snapshot(canvas.snapshot), except: guestDrawer)
        if let guestDrawer {
            peers[guestDrawer]?.send(.grantTurn(canvas.snapshot))
        }
    }

    private func receive(_ message: PeerConnection.Message, from id: UUID) {
        guard readyGuests.contains(id) else { return }
        if !hasStarted {
            if case .requestStart = message {
                startGame()
            }
            return
        }
        if isPaused {
            guard id == guestDrawer, waitingForDrawer else { return }
            switch message {
            case .snapshot(let snapshot):
                canvas.apply(snapshot)
            case .pausedCanvas(let snapshot):
                canvas.apply(snapshot)
                canvas.finishCurrentStroke()
                waitingForDrawer = false
            default:
                break
            }
            return
        }

        switch message {
        case .snapshot(let snapshot) where guestDrawer == id:
            canvas.apply(snapshot)
            for guest in readyGuests where guest != id {
                peers[guest]?.publishSnapshot(snapshot, immediate: true)
            }
        case .requestTurn:
            requestTurn(for: id)
        case .relinquishTurn(let snapshot) where guestDrawer == id:
            guard let nextDrawer else { return }
            canvas.apply(snapshot)
            grantTurn(to: nextDrawer)
        default:
            break
        }
    }

    private func removeGuest(_ id: UUID) {
        peers.removeValue(forKey: id)
        guard readyGuests.remove(id) != nil else { return }
        if !hasStarted || isPaused {
            if guestDrawer == id {
                canvas.finishCurrentStroke()
                guestDrawer = nil
                waitingForDrawer = false
            }
            broadcastLobby()
        } else if guestDrawer == id {
            canvas.finishCurrentStroke()
            grantTurn(to: nextDrawer ?? hostID)
        }
    }

    private func broadcastLobby() {
        broadcast(.lobby(playerCount: playerCount, isPaused: isPaused))
    }

    private func broadcast(_ message: PeerConnection.Message, except excluded: UUID? = nil) {
        for id in readyGuests where id != excluded {
            peers[id]?.send(message)
        }
    }
}
