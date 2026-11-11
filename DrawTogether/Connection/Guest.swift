import Network
import Observation

@Observable
final class Guest {
    private let browser = NWBrowser(for: .bonjour(type: PeerConnection.serviceType, domain: nil), using: .tcp)
    private(set) var peer: PeerConnection?

    init(canvas: CanvasModel, onStatus: @escaping (String) -> Void) {
        browser.stateUpdateHandler = { [weak self] state in
            guard let self, self.peer == nil else { return }
            switch state {
            case .ready:
                onStatus("Looking for host…")
            case .waiting(let error), .failed(let error):
                onStatus("Discovery unavailable: \(error.localizedDescription)")
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.peer == nil, let endpoint = results.first?.endpoint else { return }

            let connection = NWConnection(to: endpoint, using: .tcp)
            self.browser.cancel()
            onStatus("Connecting…")
            self.peer = PeerConnection(connection, canvas: canvas, startsDrawing: false, peerName: "host") { [weak self] status in
                guard self != nil else { return }
                onStatus(status)
            }
        }
        browser.start(queue: .main)
    }

    deinit {
        browser.cancel()
    }
}
