import Network
import Observation

// The listener, browser, and connection all deliver callbacks on the main queue.
@Observable
final class Host {
    private let listener: NWListener
    private(set) var peer: PeerConnection?

    init(canvas: CanvasModel, onStatus: @escaping (String) -> Void) throws {
        listener = try NWListener(using: .tcp)
        listener.service = NWListener.Service(type: PeerConnection.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, self.peer == nil else { return }
            switch state {
            case .ready:
                onStatus("Waiting for guest…")
            case .waiting(let error), .failed(let error):
                onStatus("Host unavailable: \(error.localizedDescription)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.peer == nil else {
                connection.cancel()
                return
            }

            self.listener.cancel()
            onStatus("Connecting…")
            self.peer = PeerConnection(connection, canvas: canvas, startsDrawing: true, peerName: "guest") { [weak self] status in
                guard self != nil else { return }
                onStatus(status)
            }
        }
        listener.start(queue: .main)
    }

    deinit {
        listener.cancel()
    }
}
