import SwiftUI

/// Liquid Glass bottom control bar — play/pause, navigation, speed, progress dots.
struct GlassControls: View {
    @Bindable var engine: SceneEngine
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 16) {
                // Navigation cluster
                HStack(spacing: 4) {
                    navButton(icon: "backward.end.fill") { engine.goTo(global: 0) }
                    navButton(icon: "chevron.left") { engine.previous() }
                    playButton
                    navButton(icon: "chevron.right") { engine.next() }
                    navButton(icon: "forward.end.fill") { engine.goTo(global: engine.totalScenes - 1) }
                }
                .glassEffect(.regular, in: .capsule)

                Spacer()

                // Progress dots
                progressDots
                    .glassEffect(.regular, in: .capsule)

                Spacer()

                // Speed + counter + settings
                HStack(spacing: 8) {
                    navButton(icon: "minus") { engine.adjustSpeed(delta: -0.25) }
                    Text(String(format: "%.1fx", engine.speed))
                        .scaledFont(size: 11, weight: .bold, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                    navButton(icon: "plus") { engine.adjustSpeed(delta: 0.25) }

                    Text("\(engine.currentGlobal + 1)/\(engine.totalScenes)")
                        .scaledFont(size: 11, weight: .medium, design: .monospaced)
                        .foregroundStyle(.tertiary)

                    settingsButton
                }
                .glassEffect(.regular, in: .capsule)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    /// Gear button → text-scale slider popover. Lives on the right side of
    /// the control bar so it doesn't fight the play/transport cluster on the
    /// left.
    private var settingsButton: some View {
        Button {
            showSettings.toggle()
        } label: {
            Image(systemName: "textformat.size")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .help("Adjust text size")
        .popover(isPresented: $showSettings, arrowEdge: .top) {
            TextScalePopover(settings: settings)
                .padding(16)
                .frame(width: 260)
        }
    }

    private var playButton: some View {
        Button {
            engine.togglePlay()
        } label: {
            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 36, height: 30)
        }
        .buttonStyle(.glass)
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
    }

    private var progressDots: some View {
        HStack(spacing: 4) {
            ForEach(AllChapters.list) { chapter in
                let isCurrentChapter = chapter.id == engine.address.chapter
                let isPast = chapter.id < engine.address.chapter
                Circle()
                    .fill(isCurrentChapter ? Color.white : isPast ? Color.white.opacity(0.6) : Color.white.opacity(0.2))
                    .frame(width: isCurrentChapter ? 8 : 5, height: isCurrentChapter ? 8 : 5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Text-scale popover

/// Continuous slider for the global text-size multiplier. Bound to
/// `AppSettings.textScale`; every other view that uses `.scaledFont(...)` or
/// `settings.scaled(...)` reacts immediately.
private struct TextScalePopover: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Text size")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f%%", settings.textScale * 100))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }

            Slider(
                value: $settings.textScale,
                in: AppSettings.textScaleMin...AppSettings.textScaleMax,
                step: 0.01
            )

            HStack {
                Button("Reset") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.textScale = 1.0
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                Text("A")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text("A")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
