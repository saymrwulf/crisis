import SwiftUI
import AppKit

/// AppDelegate handles two things:
///
/// 1. **Activation policy** — when CrisisViz is launched unbundled (e.g. via
///    `swift run CrisisViz` during development) macOS defaults to
///    `.accessory`, which hides it from the Dock and menu bar. Forcing
///    `.regular` makes it behave like a real native app even without a
///    `.app` bundle.
///
/// 2. **Window placement** — by default SwiftUI's `.defaultSize` is taken
///    literally and macOS may place the window so it overlaps the Dock or
///    spills off-screen. We snap the main window to the screen's
///    `visibleFrame` (which already excludes Dock + menu bar regardless of
///    the user's Dock position) inset by a small margin, and center it.
///    This is the macOS HIG-recommended approach for "fill the available
///    workspace without fighting the OS chrome".
@MainActor
final class CrisisAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let edgeInset: CGFloat = 32
    static let minContentSize = NSSize(width: 960, height: 640)

    /// Toggle to print every resize event to stderr. Pass `--debug-resize`
    /// on launch to enable. Use this when the user reports a "won't resize"
    /// regression so we can see exactly what NSWindow is doing.
    private static var debugResize: Bool {
        CommandLine.arguments.contains("--debug-resize")
    }
    private weak var managedWindow: NSWindow?

    /// Pure resize-clamp logic, extracted so the testbed can unit-test it
    /// without spinning up an NSWindow. Rules:
    ///   - never below `minContentSize`
    ///   - never above the screen's `visibleFrame` (prevents pushing past
    ///     menu bar / Dock, which on macOS 15+ triggers automatic tiling)
    /// `visibleSize` may be nil (test harness with no screen).
    static func clampResize(proposed: NSSize, visibleSize: CGSize?) -> NSSize {
        let minW = minContentSize.width
        let minH = minContentSize.height
        let maxW: CGFloat = visibleSize?.width  ?? .greatestFiniteMagnitude
        let maxH: CGFloat = visibleSize?.height ?? .greatestFiniteMagnitude
        return NSSize(
            width:  min(maxW, max(minW, proposed.width)),
            height: min(maxH, max(minH, proposed.height))
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Defer the layout until SwiftUI has actually created its window —
        // querying NSApp.windows synchronously here returns an empty list.
        DispatchQueue.main.async { [weak self] in
            self?.fitMainWindowToScreen()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Resize and center the first content window inside the active screen's
    /// `visibleFrame`. Also installs a minimum content size so the user can
    /// shrink the window but never below something usable.
    ///
    /// Why this is fiddly: SwiftUI's `.windowResizability(.contentMinSize)`
    /// sets `window.maxSize` based on the content's *current ideal* size
    /// rather than treating "no max" as actually unbounded. The user-visible
    /// symptom is that the LEFT edge can be dragged (because moving the
    /// window's origin doesn't trip the max-size check) but the right, top,
    /// bottom, and corner handles silently refuse to grow. We fix this by:
    ///   1. Owning the window's resize lifecycle via NSWindowDelegate, and
    ///   2. Returning whatever size the user requests from `windowWillResize`
    ///      as long as it stays above the minimum.
    /// We also explicitly write infinity into both `maxSize` and
    /// `contentMaxSize` so even code paths that bypass our delegate land on
    /// "unbounded".
    @MainActor
    private func fitMainWindowToScreen() {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else { return }
        managedWindow = window
        configure(window: window)

        // SwiftUI sometimes installs its own NSWindowDelegate when the window
        // becomes key (e.g., after a fullscreen toggle or a window-tab event),
        // silently displacing ours. Re-assert on every key change.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reattachDelegate(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func reattachDelegate(_ note: Notification) {
        guard let win = note.object as? NSWindow,
              win === managedWindow,
              win.delegate !== self
        else { return }
        if Self.debugResize { NSLog("[CrisisViz] re-attaching delegate (was: \(String(describing: win.delegate)))") }
        win.delegate = self
    }

    @MainActor
    private func configure(window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        // Take ownership of the resize lifecycle.
        window.delegate = self

        // Guarantee resize is enabled and clear every upper bound we know about.
        window.styleMask.insert(.resizable)
        window.minSize        = Self.minContentSize
        window.maxSize        = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                       height: CGFloat.greatestFiniteMagnitude)
        window.contentMinSize = Self.minContentSize
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                       height: CGFloat.greatestFiniteMagnitude)
        window.resizeIncrements = NSSize(width: 1, height: 1)

        // Initial size: 80% of visibleFrame, centered. We deliberately do NOT
        // touch the edges of the visible frame at startup, because on macOS
        // Tahoe a window flush against the menu bar / Dock is treated as a
        // tiling candidate as soon as the user begins dragging, which locks
        // height. An 80%-centered window has clearance on every edge, so
        // tiling is never armed.
        let w = visible.width  * 0.80
        let h = visible.height * 0.80
        let target = NSRect(
            x: visible.minX + (visible.width  - w) / 2,
            y: visible.minY + (visible.height - h) / 2,
            width: max(Self.minContentSize.width, w),
            height: max(Self.minContentSize.height, h)
        )
        window.setFrame(target, display: true, animate: false)

        window.collectionBehavior.insert(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenDisallowsTiling)
    }

    // MARK: - NSWindowDelegate

    /// Cap proposed sizes at the screen's visibleFrame. Returning a size that
    /// pushes past the menu bar makes macOS 15+/Tahoe interpret the drag as
    /// a tile gesture, after which only one edge remains user-controllable.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let visible = (sender.screen ?? NSScreen.main)?.visibleFrame.size
        let result = Self.clampResize(proposed: frameSize, visibleSize: visible)
        if Self.debugResize {
            NSLog("[CrisisViz] willResize proposed=\(frameSize) visible=\(visible ?? .zero) result=\(result) currentFrame=\(sender.frame)")
        }
        return result
    }

    func windowDidResize(_ notification: Notification) {
        guard Self.debugResize, let window = notification.object as? NSWindow else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let nearTop    = abs(window.frame.maxY - visible.maxY) < 2
        let nearBottom = abs(window.frame.minY - visible.minY) < 2
        let nearLeft   = abs(window.frame.minX - visible.minX) < 2
        let nearRight  = abs(window.frame.maxX - visible.maxX) < 2
        NSLog("[CrisisViz] didResize frame=\(window.frame) edges_touched=[T:\(nearTop) B:\(nearBottom) L:\(nearLeft) R:\(nearRight)]")
    }
}

