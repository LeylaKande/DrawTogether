import CoreGraphics
import Observation

@Observable
final class CanvasModel {
    struct Snapshot: Codable {
        var strokes: [[CGPoint]] = []
        var currentStroke: [CGPoint] = []
    }

    private(set) var snapshot = Snapshot()

    func appendPoint(_ point: CGPoint) {
        if snapshot.currentStroke.last != point {
            snapshot.currentStroke.append(point)
        }
    }

    func finishStroke(at point: CGPoint) {
        appendPoint(point)
        finishCurrentStroke()
    }

    func finishCurrentStroke() {
        guard !snapshot.currentStroke.isEmpty else { return }
        snapshot.strokes.append(snapshot.currentStroke)
        snapshot.currentStroke = []
    }

    func clear() {
        snapshot = Snapshot()
    }

    func apply(_ snapshot: Snapshot) {
        self.snapshot = snapshot
    }
}
