import SwiftUI

/// Persistent left-edge cast strip. Always visible, in every chapter, with
/// the cast members in fixed lane order (Aaron → Ben → Carl → Dave). The
/// vertical position of each card lines up with the lane that validator
/// occupies in the chapter canvas, so the viewer can trace "this card →
/// that lane" without thinking.
///
/// Width is fixed (`Self.width`) and the chapter HStack subtracts that
/// width from its available space, so chapters never have to know the
/// sidebar exists — they just see a slightly narrower canvas.
struct CastSidebar: View {
    static let width: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CAST")
                .scaledFont(size: 11, weight: .heavy, design: .monospaced)
                .foregroundStyle(.white.opacity(0.45))
                .tracking(2)
                .padding(.bottom, 4)

            ForEach(Cast.leads, id: \.id) { role in
                CastCard(role: role)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 24)
        .frame(width: Self.width, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.20),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

private struct CastCard: View {
    let role: CastRole

    var body: some View {
        HStack(spacing: 10) {
            // Color swatch — same color the vertices for this validator wear.
            Circle()
                .fill(role.color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.35), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(role.displayName)
                        .scaledFont(size: 13, weight: .heavy, design: .monospaced)
                        .foregroundStyle(.white.opacity(0.92))
                    if role.isByzantineSlot {
                        Text("BYZ")
                            .scaledFont(size: 8, weight: .heavy, design: .monospaced)
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.red.opacity(0.6), lineWidth: 0.8)
                            )
                    }
                }
                Text(role.cue)
                    .scaledFont(size: 9, weight: .medium, design: .monospaced)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Persistent right-edge legend. Lists the encoding rules that hold across
/// every chapter:
///   - color = which named validator a vertex belongs to
///   - vertical stripe = round
///   - border thickness/halo = vertex state
///   - edge style = parent link kind
struct LegendSidebar: View {
    static let width: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LEGEND")
                .scaledFont(size: 11, weight: .heavy, design: .monospaced)
                .foregroundStyle(.white.opacity(0.45))
                .tracking(2)

            Group {
                section(title: "color = validator") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Cast.leads, id: \.id) { role in
                            HStack(spacing: 6) {
                                Circle().fill(role.color)
                                    .frame(width: 8, height: 8)
                                Text(role.displayName)
                                    .scaledFont(size: 10, weight: .medium, design: .monospaced)
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                        }
                    }
                }

                section(title: "stripe = round") {
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { i in
                            Rectangle()
                                .fill(Color.white.opacity(i.isMultiple(of: 2) ? 0.06 : 0.02))
                                .frame(width: 16, height: 18)
                                .overlay(
                                    Text("R\(i)")
                                        .scaledFont(size: 7, weight: .heavy, design: .monospaced)
                                        .foregroundStyle(.white.opacity(0.55))
                                )
                        }
                    }
                    .background(Color.black.opacity(0.4))
                }

                section(title: "border = state") {
                    VStack(alignment: .leading, spacing: 6) {
                        legendDot(border: 0.6, halo: false, label: "unconfirmed")
                        legendDot(border: 1.6, halo: false, label: "round-marked")
                        legendDot(border: 1.6, halo: true,  label: "leader")
                        legendXMark(label: "banned (Byz)")
                    }
                }

                section(title: "edge = parent link") {
                    VStack(alignment: .leading, spacing: 4) {
                        edgeSample(dashed: false, label: "self-parent")
                        edgeSample(dashed: true,  label: "cross-parent")
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 24)
        .frame(width: Self.width, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.20),
                    Color.black.opacity(0.55),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .scaledFont(size: 9, weight: .heavy, design: .monospaced)
                .foregroundStyle(.white.opacity(0.50))
                .tracking(1)
            content()
        }
    }

    private func legendDot(border: CGFloat, halo: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                if halo {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 4)
                        .frame(width: 18, height: 18)
                }
                Circle()
                    .fill(Cast.coral.opacity(0.85))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.85), lineWidth: border)
                    )
            }
            .frame(width: 22, height: 22)
            Text(label)
                .scaledFont(size: 9, weight: .medium, design: .monospaced)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func legendXMark(label: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Cast.violet.opacity(0.85))
                    .frame(width: 10, height: 10)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.red)
            }
            .frame(width: 22, height: 22)
            Text(label)
                .scaledFont(size: 9, weight: .medium, design: .monospaced)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func edgeSample(dashed: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            Canvas { ctx, size in
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height / 2))
                p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                let style = StrokeStyle(
                    lineWidth: 1.2,
                    dash: dashed ? [3, 3] : []
                )
                ctx.stroke(p, with: .color(.white.opacity(0.65)), style: style)
            }
            .frame(width: 26, height: 10)
            Text(label)
                .scaledFont(size: 9, weight: .medium, design: .monospaced)
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}
