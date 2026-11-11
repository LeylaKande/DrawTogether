import Network

// The listener, browser, and connection all deliver callbacks on the main queue.
final class Host {
    private let listener: NWListener
    private var connection: NWConnection?

    init(onStatus: @escaping (String) -> Void) throws {
        listener = try NWListener(using: .tcp)
        listener.service = NWListener.Service(type: PeerConnection.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, self.connection == nil else { return }
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
            guard let self, self.connection == nil else {
                connection.cancel()
                return
            }

            self.connection = connection
            self.listener.cancel()
            onStatus("Connecting…")
            PeerConnection.start(connection, peer: "guest") { [weak self] status in
                guard self != nil else { return }
                onStatus(status)
            }
        }
        listener.start(queue: .main)
    }

    deinit {
        listener.cancel()
        connection?.cancel()
    }
}
