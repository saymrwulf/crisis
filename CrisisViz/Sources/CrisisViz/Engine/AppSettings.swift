import SwiftUI

/// App-wide UI settings injected via `.environment(...)` at the Scene root.
///
/// Currently only carries the global text-size scale, but is the natural place
/// for any future user-tunable rendering preferences.
@MainActor
@Observable
final class AppSettings {
    /// Text scale multiplier applied to every `.scaledFont(...)` call site,
    /// including text drawn inside `Canvas` (those sites read it explicitly
    /// via `settings.scaled(_:)`).
    ///
    /// Range chosen by trying out the live app: 0.85× still readable on
    /// large monitors, 1.6× comfortable for screen-sharing / projection.
    var textScale: Double = 1.0

    static let textScaleMin: Double = 0.85
    static let textScaleMax: Double = 1.6

    /// Convenience for Canvas-rendered text, where Environment is not
    /// available — chapter views capture `settings` and call this on every
    /// font size before constructing a `Font`.
    func scaled(_ size: CGFloat) -> CGFloat {
        size * CGFloat(textScale)
    }
}

// MARK: - .scaledFont(size:weight:design:) view modifier
//
// `AppSettings` is injected via the @Observable mechanism — `.environment(settings)`
// at the Scene root makes it available to every view via
// `@Environment(AppSettings.self)`. No custom EnvironmentKey needed.
//
// Drop-in replacement for `.font(.system(size:weight:design:))` that respects
// the user's textScale slider. SwiftUI views inside the AppSettings
// environment can use this anywhere they would have used `.font(...)`.

extension View {
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(AppSettings.self) private var settings
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: settings.scaled(size), weight: weight, design: design))
    }
}
