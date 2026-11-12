import SwiftUI

struct FreeDrawView: View {
    @State private var session: FreeDrawSession?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let session {
                drawingRoom(session)
            } else {
                entryScreen
            }
        }
        .background {
            LinearGradient(
                colors: [.indigo.opacity(0.16), .mint.opacity(0.16), Color(uiColor: .systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .tint(.indigo)
        .navigationTitle("Free Draw")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var entryScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "scribble.variable")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)

                Text("Draw together")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Share a canvas with anyone on the same Wi-Fi.")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 14)

                roomButton("Host Free Draw", icon: "plus", hosting: true)
                roomButton("Join Free Draw", icon: "arrow.right", hosting: false)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private func roomButton(_ title: String, icon: String, hosting: Bool) -> some View {
        Button {
            connect(hosting: hosting)
        } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(hosting ? .indigo : Color(uiColor: .secondarySystemBackground))
        .foregroundStyle(hosting ? Color.white : Color.primary)
        .buttonBorderShape(.roundedRectangle(radius: 14))
    }

    private func drawingRoom(_ session: FreeDrawSession) -> some View {
        DrawingSurface(layers: session.layers, canDraw: session.canDraw, cornerRadius: 16, backdrop: .clear) { point, finished in
            guard session.canDraw, let penColor = session.penColor else { return }
            if finished {
                session.canvas.finishStroke(at: point, color: penColor)
            } else {
                session.canvas.appendPoint(point, color: penColor)
            }
            session.publishInk(immediate: finished)
        }
        .padding(8)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                if session.canDraw, let color = session.penColor {
                    Circle()
                        .fill(color.displayColor)
                        .frame(width: 18, height: 18)
                        .accessibilityLabel("Your pen color is \(color.rawValue)")
                }
                Text(session.status)
                    .font(.footnote.weight(.medium))
                Spacer(minLength: 0)
                Button("Leave") { self.session = nil }
                    .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear My Ink", systemImage: "eraser") {
                    session.canvas.clear()
                    session.publishInk(immediate: true)
                }
                .disabled(!session.canDraw)
            }
        }
    }

    private func connect(hosting: Bool) {
        errorMessage = nil
        do {
            session = try FreeDrawSession(hosting: hosting)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
