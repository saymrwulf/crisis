import SwiftUI

/// Liquid Glass narration overlay — positioned bottom-left, never blocks the center canvas.
struct GlassNarration: View {
    let title: String
    let narration: String
    let chapterTitle: String
    let chapterIndex: Int
    let sceneIndex: Int
    let sceneCount: Int
    let globalSceneIndex: Int
    let totalScenes: Int
    @Binding var isExpanded: Bool
    @Namespace private var narrationNS

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 8) {
                // Position badge + chapter title + collapse toggle
                HStack(spacing: 8) {
                    Text("CH \(chapterIndex).\(sceneIndex)")
                        .scaledFont(size: 11, weight: .heavy, design: .monospaced)
                        .foregroundStyle(.yellow.opacity(0.95))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.yellow.opacity(0.15))
                        )
                    Text("(\(globalSceneIndex + 1)/\(totalScenes))")
                        .scaledFont(size: 10, weight: .regular, design: .monospaced)
                        .foregroundStyle(.secondary.opacity(0.7))
                    Text(chapterTitle)
                        .scaledFont(size: 10, weight: .bold, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("narration-toggle", in: narrationNS)
                }

                if isExpanded {
                    // Scene title
                    Text(title)
                        .scaledFont(size: 13, weight: .bold, design: .monospaced)
                        .foregroundStyle(.primary)

                    // Body text
                    Text(narration)
                        .scaledFont(size: 11, weight: .regular, design: .monospaced)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: 340, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .glassEffectID("narration-panel", in: narrationNS)
        }
    }
}
