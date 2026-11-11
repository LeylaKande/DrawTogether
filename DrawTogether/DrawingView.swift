import SwiftUI

struct DrawingView: View {
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []

    private let lineWidth: CGFloat = 5

    var body: some View {
        NavigationStack {
            Canvas { context, _ in
                for stroke in strokes {
                    draw(stroke, in: context)
                }
                draw(currentStroke, in: context)
            }
            .background(.white)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        appendPoint(value.location)
                    }
                    .onEnded { value in
                        appendPoint(value.location)
                        strokes.append(currentStroke)
                        currentStroke = []
                    }
            )
            .accessibilityLabel("Drawing canvas")
            .navigationTitle("Draw Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        strokes.removeAll()
                        currentStroke.removeAll()
                    }
                    .disabled(strokes.isEmpty && currentStroke.isEmpty)
                }
            }
        }
    }

    private func appendPoint(_ point: CGPoint) {
        if currentStroke.last != point {
            currentStroke.append(point)
        }
    }

    private func draw(_ points: [CGPoint], in context: GraphicsContext) {
        guard let first = points.first else { return }

        if points.count == 1 {
            let dot = CGRect(
                x: first.x - lineWidth / 2,
                y: first.y - lineWidth / 2,
                width: lineWidth,
                height: lineWidth
            )
            context.fill(Path(ellipseIn: dot), with: .color(.black))
            return
        }

        var path = Path()
        path.addLines(points)
        context.stroke(
            path,
            with: .color(.black),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
