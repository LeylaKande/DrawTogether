import Network
import Observation

@Observable
final class Guest {
    let code: String

    private let browser = NWBrowser(for: .bonjour(type: PeerConnection.serviceType, domain: nil), using: .tcp)
    private var peer: PeerConnection?
    private let canvas: CanvasModel

    private(set) var playerCount: Int?
    private(set) var hasStarted = false
    private(set) var canDraw = false
    private(set) var isRequestingTurn = false
    var canTakeTurn: Bool { hasStarted && peer != nil && !canDraw && !isRequestingTurn }

    init?(code: String, canvas: CanvasModel, onStatus: @escaping (String) -> Void) {
        guard PeerConnection.isValidSessionCode(code) else { return nil }
        let prefix = PeerConnection.sessionNamePrefix(for: code)
        self.code = code
        self.canvas = canvas
        browser.stateUpdateHandler = { [weak self] state in
            guard let self, self.peer == nil else { return }
            switch state {
            case .ready:
                onStatus("Looking for session \(code)…")
            case .waiting(let error), .failed(let error):
                onStatus("Discovery unavailable: \(error.localizedDescription)")
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.peer == nil else { return }
            var matches: [String: NWEndpoint] = [:]
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint, name.hasPrefix(prefix) {
                    matches[name] = result.endpoint
                }
            }

            // ponytail: detect duplicate codes among the sessions currently visible to Bonjour.
            guard matches.count == 1, let endpoint = matches.values.first else {
                onStatus(matches.isEmpty ? "Looking for session \(code)…" : "Multiple sessions use this code. Ask the host to restart the session.")
                return
            }

            let connection = NWConnection(to: endpoint, using: .tcp)
            self.browser.cancel()
            onStatus("Joining…")
            self.peer = PeerConnection(connection, onReady: {
                onStatus("Connected to host")
            }, onMessage: { [weak self] message in
                self?.receive(message)
            }, onEnd: { [weak self] error in
                guard let self else { return }
                self.peer = nil
                self.canDraw = false
                self.isRequestingTurn = false
                if !self.hasStarted { self.playerCount = nil }
                onStatus(error.map { "Connection ended: \($0.localizedDescription)" } ?? "Host disconnected")
            })
        }
        browser.start(queue: .main)
    }

    deinit {
        browser.cancel()
    }

    func requestTurn() {
        guard canTakeTurn else { return }
        isRequestingTurn = true
        peer?.send(.requestTurn)
    }

    func publishSnapshot(immediate: Bool) {
        guard canDraw else { return }
        peer?.publishSnapshot(canvas.snapshot, immediate: immediate)
    }

    private func receive(_ message: PeerConnection.Message) {
        switch message {
        case .lobby(let playerCount) where !hasStarted:
            self.playerCount = playerCount
        case .startGame(let snapshot) where !hasStarted:
            canvas.apply(snapshot)
            hasStarted = true
        case .snapshot(let snapshot) where hasStarted && !canDraw:
            canvas.apply(snapshot)
        case .grantTurn(let snapshot) where isRequestingTurn:
            canvas.apply(snapshot)
            isRequestingTurn = false
            canDraw = true
        case .yieldTurn where canDraw:
            canvas.finishCurrentStroke()
            canDraw = false
            peer?.send(.relinquishTurn(canvas.snapshot))
        case .turnUnavailable:
            isRequestingTurn = false
        default:
            break
        }
    }
}
