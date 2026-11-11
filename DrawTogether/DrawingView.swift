import SwiftUI

struct DrawingView: View {
    let canvas: CanvasModel

    @State private var host: Host?
    @State private var guest: Guest?
    @State private var connectionStatus = "Offline"

    private let canvasAspectRatio: CGFloat = 3.0 / 4.0

    private var peer: PeerConnection? { host?.peer ?? guest?.peer }
    private var canDraw: Bool { peer?.canDraw ?? (guest == nil) }

    var body: some View {
        let strokes = canvas.snapshot.strokes
        let currentStroke = canvas.snapshot.currentStroke

        NavigationStack {
            GeometryReader { geometry in
                let width = min(geometry.size.width, geometry.size.height * canvasAspectRatio)
                let size = CGSize(width: width, height: width / canvasAspectRatio)

                Canvas { context, size in
                    for stroke in strokes {
                        draw(stroke, in: context, size: size)
                    }
                    draw(currentStroke, in: context, size: size)
                }
                .frame(width: size.width, height: size.height)
                .background(.white)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canDraw, size.width > 0 else { return }
                            canvas.appendPoint(normalized(value.location, in: size))
                            peer?.publishSnapshot()
                        }
                        .onEnded { value in
                            guard canDraw, size.width > 0 else { return }
                            canvas.finishStroke(at: normalized(value.location, in: size))
                            peer?.publishSnapshot(immediate: true)
                        },
                    including: canDraw ? .all : .none
                )
                .accessibilityLabel("Drawing canvas")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Draw Together")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(connectionStatus)
                        if let peer, peer.isReady {
                            Text(peer.canDraw ? "You’re drawing" : "You’re watching")
                        }
                    }
                    .font(.footnote)
                    Spacer()
                    if let peer, peer.canTakeTurn || peer.isRequestingTurn {
                        Button(peer.isRequestingTurn ? "Taking Turn…" : "Take Turn") {
                            peer.requestTurn()
                        }
                        .disabled(peer.isRequestingTurn)
                    }
                    if host != nil || guest != nil {
                        Button("Disconnect") {
                            canvas.finishCurrentStroke()
                            host = nil
                            guest = nil
                            connectionStatus = "Offline"
                        }
                    } else {
                        Button("Host") {
                            connectionStatus = "Starting host…"
                            do {
                                host = try Host(canvas: canvas) { connectionStatus = $0 }
                            } catch {
                                connectionStatus = "Host unavailable: \(error.localizedDescription)"
                            }
                        }
                        Button("Join") {
                            connectionStatus = "Looking for host…"
                            guest = Guest(canvas: canvas) { connectionStatus = $0 }
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
                        canvas.clear()
                        peer?.publishSnapshot(immediate: true)
                    }
                    .disabled(!canDraw || (strokes.isEmpty && currentStroke.isEmpty))
                }
            }
        }
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(1, max(0, point.x / size.width)),
            y: min(1, max(0, point.y / size.height))
        )
    }

    private func draw(_ normalizedPoints: [CGPoint], in context: GraphicsContext, size: CGSize) {
        guard !normalizedPoints.isEmpty else { return }
        let points = normalizedPoints.map {
            CGPoint(x: $0.x * size.width, y: $0.y * size.height)
        }
        let lineWidth = size.width / 75

        if let first = points.first, points.count == 1 {
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
