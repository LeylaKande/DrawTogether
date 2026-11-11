import Network

enum PeerConnection {
    static let serviceType = "_drawtogether._tcp"

    static func start(_ connection: NWConnection, peer: String, onStatus: @escaping (String) -> Void) {
        connection.stateUpdateHandler = { [weak connection] state in
            switch state {
            case .ready:
                onStatus("Connected to \(peer)")
                // No messages yet. A pending read lets us detect when the peer closes TCP.
                connection?.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, error in
                    if let error {
                        onStatus("Connection ended: \(error.localizedDescription)")
                    } else {
                        onStatus("Connection ended")
                    }
                    connection?.cancel()
                }
            case .waiting(let error), .failed(let error):
                onStatus("Connection unavailable: \(error.localizedDescription)")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
}
