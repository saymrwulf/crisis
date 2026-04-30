import SwiftUI

/// Liquid Glass bottom control bar — play/pause, navigation, speed, progress dots.
struct GlassControls: View {
    @Bindable var engine: SceneEngine

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

                // Speed + counter
                HStack(spacing: 8) {
                    navButton(icon: "minus") { engine.adjustSpeed(delta: -0.25) }
                    Text(String(format: "%.1fx", engine.speed))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                    navButton(icon: "plus") { engine.adjustSpeed(delta: 0.25) }

                    Text("\(engine.currentGlobal + 1)/\(engine.totalScenes)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .glassEffect(.regular, in: .capsule)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
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
