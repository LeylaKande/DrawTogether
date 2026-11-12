import SwiftUI

struct DrawingView: View {
    let canvas: CanvasModel

    @State private var host: Host?
    @State private var guest: Guest?
    @State private var joinCode = ""
    @FocusState private var isJoinCodeFocused: Bool
    @State private var penColor: CanvasModel.PenColor = .black
    @State private var connectionStatus = "Offline"
    @State private var showsIdeas = false
    @State private var ideas: [String] = []
    @State private var promptDeck = DrawingView.prompts.shuffled()

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
            .background {
                LinearGradient(
                    colors: [.indigo.opacity(0.16), .mint.opacity(0.14), Color(uiColor: .systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .tint(.indigo)
            .navigationTitle(host == nil && guest == nil ? "" : "Draw Together")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: canDraw) { _, canDraw in
                if !canDraw {
                    showsIdeas = false
                    ideas = []
                }
            }
        }
    }

    private var startScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 36, weight: .medium))
                        .accessibilityHidden(true)
                    Text("Draw Together")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Take turns drawing while everyone else guesses.")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        canvas.clear()
                        connectionStatus = "Starting session…"
                        do {
                            host = try Host(canvas: canvas) { connectionStatus = $0 }
                        } catch {
                            connectionStatus = "Host unavailable: \(error.localizedDescription)"
                        }
                    } label: {
                        Label("Host Session", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)

                    Divider()

                    TextField("5-digit session code", text: $joinCode)
                        .font(.title3.monospacedDigit())
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .focused($isJoinCodeFocused)
                        .accessibilityLabel("5-digit session code")
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(uiColor: .secondarySystemBackground))
                                .contentShape(Rectangle())
                                .onTapGesture { isJoinCodeFocused = true }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isJoinCodeFocused ? Color.indigo : Color.secondary.opacity(0.3))
                                .allowsHitTesting(false)
                        }

                    Button {
                        isJoinCodeFocused = false
                        canvas.clear()
                        connectionStatus = "Looking for session \(joinCode)…"
                        guest = Guest(code: joinCode, canvas: canvas) { connectionStatus = $0 }
                    } label: {
                        Label("Join Session", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!PeerConnection.isValidSessionCode(joinCode))

                    if connectionStatus != "Offline" {
                        Text(connectionStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))

                NavigationLink {
                    FreeDrawView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "pencil.and.scribble")
                        Text("Free Draw Experiment")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.headline)
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
    }

    private var lobby: some View {
        VStack(spacing: 16) {
            Text(isPaused ? "Game Paused" : "Lobby")
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if let code = host?.code ?? guest?.code {
                VStack(spacing: 6) {
                    Text("Session code")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .foregroundStyle(.indigo)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
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
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var game: some View {
        let strokes = canvas.snapshot.strokes
        let currentStroke = canvas.snapshot.currentStroke

        return DrawingSurface(layers: [canvas.snapshot], canDraw: canDraw, cornerRadius: 12, backdrop: .clear) { point, finished in
            guard canDraw else { return }
            if finished {
                canvas.finishStroke(at: point, color: penColor)
            } else {
                canvas.appendPoint(point, color: penColor)
            }
            publishSnapshot(immediate: finished)
        }
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
                    Button {
                        host?.requestTurn()
                        guest?.requestTurn()
                    } label: {
                        Label(guest?.isRequestingTurn == true ? "Taking Turn…" : "Take Turn", systemImage: "pencil")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(guest?.isRequestingTurn == true)
                }
                Button("Leave", action: leaveSession)
                    .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canDraw {
                    ideasButton
                }
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

    private var ideasButton: some View {
        Button {
            shuffleIdeas()
            showsIdeas = true
        } label: {
            Label("Ideas", systemImage: "lightbulb")
        }
        .popover(isPresented: $showsIdeas) {
            IdeasPopover(ideas: $ideas, onShuffle: shuffleIdeas)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func shuffleIdeas() {
        var nextIdeas: [String] = []
        for _ in 0..<3 {
            if promptDeck.isEmpty {
                promptDeck = Self.prompts.shuffled()
            }
            if let index = promptDeck.lastIndex(where: { !nextIdeas.contains($0) }) {
                nextIdeas.append(promptDeck.remove(at: index))
            }
        }
        ideas = nextIdeas
    }

    private var penPalette: some View {
        HStack(spacing: 12) {
            ForEach(CanvasModel.PenColor.allCases, id: \.self) { color in
                Button {
                    penColor = color
                } label: {
                    Circle()
                        .fill(color.displayColor)
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
}

private struct IdeasPopover: View {
    @Binding var ideas: [String]
    let onShuffle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ideas, id: \.self) { idea in
                Text(idea)
            }
            Button("Shuffle", systemImage: "shuffle", action: onShuffle)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

private extension DrawingView {
    static let prompts = [
        "Der König der Löwen",
        "Blumenbeet",
        "Tom und Jerry",
        "Findet Nemo",
        "Jurassic Park",
        "Der Zauberer von Oz",
        "Geldwäsche",
        "Treppenhaus",
        "Lesebrille",
        "Taschenrechner",
        "Zahnrad",
        "Leiter",
        "Apfel",
        "Fenster",
        "Stuhl",
        "Tisch",
        "Spinne",
        "Hut",
        "Pizza",
        "Schuh",
        "Stern",
        "Schmetterling",
        "Lampe",
        "Kokosnuss",
        "Auto",
        "Segelboot",
        "Ball",
        "Flugdrachen",
        "Tasse",
        "Herz",
        "Katze",
        "Schatztruhe",
        "Iglu",
        "Burg",
        "Aquarium",
        "Elefant",
        "Piratenschiff",
        "Schneemann",
        "Meerjungfrau",
        "Skateboard",
        "Vogelscheuche",
        "Helikopter",
        "Surfbrett",
        "Vogelhäuschen",
        "Vulkan",
        "Gitarre",
        "Teleskop",
        "Trampolin",
        "Lagerfeuer",
        "Rakete",
    ]
}
