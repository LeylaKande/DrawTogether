import CoreGraphics
import Observation

@Observable
final class CanvasModel {
    enum PenColor: String, CaseIterable, Codable {
        case black, red, blue, green
    }

    struct Stroke: Codable {
        let color: PenColor
        var points: [CGPoint]
    }

    struct Snapshot: Codable {
        var strokes: [Stroke] = []
        var currentStroke: Stroke?
    }

    private(set) var snapshot = Snapshot()

    func appendPoint(_ point: CGPoint, color: PenColor) {
        if snapshot.currentStroke == nil {
            snapshot.currentStroke = Stroke(color: color, points: [point])
        } else if snapshot.currentStroke?.points.last != point {
            snapshot.currentStroke?.points.append(point)
        }
    }

    func finishStroke(at point: CGPoint, color: PenColor) {
        appendPoint(point, color: color)
        finishCurrentStroke()
    }

    func finishCurrentStroke() {
        guard let stroke = snapshot.currentStroke else { return }
        snapshot.strokes.append(stroke)
        snapshot.currentStroke = nil
    }

    func clear() {
        snapshot = Snapshot()
    }

    func apply(_ snapshot: Snapshot) {
        self.snapshot = snapshot
    }
}
