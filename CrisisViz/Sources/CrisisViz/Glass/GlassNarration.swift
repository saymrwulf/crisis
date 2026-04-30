import SwiftUI

/// Liquid Glass narration overlay — positioned bottom-left, never blocks the center canvas.
struct GlassNarration: View {
    let title: String
    let narration: String
    let chapterTitle: String
    @Binding var isExpanded: Bool
    @Namespace private var narrationNS

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 8) {
                // Chapter badge + collapse toggle
                HStack(spacing: 6) {
                    Text(chapterTitle)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
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
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    // Body text
                    Text(narration)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
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
