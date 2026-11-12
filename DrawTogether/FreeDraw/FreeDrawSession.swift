import Foundation
import Network
import Observation

@Observable
final class FreeDrawSession {
    static let serviceType = "_drawfree._tcp"

    enum Message: Codable {
        case welcome(UUID, color: CanvasModel.PenColor)
        case ink(CanvasModel.Snapshot)
        case board([UUID: CanvasModel.Snapshot])
    }

    let canvas = CanvasModel()
    private let isHost: Bool
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var host: FramedPeer<Message>?
    private var guests: [UUID: FramedPeer<Message>] = [:]
    private var guestColors: [UUID: CanvasModel.PenColor] = [:]
    private var board: [UUID: CanvasModel.Snapshot] = [:]
    private var localID: UUID?

    private(set) var penColor: CanvasModel.PenColor?
    private(set) var status = "Connecting…"
    var canDraw: Bool { localID != nil }

    var layers: [CanvasModel.Snapshot] {
        var visible = board
        if let localID {
            // Draw local ink immediately and ignore its echoed copy from the host.
            visible[localID] = canvas.snapshot
        }
        return visible.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { visible[$0] }
    }

    init(hosting: Bool) throws {
        isHost = hosting
        if hosting {
            localID = UUID()
            penColor = nextPenColor()
            try advertise()
        } else {
            browse()
        }
    }

    deinit {
        listener?.cancel()
        browser?.cancel()
    }

    func publishInk(immediate: Bool) {
        guard let localID else { return }
        if isHost {
            board[localID] = canvas.snapshot
            broadcastBoard(immediate: immediate)
        } else {
            host?.publishLatest(.ink(canvas.snapshot), immediate: immediate)
        }
    }

    private func advertise() throws {
        let listener = try NWListener(using: .tcp)
        self.listener = listener
        listener.service = NWListener.Service(type: Self.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.status = "Free Draw is open"
            case .waiting(let error), .failed(let error):
                self?.status = "Hosting unavailable: \(error.localizedDescription)"
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            self.accept(connection)
        }
        listener.start(queue: .main)
    }

    private func nextPenColor() -> CanvasModel.PenColor {
        let palette = CanvasModel.PenColor.allCases.shuffled()
        return palette.first { $0 != penColor && !guestColors.values.contains($0) }
            ?? palette.first ?? .black
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        let color = nextPenColor()
        guestColors[id] = color
        guests[id] = FramedPeer(connection, onReady: { [weak self] in
            guard let self, let peer = self.guests[id] else { return }
            peer.send(.welcome(id, color: color))
            peer.send(.board(self.board))
        }, onMessage: { [weak self] message in
            guard let self, case .ink(let snapshot) = message else { return }
            self.board[id] = snapshot
            self.broadcastBoard(immediate: true)
        }, onEnd: { [weak self] _ in
            guard let self else { return }
            self.guests.removeValue(forKey: id)
            self.guestColors.removeValue(forKey: id)
            // Keep the departing player's ink and finish any visible stroke.
            if let stroke = self.board[id]?.currentStroke {
                self.board[id]?.strokes.append(stroke)
                self.board[id]?.currentStroke = nil
                self.broadcastBoard(immediate: true)
            }
        })
    }

    private func broadcastBoard(immediate: Bool) {
        // ponytail: send the whole board for short experiments. Send stroke deltas for long sessions.
        let update = Message.board(board)
        for peer in guests.values {
            peer.publishLatest(update, immediate: immediate)
        }
    }

    private func browse() {
        status = "Looking for a Free Draw session…"
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.status = "Discovery unavailable: \(error.localizedDescription)"
            } else if case .waiting(let error) = state {
                self?.status = "Discovery unavailable: \(error.localizedDescription)"
            } else if case .ready = state {
                self?.status = "Looking for a Free Draw session…"
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            // ponytail: join the first Free Draw room. Add room selection if multiple experiments run together.
            guard let self, self.host == nil, let endpoint = results.first?.endpoint else { return }
            self.browser?.cancel()
            self.status = "Joining Free Draw…"
            self.host = FramedPeer(NWConnection(to: endpoint, using: .tcp), onReady: {}, onMessage: { [weak self] message in
                guard let self else { return }
                switch message {
                case .welcome(let id, let color):
                    self.penColor = color
                    self.localID = id
                    self.status = "Everyone can draw"
                case .board(let board):
                    self.board = board
                case .ink:
                    break
                }
            }, onEnd: { [weak self] error in
                guard let self else { return }
                // Retain the local preview when the connection ends.
                if let id = self.localID {
                    self.board[id] = self.canvas.snapshot
                }
                self.localID = nil
                self.status = error.map { "Connection ended: \($0.localizedDescription)" } ?? "Host disconnected"
            })
        }
        browser.start(queue: .main)
    }
}
