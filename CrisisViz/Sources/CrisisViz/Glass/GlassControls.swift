import SwiftUI

/// Liquid Glass bottom control bar — a film-editor-style transport with
/// signed speed (reverse playback) and a chapter-position scrubber.
///
/// The viewer is the master of time:
///   - Speed slider: −16× … 0 (frozen) … +16×. Pull it left for reverse.
///   - Position scrubber: drag freely along the chapter's continuous
///     timeline, in either direction. Snaps to scene starts on click.
struct GlassControls: View {
    @Bindable var engine: SceneEngine
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false
    /// Local mirror of the live chapter position so SwiftUI's Slider has
    /// a binding it can drive without round-tripping through the engine
    /// during a drag. Updated from the engine via `.task`/`.onReceive`
    /// equivalents — here we just refresh on appear/each frame.
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let livePosition = engine.chapterPosition(at: timeline.date)
            GlassEffectContainer {
                VStack(spacing: 6) {
                    // Top row: position scrubber across the chapter.
                    chapterScrubber(livePosition: livePosition)

                    // Bottom row: play/pause + speed slider + chapter dots + settings.
                    HStack(spacing: 16) {
                        playButton

                        speedControl

                        Spacer()

                        progressDots

                        Spacer()

                        navCluster

                        settingsButton
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .onAppear { scrubPosition = livePosition }
            .onChange(of: livePosition) { _, new in
                if !isScrubbing { scrubPosition = new }
            }
        }
    }

    // MARK: - Chapter scrubber (top row)

    private func chapterScrubber(livePosition: Double) -> some View {
        HStack(spacing: 10) {
            Text(String(format: "%.1fs", scrubPosition))
                .scaledFont(size: 10, weight: .medium, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubPosition },
                    set: { newValue in
                        scrubPosition = newValue
                        engine.setChapterPosition(newValue)
                    }
                ),
                in: 0...max(0.01, engine.currentChapterDuration),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        // Sync any drift after release.
                        scrubPosition = engine.chapterPosition(at: Date())
                    }
                }
            )
            .controlSize(.small)
            .tint(.white.opacity(0.9))

            Text(String(format: "%.0fs", engine.currentChapterDuration))
                .scaledFont(size: 10, weight: .medium, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Speed slider (signed)

    private var speedControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "backward.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)

            Slider(
                value: Binding(
                    get: { engine.speed },
                    set: { engine.setSpeed($0) }
                ),
                in: SceneEngine.speedMin...SceneEngine.speedMax
            )
            .controlSize(.small)
            .frame(width: 160)
            .tint(speedTint)

            Image(systemName: "forward.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)

            Text(speedLabel)
                .scaledFont(size: 10, weight: .heavy, design: .monospaced)
                .foregroundStyle(.primary)
                .frame(width: 56, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }

    private var speedTint: Color {
        if engine.speed > 0.05 { return .green.opacity(0.8) }
        if engine.speed < -0.05 { return .orange.opacity(0.8) }
        return .gray.opacity(0.8)
    }

    private var speedLabel: String {
        if abs(engine.speed) < 0.05 { return "❚❚ 0×" }
        return String(format: "%+.2f×", engine.speed)
    }

    // MARK: - Cast clusters / play / dots / settings

    private var playButton: some View {
        Button {
            engine.togglePlay()
        } label: {
            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.glass)
    }

    private var navCluster: some View {
        HStack(spacing: 4) {
            navButton(icon: "backward.end.fill") { engine.goTo(global: 0) }
            navButton(icon: "chevron.left") { engine.previous() }
            navButton(icon: "chevron.right") { engine.next() }
            navButton(icon: "forward.end.fill") { engine.goTo(global: engine.totalScenes - 1) }
        }
        .glassEffect(.regular, in: .capsule)
    }

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

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
    }

    private var progressDots: some View {
        HStack(spacing: 4) {
            ForEach(AllChapters.list) { chapter in
                let isCurrentChapter = chapter.id == engine.address.chapter
                let isPast = chapter.id < engine.address.chapter
                Circle()
                    .fill(isCurrentChapter ? Color.white
                          : isPast ? Color.white.opacity(0.6)
                          : Color.white.opacity(0.2))
                    .frame(width: isCurrentChapter ? 8 : 5,
                           height: isCurrentChapter ? 8 : 5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Text-scale popover

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
                Text("A").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                Text("A").font(.system(size: 18, weight: .bold)).foregroundStyle(.tertiary)
            }
        }
    }
}
