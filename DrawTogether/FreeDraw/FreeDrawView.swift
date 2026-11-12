import SwiftUI

struct FreeDrawView: View {
    @State private var session: FreeDrawSession?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let session {
                DrawingSurface(layers: session.layers, canDraw: session.canDraw) { point, finished in
                    guard session.canDraw, let penColor = session.penColor else { return }
                    if finished {
                        session.canvas.finishStroke(at: point, color: penColor)
                    } else {
                        session.canvas.appendPoint(point, color: penColor)
                    }
                    session.publishInk(immediate: finished)
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Text(session.status)
                            .font(.footnote)
                        Spacer()
                        if session.canDraw, let color = session.penColor {
                            Circle()
                                .fill(color.displayColor)
                                .frame(width: 20, height: 20)
                                .accessibilityLabel("Your pen color is \(color.rawValue)")
                        }
                        Button("Leave") { self.session = nil }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.bar)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear My Ink") {
                            session.canvas.clear()
                            session.publishInk(immediate: true)
                        }
                        .disabled(!session.canDraw)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Button("Host Free Draw") { connect(hosting: true) }
                        .buttonStyle(.borderedProminent)
                    Button("Join Free Draw") { connect(hosting: false) }
                        .buttonStyle(.bordered)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Free Draw")
        .navigationBarTitleDisplayMode(.inline)
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
