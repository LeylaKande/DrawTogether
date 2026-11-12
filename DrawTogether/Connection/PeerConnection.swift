import Foundation
import Network

typealias PeerConnection = FramedPeer<GameMessage>

enum GameMessage: Codable {
    case snapshot(CanvasModel.Snapshot)
    case lobby(playerCount: Int, isPaused: Bool)
    case requestStart
    case startGame(CanvasModel.Snapshot)
    case pauseGame
    case pausedCanvas(CanvasModel.Snapshot)
    case requestTurn
    case yieldTurn
    case relinquishTurn(CanvasModel.Snapshot)
    case grantTurn(CanvasModel.Snapshot)
    case turnUnavailable
}

extension FramedPeer where Payload == GameMessage {
    static var serviceType: String { "_drawtogether._tcp" }

    static func isValidSessionCode(_ code: String) -> Bool {
        let digits = code.utf8
        return digits.count == 5 && digits.allSatisfy { (48...57).contains($0) }
    }

    static func sessionNamePrefix(for code: String) -> String {
        "DrawTogether-\(code)-"
    }

    func publishSnapshot(_ snapshot: CanvasModel.Snapshot, immediate: Bool) {
        publishLatest(.snapshot(snapshot), immediate: immediate)
    }
}

// All session and connection callbacks run on the main queue.
final class FramedPeer<Payload: Codable> {
    typealias Message = Payload

    private static var maximumPayloadSize: Int { 4 * 1024 * 1024 }

    private enum SnapshotError: LocalizedError {
        case invalidFrame
        case canvasTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidFrame: "Invalid canvas message"
            case .canvasTooLarge: "Canvas is too large to share"
            }
        }
    }

    private let connection: NWConnection
    private let onMessage: (Message) -> Void
    private let onEnd: (Error?) -> Void
    private(set) var isReady = false
    private var hasStartedReceiving = false
    private var hasEnded = false
    private var lastSendTime = -Double.infinity
    private var isSendingSnapshot = false
    private var pendingMessage: Message?

    init(
        _ connection: NWConnection,
        onReady: @escaping () -> Void,
        onMessage: @escaping (Message) -> Void,
        onEnd: @escaping (Error?) -> Void
    ) {
        self.connection = connection
        self.onMessage = onMessage
        self.onEnd = onEnd

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isReady = true
                if !self.hasStartedReceiving {
                    self.hasStartedReceiving = true
                    onReady()
                    self.receiveMessage()
                }
            case .waiting(let error), .failed(let error):
                self.endConnection(error)
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    deinit {
        connection.cancel()
    }

    func publishLatest(_ message: Message, immediate: Bool) {
        guard isReady else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard immediate || now - lastSendTime >= 1.0 / 20 else { return }
        guard !isSendingSnapshot else {
            pendingMessage = message
            return
        }

        isSendingSnapshot = true
        lastSendTime = now
        sendFrame(message) { [weak self] in
            guard let self else { return }
            self.isSendingSnapshot = false
            if let pending = self.pendingMessage {
                self.pendingMessage = nil
                self.publishLatest(pending, immediate: true)
            }
        }
    }

    // A control message can supersede a queued snapshot at a turn boundary.
    func send(_ message: Message) {
        guard isReady else { return }
        pendingMessage = nil
        sendFrame(message)
    }

    private func sendFrame(_ message: Message, onSent: (() -> Void)? = nil) {
        do {
            let frame = try Self.frame(message)
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.endConnection(error)
                } else {
                    onSent?()
                }
            })
        } catch {
            endConnection(error)
        }
    }

    private func endConnection(_ error: Error?) {
        guard !hasEnded else { return }
        hasEnded = true
        isReady = false
        connection.cancel()
        onEnd(error)
    }

    // encode msg as JSON and encode with 4-byte payload length
    static func frame(_ message: Message) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= maximumPayloadSize else { throw SnapshotError.canvasTooLarge }

        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        return frame
    }

    private func receiveMessage() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, _, error in
            guard let self else { return }
            if let error {
                self.endConnection(error)
                return
            }
            guard let header, !header.isEmpty else {
                self.endConnection(nil)
                return
            }
            let length = header.reduce(0) { ($0 << 8) | Int($1) }
            guard header.count == 4, (1...Self.maximumPayloadSize).contains(length) else {
                self.endConnection(SnapshotError.invalidFrame)
                return
            }

            self.connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] payload, _, _, error in
                guard let self else { return }
                if let error {
                    self.endConnection(error)
                    return
                }
                guard let payload, payload.count == length else {
                    self.endConnection(SnapshotError.invalidFrame)
                    return
                }
                do {
                    self.onMessage(try JSONDecoder().decode(Message.self, from: payload))
                    if self.isReady {
                        self.receiveMessage()
                    }
                } catch {
                    self.endConnection(error)
                }
            }
        }
    }
}
