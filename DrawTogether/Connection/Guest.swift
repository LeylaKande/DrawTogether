import Network

final class Guest {
    private let browser = NWBrowser(for: .bonjour(type: PeerConnection.serviceType, domain: nil), using: .tcp)
    private var connection: NWConnection?

    init(canvas: CanvasModel, onStatus: @escaping (String) -> Void) {
        browser.stateUpdateHandler = { [weak self] state in
            guard let self, self.connection == nil else { return }
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
            guard let self, self.connection == nil, let endpoint = results.first?.endpoint else { return }

            let connection = NWConnection(to: endpoint, using: .tcp)
            self.connection = connection
            self.browser.cancel()
            onStatus("Connecting…")
            PeerConnection.start(connection, peer: "host", onStatus: { [weak self] status in
                guard self != nil else { return }
                onStatus(status)
            }, onReady: { [weak self] connection in
                PeerConnection.receiveSnapshots(from: connection, onSnapshot: { [weak self] snapshot in
                    guard self != nil else { return }
                    canvas.apply(snapshot)
                }, onEnd: { [weak self, weak connection] error in
                    guard self != nil, let connection, case .ready = connection.state else { return }
                    onStatus(error.map { "Connection ended: \($0.localizedDescription)" } ?? "Connection ended")
                    connection.cancel()
                })
            })
        }
        browser.start(queue: .main)
    }

    deinit {
        browser.cancel()
        connection?.cancel()
    }
}
