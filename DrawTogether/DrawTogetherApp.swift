import SwiftUI

@main
struct DrawTogetherApp: App {
    @State private var canvas = CanvasModel()

    var body: some Scene {
        WindowGroup {
            DrawingView(canvas: canvas)
        }
    }
}
