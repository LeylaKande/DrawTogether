import Foundation
import Network

enum PeerConnection {
    static let serviceType = "_drawtogether._tcp"
    private static let maximumPayloadSize = 4 * 1024 * 1024

    enum SnapshotError: LocalizedError {
        case invalidFrame
        case canvasTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidFrame: "Invalid canvas message"
            case .canvasTooLarge: "Canvas is too large to share"
            }
        }
    }

    static func start(
        _ connection: NWConnection,
        peer: String,
        onStatus: @escaping (String) -> Void,
        onReady: @escaping (NWConnection) -> Void
    ) {
        connection.stateUpdateHandler = { [weak connection] state in
            switch state {
            case .ready:
                onStatus("Connected to \(peer)")
                if let connection { onReady(connection) }
            case .waiting(let error), .failed(let error):
                onStatus("Connection unavailable: \(error.localizedDescription)")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    static func frame(_ snapshot: CanvasModel.Snapshot) throws -> Data {
        let payload = try JSONEncoder().encode(snapshot)
        guard payload.count <= maximumPayloadSize else { throw SnapshotError.canvasTooLarge }

        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        return frame
    }

    static func receiveSnapshots(
        from connection: NWConnection,
        onSnapshot: @escaping (CanvasModel.Snapshot) -> Void,
        onEnd: @escaping (Error?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak connection] header, _, _, error in
            guard let connection else { return }
            if let error {
                onEnd(error)
                return
            }
            guard let header, !header.isEmpty else {
                onEnd(nil)
                return
            }
            let length = header.reduce(0) { ($0 << 8) | Int($1) }
            guard header.count == 4, (1...maximumPayloadSize).contains(length) else {
                onEnd(SnapshotError.invalidFrame)
                return
            }

            connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak connection] payload, _, _, error in
                guard let connection else { return }
                if let error {
                    onEnd(error)
                    return
                }
                guard let payload, payload.count == length else {
                    onEnd(SnapshotError.invalidFrame)
                    return
                }
                do {
                    onSnapshot(try JSONDecoder().decode(CanvasModel.Snapshot.self, from: payload))
                    receiveSnapshots(from: connection, onSnapshot: onSnapshot, onEnd: onEnd)
                } catch {
                    onEnd(error)
                }
            }
        }
    }
}
