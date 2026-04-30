import SwiftUI
import AppKit

/// AppDelegate exists for one reason: when CrisisViz is launched unbundled
/// (e.g. via `swift run CrisisViz` during development) macOS defaults the
/// activation policy to `.accessory`, which means no Dock tile, no menu-bar
/// presence, and no Cmd-Tab visibility. Forcing `.regular` here makes the
/// running app behave like a real native app even without a `.app` bundle.
final class CrisisAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CrisisApp: App {
    @NSApplicationDelegateAdaptor(CrisisAppDelegate.self) private var appDelegate

    @State private var captureRequested = CommandLine.arguments.contains("--capture")
        || CommandLine.arguments.contains("--testbed")

    var body: some Scene {
        WindowGroup("CrisisViz") {
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
