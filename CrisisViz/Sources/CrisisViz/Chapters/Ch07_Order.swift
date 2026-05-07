import SwiftUI

/// Ch06 (chapter index 6, file Ch07_Order.swift):
/// "Spokespersons line up. Everyone else falls in behind." — total order.
struct Ch07_Order: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch06Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch06Timeline.state(at: t)
        drawLanes(in: &context, size: size)
        drawCastFigures(in: &context, size: size)
        drawAcceptedVertices(in: &context, size: size, world: world)
        drawOrderingSnake(in: &context, size: size, world: world, t: t)
        drawRoundOrderedBadges(in: &context, size: size, world: world)
        if world.finalConvergenceAlpha > 0 {
            drawFinalConvergence(in: &context, size: size,
                                  alpha: world.finalConvergenceAlpha)
        }
        drawBeatTag(in: &context, size: size, world: world)
    }

    private func castLaneY(_ laneIdx: Int, size: CGSize) -> CGFloat {
        let margin: CGFloat = 60
        let nodeCount: CGFloat = 7
        let laneHeight = (size.height - 2 * margin) / nodeCount
        return margin + (CGFloat(laneIdx) + 0.5) * laneHeight
    }

    private func castPosition(cast: Ch01Cast, size: CGSize) -> CGPoint {
        let laneIdx: Int
        switch cast {
        case .aaron: laneIdx = 0
        case .ben:   laneIdx = 1
        case .carl:  laneIdx = 2
        case .dave:  laneIdx = 3
        }
        return CGPoint(x: size.width * 0.20, y: castLaneY(laneIdx, size: size))
    }

    private func castColor(_ cast: Ch01Cast) -> Color {
        switch cast {
        case .aaron: return Cast.coral
        case .ben:   return Cast.teal
        case .carl:  return Cast.amber
        case .dave:  return Cast.violet
        }
    }

    private func authorOf(_ mid: String) -> Ch01Cast {
        if let m = Ch01Timeline.messages[mid] { return m.author }
        if let m = Ch02Timeline.messages[mid] { return m.author }
        return .aaron
    }

    private static let allMessages: [String] = ["α", "β", "γ", "δ", "ε"]
    private static let castLanes: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]

    private func vertexPosition(cast: Ch01Cast, mid: String, size: CGSize) -> CGPoint? {
        guard let i = Self.allMessages.firstIndex(of: mid) else { return nil }
        let laneIdx: Int
        switch cast {
        case .aaron: laneIdx = 0
        case .ben:   laneIdx = 1
        case .carl:  laneIdx = 2
        case .dave:  laneIdx = 3
        }
        let lane = castLaneY(laneIdx, size: size)
        let castX = castPosition(cast: cast, size: size).x
        return CGPoint(x: castX + 70 + CGFloat(i) * 56, y: lane)
    }

    private func drawLanes(in context: inout GraphicsContext, size: CGSize) {
        for (cast, idx) in Self.castLanes {
            let y = castLaneY(idx, size: size)
            var path = Path()
            path.move(to: CGPoint(x: 36, y: y))
            path.addLine(to: CGPoint(x: size.width - 24, y: y))
            context.stroke(path, with: .color(castColor(cast).opacity(0.18)),
                          style: StrokeStyle(lineWidth: 0.8, dash: [4, 6]))
            context.draw(
                Text(cast.role.displayName.capitalized)
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(castColor(cast).opacity(0.75)),
                at: CGPoint(x: 24, y: y), anchor: .leading
            )
        }
    }

    private func drawCastFigures(in context: inout GraphicsContext, size: CGSize) {
        for cast in Ch01Cast.allCases {
            let pos = castPosition(cast: cast, size: size)
            let r: CGFloat = 24
            let color = castColor(cast)
            context.fill(
                Circle().path(in: CGRect(x: pos.x - r * 1.5, y: pos.y - r * 1.5,
                                          width: r * 3, height: r * 3)),
                with: .color(color.opacity(0.10))
            )
            context.fill(
                Circle().path(in: CGRect(x: pos.x - r, y: pos.y - r,
                                          width: r * 2, height: r * 2)),
                with: .color(color.opacity(0.95))
            )
            context.draw(
                Text(String(cast.role.displayName.prefix(1)))
                    .font(.system(size: settings.scaled(16), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white),
                at: pos
            )
        }
    }

    private func drawAcceptedVertices(
        in context: inout GraphicsContext, size: CGSize, world: Ch06WorldState
    ) {
        for (cast, _) in Self.castLanes {
            for mid in Self.allMessages {
                guard let pos = vertexPosition(cast: cast, mid: mid, size: size) else { continue }
                let r: CGFloat = 11
                let color = castColor(authorOf(mid))
                let inOrder = world.order.contains(mid)
                let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                context.fill(Circle().path(in: rect),
                            with: .color(color.opacity(inOrder ? 0.6 : 0.85)))
                context.stroke(Circle().path(in: rect),
                              with: .color(.white.opacity(0.45)), lineWidth: 0.8)
                context.draw(
                    Text(mid)
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(inOrder ? 0.7 : 1.0)),
                    at: pos
                )
            }
        }
    }

    private func drawOrderingSnake(
        in context: inout GraphicsContext, size: CGSize,
        world: Ch06WorldState, t: Double
    ) {
        let trackY: CGFloat = size.height - 100
        let blockW: CGFloat = 76
        let blockH: CGFloat = 38
        let blockGap: CGFloat = 16
        let totalW = CGFloat(Self.allMessages.count) * blockW
                    + CGFloat(Self.allMessages.count - 1) * blockGap
        let startX = (size.width - totalW) / 2

        context.draw(
            Text("TOTAL ORDER")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.65)),
            at: CGPoint(x: size.width / 2, y: trackY - 32)
        )

        for i in 0..<Self.allMessages.count {
            let x = startX + CGFloat(i) * (blockW + blockGap)
            let rect = CGRect(x: x, y: trackY - blockH / 2,
                              width: blockW, height: blockH)
            if i >= world.order.count {
                context.stroke(RoundedRectangle(cornerRadius: 6).path(in: rect),
                              with: .color(.white.opacity(0.18)),
                              style: StrokeStyle(lineWidth: 1.0, dash: [3, 4]))
                context.draw(
                    Text("#\(i + 1)")
                        .font(.system(size: settings.scaled(9), weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.30)),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
        }

        var activeSlideIndex = -1
        if case .appendToOrder = world.activeBeat?.kind {
            activeSlideIndex = world.order.count - 1
        }

        for (i, mid) in world.order.enumerated() {
            let x = startX + CGFloat(i) * (blockW + blockGap)
            let restY = trackY
            let dropFrom = trackY + 60
            let isSliding = (i == activeSlideIndex)
            let p = isSliding ? max(0, min(1, world.activeProgress)) : 1.0
            let eased = 1 - pow(1 - p, 3)
            let y = restY * eased + dropFrom * (1 - eased)
            let rect = CGRect(x: x, y: y - blockH / 2,
                              width: blockW, height: blockH)
            let color = castColor(authorOf(mid))
            context.fill(RoundedRectangle(cornerRadius: 6).path(in: rect),
                        with: .color(color.opacity(0.92 * eased)))
            context.stroke(RoundedRectangle(cornerRadius: 6).path(in: rect),
                          with: .color(.white.opacity(0.55 * eased)), lineWidth: 1.2)
            context.draw(
                Text("\(i + 1)")
                    .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55 * eased)),
                at: CGPoint(x: rect.midX, y: rect.minY + 8)
            )
            context.draw(
                Text(mid)
                    .font(.system(size: settings.scaled(16), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(eased)),
                at: CGPoint(x: rect.midX, y: rect.midY + 4)
            )
        }

        // Snake spine arrows between filled slots
        for i in 0..<max(0, world.order.count - 1) {
            let x1 = startX + CGFloat(i) * (blockW + blockGap) + blockW
            let x2 = startX + CGFloat(i + 1) * (blockW + blockGap)
            var path = Path()
            path.move(to: CGPoint(x: x1, y: trackY))
            path.addLine(to: CGPoint(x: x2, y: trackY))
            context.stroke(path, with: .color(.white.opacity(0.35)),
                          lineWidth: 1.2)
            var head = Path()
            head.move(to: CGPoint(x: x2, y: trackY))
            head.addLine(to: CGPoint(x: x2 - 5, y: trackY - 3))
            head.move(to: CGPoint(x: x2, y: trackY))
            head.addLine(to: CGPoint(x: x2 - 5, y: trackY + 3))
            context.stroke(head, with: .color(.white.opacity(0.35)),
                          lineWidth: 1.2)
        }
    }

    private func drawRoundOrderedBadges(
        in context: inout GraphicsContext, size: CGSize, world: Ch06WorldState
    ) {
        for (round, alpha) in world.roundOrderedAlpha where alpha > 0 {
            let label = "✓ ROUND \(round) ORDERED"
            context.draw(
                Text(label)
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(.green.opacity(0.95 * alpha)),
                at: CGPoint(x: size.width / 2,
                             y: size.height - 50 - CGFloat(round) * 18)
            )
        }
    }

    private func drawFinalConvergence(
        in context: inout GraphicsContext, size: CGSize, alpha: Double
    ) {
        context.draw(
            Text("✓ ALL VALIDATORS COMPUTE THE SAME TOTAL ORDER  —  CONVERGENCE")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.95 * alpha)),
            at: CGPoint(x: size.width / 2, y: 40)
        )
    }

    private func drawBeatTag(
        in context: inout GraphicsContext, size: CGSize, world: Ch06WorldState
    ) {
        guard let beatId = world.activeBeat?.id else { return }
        context.draw(
            Text(beatId)
                .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.20)),
            at: CGPoint(x: size.width - 14, y: 10), anchor: .trailing
        )
    }
}