@main
struct CrisisApp: App {
    @NSApplicationDelegateAdaptor(CrisisAppDelegate.self) private var appDelegate

    @State private var captureRequested = CommandLine.arguments.contains("--capture")
        || CommandLine.arguments.contains("--testbed")

    /// Global UI settings (text scale, etc.). Lives at the App level so it
    /// survives the entire process and feeds every Scene/View via .environment.
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup("CrisisViz") {
            ImmersiveView()
                .environment(settings)
                // Explicit min/max frame on the root content. With
                // `.windowResizability(.contentSize)` below, SwiftUI uses
                // these as the window's size bounds — `maxWidth/Height: .infinity`
                // means no upper cap from the SwiftUI side. Our delegate then
                // adds a runtime cap at the screen's visibleFrame.
                .frame(
                    minWidth:  CrisisAppDelegate.minContentSize.width,
                    maxWidth:  .infinity,
                    minHeight: CrisisAppDelegate.minContentSize.height,
                    maxHeight: .infinity
                )
                .task {
                    if captureRequested {
                        await SceneCapture.captureAll()
                        NSApplication.shared.terminate(nil)
                    }
                }
        }
        // .hiddenTitleBar removes the macOS title-bar chrome (traffic lights
        // remain, floating over content). Without this, our `.ignoresSafeArea()`
        // content — including the inspector's top header — gets clipped by the
        // ~28pt title bar.
        .windowStyle(.hiddenTitleBar)
        // .contentSize honors the content's frame min/max above. Previously
        // we used .contentMinSize which silently capped maxSize at the
        // content's idealSize and made every edge except the left feel dead.
        .windowResizability(.contentSize)
        .defaultSize(width: 1400, height: 900)
    }
}
