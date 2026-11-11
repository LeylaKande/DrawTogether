import SwiftUI

struct DrawingView: View {
    let canvas: CanvasModel

    @State private var host: Host?
    @State private var guest: Guest?
    @State private var joinCode = ""
    @State private var penColor: CanvasModel.PenColor = .black
    @State private var connectionStatus = "Offline"

    private let canvasAspectRatio: CGFloat = 3.0 / 4.0

    private var canDraw: Bool { host?.canDraw ?? guest?.canDraw ?? false }
    private var canTakeTurn: Bool { host?.canTakeTurn ?? guest?.canTakeTurn ?? false }
    private var isPaused: Bool { host?.isPaused ?? guest?.isPaused ?? false }
    private var playerCount: Int? { host?.playerCount ?? guest?.playerCount }

    var body: some View {
        NavigationStack {
            Group {
                if !isPaused && (host?.hasStarted == true || guest?.hasStarted == true) {
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
            Text(isPaused ? "Game Paused" : "Lobby")
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
                if isPaused && host == nil {
                    Text("Waiting for the host to resume…")
                        .font(.footnote)
                }
                if isPaused {
                    Button("Resume Game") {
                        host?.resumeGame()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(host?.canResume != true)
                    if host?.canResume == false {
                        Text("Waiting for the drawer’s canvas…")
                            .font(.footnote)
                    }
                } else {
                    Button("Start Game") {
                        host?.startGame()
                        guest?.requestStart()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(playerCount < 2)
                }
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
                if let currentStroke {
                    draw(currentStroke, in: context, size: size)
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
                        canvas.appendPoint(normalized(value.location, in: size), color: penColor)
                        publishSnapshot(immediate: false)
                    }
                    .onEnded { value in
                        guard canDraw, size.width > 0 else { return }
                        canvas.finishStroke(at: normalized(value.location, in: size), color: penColor)
                        publishSnapshot(immediate: true)
                    },
                including: canDraw ? .all : .none
            )
            .accessibilityLabel("Drawing canvas")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemGray5))
        .safeAreaInset(edge: .top, spacing: 0) {
            penPalette
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                VStack(alignment: .leading) {
                    if let lobbyError = host?.lobbyError {
                        Text(lobbyError)
                    } else if guest != nil {
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let host {
                    Menu {
                        Button("Add Player", systemImage: "person.badge.plus") {
                            host.pauseToAddPlayer()
                        }
                    } label: {
                        Label("Players", systemImage: "person.badge.plus")
                    }
                    .disabled(!host.canPause)
                }
                Button("Clear") {
                    canvas.clear()
                    publishSnapshot(immediate: true)
                }
                .disabled(!canDraw || (strokes.isEmpty && currentStroke == nil))
            }
        }
    }

    private var penPalette: some View {
        HStack(spacing: 12) {
            ForEach(CanvasModel.PenColor.allCases, id: \.self) { color in
                Button {
                    penColor = color
                } label: {
                    Circle()
                        .fill(displayColor(color))
                        .frame(width: 28, height: 28)
                        .overlay {
                            if color == penColor {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.rawValue.capitalized)
                .accessibilityAddTraits(color == penColor ? .isSelected : [])
            }
        }
        .disabled(!canDraw)
        .opacity(canDraw ? 1 : 0.55)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func displayColor(_ color: CanvasModel.PenColor) -> Color {
        switch color {
        case .black: .black
        case .red: .red
        case .blue: .blue
        case .green: Color(red: 0, green: 0.5, blue: 0.2)
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

    private func draw(_ stroke: CanvasModel.Stroke, in context: GraphicsContext, size: CGSize) {
        let ink = displayColor(stroke.color)
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
