import Foundation
import Network
import Observation

@Observable
final class Host {
    let code = String(Int.random(in: 10000...99999))

    private let listener: NWListener
    private let canvas: CanvasModel
    private var peers: [UUID: PeerConnection] = [:]
    private var readyGuests: Set<UUID> = []
    private let hostID = UUID()
    private var guestDrawer: UUID?
    private var nextDrawer: UUID?

    private(set) var hasStarted = false
    var playerCount: Int { 1 + readyGuests.count }
    var canDraw: Bool { hasStarted && guestDrawer == nil }
    var canTakeTurn: Bool { hasStarted && guestDrawer != nil && nextDrawer == nil }

    init(canvas: CanvasModel, onStatus: @escaping (String) -> Void) throws {
        self.canvas = canvas
        listener = try NWListener(using: .tcp)
        let name = PeerConnection.sessionNamePrefix(for: code) + UUID().uuidString
        listener.service = NWListener.Service(name: name, type: PeerConnection.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, !self.hasStarted else { return }
            switch state {
            case .ready:
                onStatus("Waiting for players…")
            case .waiting(let error), .failed(let error):
                onStatus("Host unavailable: \(error.localizedDescription)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, !self.hasStarted else {
                connection.cancel()
                return
            }

            let id = UUID()
            self.peers[id] = PeerConnection(connection, onReady: { [weak self] in
                guard let self, !self.hasStarted else { return }
                self.readyGuests.insert(id)
                self.broadcast(.lobby(playerCount: self.playerCount))
            }, onMessage: { [weak self] message in
                self?.receive(message, from: id)
            }, onEnd: { [weak self] _ in
                self?.removeGuest(id)
            })
        }
        listener.start(queue: .main)
    }

    deinit {
        listener.cancel()
    }

    func startGame() {
        guard !hasStarted, playerCount > 1 else { return }
        hasStarted = true
        listener.cancel()
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
        guard hasStarted, readyGuests.contains(id) else { return }
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
        if !hasStarted {
            broadcast(.lobby(playerCount: playerCount))
        } else if guestDrawer == id {
            canvas.finishCurrentStroke()
            grantTurn(to: nextDrawer ?? hostID)
        }
    }

    private func broadcast(_ message: PeerConnection.Message, except excluded: UUID? = nil) {
        for id in readyGuests where id != excluded {
            peers[id]?.send(message)
        }
    }
}
