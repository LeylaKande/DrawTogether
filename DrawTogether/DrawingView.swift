import SwiftUI

struct DrawingView: View {
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []

    @State private var host: Host?
    @State private var guest: Guest?
    @State private var connectionStatus = "Offline"

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
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text(connectionStatus)
                        .font(.footnote)
                    Spacer()
                    if host != nil || guest != nil {
                        Button("Disconnect") {
                            host = nil
                            guest = nil
                            connectionStatus = "Offline"
                        }
                    } else {
                        Button("Host") {
                            connectionStatus = "Starting host…"
                            do {
                                host = try Host { connectionStatus = $0 }
                            } catch {
                                connectionStatus = "Host unavailable: \(error.localizedDescription)"
                            }
                        }
                        Button("Join") {
                            connectionStatus = "Looking for host…"
                            guest = Guest { connectionStatus = $0 }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .padding()
                .background(.bar)
            }
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
