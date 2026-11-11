import SwiftUI

struct DrawingView: View {
    let canvas: CanvasModel

    @State private var host: Host?
    @State private var guest: Guest?
    @State private var joinCode = ""
    @State private var connectionStatus = "Offline"

    private let canvasAspectRatio: CGFloat = 3.0 / 4.0

    private var canDraw: Bool { host?.canDraw ?? guest?.canDraw ?? false }
    private var canTakeTurn: Bool { host?.canTakeTurn ?? guest?.canTakeTurn ?? false }
    private var playerCount: Int? { host?.playerCount ?? guest?.playerCount }

    var body: some View {
        NavigationStack {
            Group {
                if host?.hasStarted == true || guest?.hasStarted == true {
                    game
                } else if host != nil || guest != nil {
                    lobby
                } else {
                    startScreen
                }
            }
            .navigationTitle("Draw Together")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var startScreen: some View {
        VStack(spacing: 16) {
            Button("Host Session") {
                canvas.clear()
                connectionStatus = "Starting session…"
                do {
                    host = try Host(canvas: canvas) { connectionStatus = $0 }
                } catch {
                    connectionStatus = "Host unavailable: \(error.localizedDescription)"
                }
            }
            .buttonStyle(.borderedProminent)

            TextField("5-digit session code", text: $joinCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .accessibilityLabel("5-digit session code")

            Button("Join Session") {
                canvas.clear()
                connectionStatus = "Looking for session \(joinCode)…"
                guest = Guest(code: joinCode, canvas: canvas) { connectionStatus = $0 }
            }
            .buttonStyle(.bordered)
            .disabled(!PeerConnection.isValidSessionCode(joinCode))

            if connectionStatus != "Offline" {
                Text(connectionStatus)
                    .font(.footnote)
            }
        }
        .padding()
    }

    private var lobby: some View {
        VStack(spacing: 16) {
            Text("Lobby")
                .font(.title)
            if let code = host?.code ?? guest?.code {
                Text("Session code")
                    .font(.subheadline)
                Text(code)
                    .font(.largeTitle.monospacedDigit())
                    .textSelection(.enabled)
            }
            if let playerCount {
                Text("Players in session: \(playerCount)")
                    .font(.headline)
            }
            Text(connectionStatus)
                .font(.footnote)
            if let playerCount {
                if host == nil {
                    Text("Waiting for the host to start…")
                        .font(.footnote)
                }
                Button("Start Game") {
                    host?.startGame()
                }
                .buttonStyle(.borderedProminent)
                .disabled(host == nil || playerCount < 2)
            }
            Button("Leave Session", action: leaveSession)
                .buttonStyle(.bordered)
        }
        .padding()
    }

    private var game: some View {
        let strokes = canvas.snapshot.strokes
        let currentStroke = canvas.snapshot.currentStroke

        return GeometryReader { geometry in
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
                        publishSnapshot(immediate: false)
                    }
                    .onEnded { value in
                        guard canDraw, size.width > 0 else { return }
                        canvas.finishStroke(at: normalized(value.location, in: size))
                        publishSnapshot(immediate: true)
                    },
                including: canDraw ? .all : .none
            )
            .accessibilityLabel("Drawing canvas")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                VStack(alignment: .leading) {
                    if guest != nil {
                        Text(connectionStatus)
                    }
                    Text(canDraw ? "You’re drawing" : "You’re watching")
                }
                .font(.footnote)
                Spacer()
                if canTakeTurn || guest?.isRequestingTurn == true {
                    Button(guest?.isRequestingTurn == true ? "Taking Turn…" : "Take Turn") {
                        host?.requestTurn()
                        guest?.requestTurn()
                    }
                    .disabled(guest?.isRequestingTurn == true)
                }
                Button("Leave", action: leaveSession)
            }
            .buttonStyle(.bordered)
            .padding()
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    canvas.clear()
                    publishSnapshot(immediate: true)
                }
                .disabled(!canDraw || (strokes.isEmpty && currentStroke.isEmpty))
            }
        }
    }

    private func publishSnapshot(immediate: Bool) {
        host?.publishSnapshot(immediate: immediate)
        guest?.publishSnapshot(immediate: immediate)
    }

    private func leaveSession() {
        host = nil
        guest = nil
        canvas.clear()
        connectionStatus = "Offline"
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
