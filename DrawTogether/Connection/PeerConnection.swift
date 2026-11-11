import Foundation
import Network
import Observation

// All session and connection callbacks run on the main queue.
@Observable
final class PeerConnection {
    static let serviceType = "_drawtogether._tcp"
    private static let maximumPayloadSize = 4 * 1024 * 1024

    enum Message: Codable {
        case snapshot(CanvasModel.Snapshot)
        case requestTurn
        case grantTurn(CanvasModel.Snapshot)
    }

    private enum Turn {
        case drawing, watching, requesting
    }

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
    private let canvas: CanvasModel
    private let onStatus: (String) -> Void
    private var turn: Turn
    private(set) var isReady = false
    private var hasStartedReceiving = false
    private var lastSendTime = -Double.infinity
    private var isSendingSnapshot = false
    private var needsSnapshot = false

    var canDraw: Bool { turn == .drawing }
    var canTakeTurn: Bool { isReady && turn == .watching }
    var isRequestingTurn: Bool { isReady && turn == .requesting }

    init(
        _ connection: NWConnection,
        canvas: CanvasModel,
        startsDrawing: Bool,
        peerName: String,
        onStatus: @escaping (String) -> Void
    ) {
        self.connection = connection
        self.canvas = canvas
        self.onStatus = onStatus
        turn = startsDrawing ? .drawing : .watching

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isReady = true
                onStatus("Connected to \(peerName)")
                self.publishSnapshot(immediate: true)
                if !self.hasStartedReceiving {
                    self.hasStartedReceiving = true
                    self.receiveMessage()
                }
            case .waiting(let error), .failed(let error):
                self.isReady = false
                onStatus("Connection unavailable: \(error.localizedDescription)")
            case .cancelled:
                self.isReady = false
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    deinit {
        connection.cancel()
    }

    func requestTurn() {
        guard canTakeTurn else { return }
        turn = .requesting
        send(.requestTurn)
    }

    func publishSnapshot(immediate: Bool = false) {
        guard isReady, canDraw else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard immediate || now - lastSendTime >= 1.0 / 20 else { return }

        guard !isSendingSnapshot else {
            needsSnapshot = true
            return
        }

        isSendingSnapshot = true
        needsSnapshot = false
        lastSendTime = now
        send(.snapshot(canvas.snapshot)) { [weak self] in
            guard let self else { return }
            self.isSendingSnapshot = false
            if self.needsSnapshot {
                self.publishSnapshot(immediate: true)
            }
        }
    }

    private func handle(_ message: Message) {
        switch message {
        case .snapshot(let snapshot) where !canDraw:
            canvas.apply(snapshot)
        case .requestTurn where canDraw:
            canvas.finishCurrentStroke()
            turn = .watching
            needsSnapshot = false
            // TCP delivers this after any snapshot already submitted for sending.
            send(.grantTurn(canvas.snapshot))
        case .grantTurn(let snapshot) where turn == .requesting:
            canvas.apply(snapshot)
            turn = .drawing
        default:
            endConnection(SnapshotError.invalidFrame)
        }
    }

    private func send(_ message: Message, onSent: (() -> Void)? = nil) {
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
        guard isReady else { return }
        isReady = false
        onStatus(error.map { "Connection ended: \($0.localizedDescription)" } ?? "Connection ended")
        connection.cancel()
    }

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
                    self.handle(try JSONDecoder().decode(Message.self, from: payload))
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
