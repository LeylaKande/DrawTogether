import Foundation
import Network

// The listener, browser, and connection all deliver callbacks on the main queue.
final class Host {
    private let listener: NWListener
    private var connection: NWConnection?

    private let canvas: CanvasModel
    private let onStatus: (String) -> Void
    private var lastSendTime = -Double.infinity
    private var isSending = false
    private var needsSnapshot = false

    init(canvas: CanvasModel, onStatus: @escaping (String) -> Void) throws {
        self.canvas = canvas
        self.onStatus = onStatus
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
            PeerConnection.start(connection, peer: "guest", onStatus: { [weak self] status in
                self?.onStatus(status)
            }, onReady: { [weak self] connection in
                self?.publishSnapshot(immediate: true)
                // The guest sends no data. A pending read detects when it closes TCP.
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, _, error in
                    self?.endConnection(error)
                }
            })
        }
        listener.start(queue: .main)
    }

    func publishSnapshot(immediate: Bool = false) {
        guard let connection, case .ready = connection.state else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard immediate || now - lastSendTime >= 1.0 / 20 else { return }

        // ponytail: keep only the latest pending snapshot while a send is in flight.
        guard !isSending else {
            needsSnapshot = true
            return
        }

        do {
            let frame = try PeerConnection.frame(canvas.snapshot)
            isSending = true
            needsSnapshot = false
            lastSendTime = now
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.isSending = false
                if let error {
                    self.endConnection(error)
                } else if self.needsSnapshot {
                    self.publishSnapshot(immediate: true)
                }
            })
        } catch {
            endConnection(error)
        }
    }

    private func endConnection(_ error: Error?) {
        guard let connection, case .ready = connection.state else { return }
        onStatus(error.map { "Connection ended: \($0.localizedDescription)" } ?? "Connection ended")
        connection.cancel()
    }

    deinit {
        listener.cancel()
        connection?.cancel()
    }
}
