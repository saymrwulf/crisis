import SwiftUI

@main
struct CrisisApp: App {
    @State private var captureRequested = CommandLine.arguments.contains("--capture")
        || CommandLine.arguments.contains("--testbed")

    var body: some Scene {
        WindowGroup {
            ImmersiveView()
                .task {
                    if captureRequested {
                        await SceneCapture.captureAll()
                        NSApplication.shared.terminate(nil)
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1400, height: 900)
    }
}
