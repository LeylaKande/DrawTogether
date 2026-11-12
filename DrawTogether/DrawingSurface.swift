import SwiftUI

struct DrawingSurface: View {
    let layers: [CanvasModel.Snapshot]
    let canDraw: Bool
    let onPoint: (CGPoint, Bool) -> Void

    private let canvasAspectRatio: CGFloat = 3.0 / 4.0

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * canvasAspectRatio)
            let size = CGSize(width: width, height: width / canvasAspectRatio)

            Canvas { context, size in
                for layer in layers {
                    for stroke in layer.strokes {
                        draw(stroke, in: context, size: size)
                    }
                    if let currentStroke = layer.currentStroke {
                        draw(currentStroke, in: context, size: size)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .background(.white)
            .clipped()
            .overlay {
                Rectangle()
                    .strokeBorder(.gray, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canDraw, size.width > 0 else { return }
                        onPoint(normalized(value.location, in: size), false)
                    }
                    .onEnded { value in
                        guard canDraw, size.width > 0 else { return }
                        onPoint(normalized(value.location, in: size), true)
                    },
                including: canDraw ? .all : .none
            )
            .accessibilityLabel("Drawing canvas")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemGray5))
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(1, max(0, point.x / size.width)),
            y: min(1, max(0, point.y / size.height))
        )
    }

    private func draw(_ stroke: CanvasModel.Stroke, in context: GraphicsContext, size: CGSize) {
        let ink = stroke.color.displayColor
        let points = stroke.points.map {
            CGPoint(x: $0.x * size.width, y: $0.y * size.height)
        }
        let lineWidth = size.width / 75

        guard let first = points.first else { return }
        if points.count == 1 {
            let dot = CGRect(
                x: first.x - lineWidth / 2,
                y: first.y - lineWidth / 2,
                width: lineWidth,
                height: lineWidth
            )
            context.fill(Path(ellipseIn: dot), with: .color(ink))
            return
        }

        var path = Path()
        path.addLines(points)
        context.stroke(
            path,
            with: .color(ink),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}

extension CanvasModel.PenColor {
    var displayColor: Color {
        switch self {
        case .black: .black
        case .red: .red
        case .blue: .blue
        case .green: Color(red: 0, green: 0.5, blue: 0.2)
        }
    }
}
