import SwiftUI

/// Ch00 (chapter index 0): "Four friends. One ledger. No boss."
///
/// Renders from `Ch00Timeline` — same architectural pattern as Ch01:
/// a strictly serial sequence of micro-beats, each with its own
/// narration, drawn as a pure function of timeline position. No hard
/// cuts; cast members appear on lanes one at a time; the screen stays
/// uncluttered.
struct Ch01_Problem: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch00Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    // MARK: - Top-level

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch00Timeline.state(at: t)

        drawIntroducedLanes(in: &context, size: size, world: world)
        drawCastFigures(in: &context, size: size, world: world, t: t)

        if world.divergeProgress > 0 {
            drawDivergingLogs(in: &context, size: size,
                              progress: world.divergeProgress)
        }
        if world.convergeProgress > 0 {
            drawConvergenceArrows(in: &context, size: size,
                                   progress: world.convergeProgress)
        }
        if world.daveOminous > 0 {
            drawDaveOminous(in: &context, size: size,
                             progress: world.daveOminous, t: t)
        }
        if let title = world.titleText {
            drawTitle(in: &context, size: size,
                      text: title, alpha: world.titleAlpha)
        }
        drawPerceptionTowers(in: &context, size: size, world: world)
        drawBeatTag(in: &context, size: size, world: world)
    }

    // MARK: - Perception towers (Ch00 abstract preview)

    /// Bottom-of-canvas towers, one per introduced cast. They fill with
    /// abstract `tx-N` blocks during the `logsDiverge` beat, in a
    /// DIFFERENT order per cast — a preview of the same structure that
    /// Ch01 fills with real α/β/γ messages.
    private func drawPerceptionTowers(
        in context: inout GraphicsContext, size: CGSize,
        world: Ch00WorldState
    ) {
        let casts: [Ch01Cast] = [.aaron, .ben, .carl, .dave]
        let visibleCasts = casts.filter { world.introduced.contains($0) }
        guard !visibleCasts.isEmpty else { return }

        let blockH: CGFloat = 26
        let blockGap: CGFloat = 4
        let towerH: CGFloat = 4 * (blockH + blockGap) + 28
        let baseY: CGFloat = size.height - 110
        let towerW: CGFloat = 110
        let totalW = CGFloat(visibleCasts.count) * towerW
                    + CGFloat(visibleCasts.count - 1) * 24
        let startX = (size.width - totalW) / 2

        for (i, cast) in visibleCasts.enumerated() {
            let towerX = startX + CGFloat(i) * (towerW + 24)
            let towerCenter = towerX + towerW / 2
            let color = castColor(cast)

            // Header
            context.draw(
                Text(cast.role.displayName.uppercased())
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(color.opacity(0.85)),
                at: CGPoint(x: towerCenter, y: baseY - towerH + 4)
            )
            context.draw(
                Text("VIEW")
                    .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35)),
                at: CGPoint(x: towerCenter, y: baseY - towerH + 18)
            )
            // Baseline + rails
            var baseline = Path()
            baseline.move(to: CGPoint(x: towerX, y: baseY))
            baseline.addLine(to: CGPoint(x: towerX + towerW, y: baseY))
            context.stroke(baseline, with: .color(color.opacity(0.45)),
                          lineWidth: 1.2)
            for railX in [towerX, towerX + towerW] {
                var rail = Path()
                rail.move(to: CGPoint(x: railX, y: baseY))
                rail.addLine(to: CGPoint(x: railX, y: baseY - towerH + 26))
                context.stroke(rail, with: .color(color.opacity(0.18)),
                              style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
            }

            // Blocks
            let blocks = world.towerBlocks[cast] ?? []
            for (j, block) in blocks.enumerated() {
                let blockY = baseY - CGFloat(j + 1) * (blockH + blockGap)
                let rect = CGRect(x: towerX + 6, y: blockY,
                                  width: towerW - 12, height: blockH)
                let blockColor = castColor(block.authorCast)
                context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                            with: .color(blockColor.opacity(0.88)))
                context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                              with: .color(.white.opacity(0.45)), lineWidth: 1.0)
                context.draw(
                    Text(block.label)
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
        }
    }

    // MARK: - Lane geometry (mirrors Ch01's; will extract to a shared
    //                       LaneRenderKit once a third chapter adopts)

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
        return CGPoint(x: size.width * 0.30, y: castLaneY(laneIdx, size: size))
    }

    private func castColor(_ cast: Ch01Cast) -> Color {
        switch cast {
        case .aaron: return Cast.coral
        case .ben:   return Cast.teal
        case .carl:  return Cast.amber
        case .dave:  return Cast.violet
        }
    }

    // MARK: - Lanes

    private func drawIntroducedLanes(
        in context: inout GraphicsContext, size: CGSize, world: Ch00WorldState
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        for (cast, idx) in casts where world.introduced.contains(cast) {
            let y = castLaneY(idx, size: size)
            var path = Path()
            path.move(to: CGPoint(x: 36, y: y))
            path.addLine(to: CGPoint(x: size.width - 24, y: y))
            context.stroke(path,
                          with: .color(castColor(cast).opacity(0.18)),
                          style: StrokeStyle(lineWidth: 0.8, dash: [4, 6]))
            context.draw(
                Text(cast.role.displayName.capitalized)
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(castColor(cast).opacity(0.75)),
                at: CGPoint(x: 24, y: y),
                anchor: .leading
            )
        }
    }

    // MARK: - Cast figures

    private func drawCastFigures(
        in context: inout GraphicsContext, size: CGSize,
        world: Ch00WorldState, t: Double
    ) {
        for cast in Ch01Cast.allCases where world.introduced.contains(cast) {
            let pos = castPosition(cast: cast, size: size)
            let r: CGFloat = 30
            let color = castColor(cast)

            // Halo
            let haloR = r * 1.6
            context.fill(
                Circle().path(in: CGRect(x: pos.x - haloR, y: pos.y - haloR,
                                          width: haloR * 2, height: haloR * 2)),
                with: .color(color.opacity(0.15))
            )
            context.fill(
                Circle().path(in: CGRect(x: pos.x - r, y: pos.y - r,
                                          width: r * 2, height: r * 2)),
                with: .color(color.opacity(0.95))
            )
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - r, y: pos.y - r,
                                          width: r * 2, height: r * 2)),
                with: .color(.white.opacity(0.5)), lineWidth: 1.5
            )
            context.draw(
                Text(String(cast.role.displayName.prefix(1)))
                    .font(.system(size: settings.scaled(22), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white),
                at: pos
            )
            context.draw(
                Text(cast.role.displayName.uppercased())
                    .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                    .foregroundColor(color.opacity(0.95)),
                at: CGPoint(x: pos.x, y: pos.y + r + 14)
            )
        }
    }

    // MARK: - "Logs diverge" — each lane gets its own scribble of vertices

    private func drawDivergingLogs(
        in context: inout GraphicsContext, size: CGSize, progress: Double
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        // Per-lane staggered vertex pattern. Each lane gets a small
        // sequence of dots to suggest "this is what THIS player has
        // recorded so far." Patterns are intentionally different so the
        // viewer reads them as distinct local logs.
        let patterns: [Ch01Cast: [Double]] = [
            .aaron: [0.45, 0.55, 0.62, 0.70, 0.80],
            .ben:   [0.50, 0.58, 0.66, 0.78],
            .carl:  [0.48, 0.60, 0.72, 0.82, 0.92],
            .dave:  [0.52, 0.64, 0.74, 0.84],
        ]
        for (cast, idx) in casts {
            guard let pattern = patterns[cast] else { continue }
            let y = castLaneY(idx, size: size)
            let laneStart: CGFloat = size.width * 0.42
            let laneEnd: CGFloat = size.width - 60
            let span = laneEnd - laneStart
            let revealed = Int(Double(pattern.count) * progress)
            for i in 0..<revealed {
                let x = laneStart + span * CGFloat(pattern[i])
                let r: CGFloat = 8
                context.fill(
                    Circle().path(in: CGRect(x: x - r, y: y - r,
                                              width: r * 2, height: r * 2)),
                    with: .color(castColor(cast).opacity(0.85))
                )
            }
        }
    }

    // MARK: - "Need to agree" — arrows from each lane converging

    private func drawConvergenceArrows(
        in context: inout GraphicsContext, size: CGSize, progress: Double
    ) {
        let target = CGPoint(
            x: size.width * 0.85,
            y: (castLaneY(1, size: size) + castLaneY(2, size: size)) / 2
        )
        let haloR: CGFloat = 28 * CGFloat(0.6 + 0.4 * progress)
        context.fill(
            Circle().path(in: CGRect(x: target.x - haloR, y: target.y - haloR,
                                      width: haloR * 2, height: haloR * 2)),
            with: .color(.green.opacity(0.18 * progress))
        )
        context.draw(
            Text("ONE HISTORY")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.92 * progress)),
            at: CGPoint(x: target.x, y: target.y)
        )

        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        for (cast, idx) in casts {
            let from = CGPoint(x: size.width * 0.42, y: castLaneY(idx, size: size))
            let p = CGFloat(progress)
            let endX = from.x + (target.x - from.x) * p
            let endY = from.y + (target.y - from.y) * p
            var path = Path()
            path.move(to: from)
            path.addLine(to: CGPoint(x: endX, y: endY))
            context.stroke(path,
                          with: .color(castColor(cast).opacity(0.65)),
                          style: StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
        }
    }

    // MARK: - Dave foreshadow

    private func drawDaveOminous(
        in context: inout GraphicsContext, size: CGSize,
        progress: Double, t: Double
    ) {
        let pos = castPosition(cast: .dave, size: size)
        let pulse: CGFloat = 1.0 + 0.10 * CGFloat(sin(t * 3))
        let outerR: CGFloat = 50 * pulse
        context.stroke(
            Circle().path(in: CGRect(x: pos.x - outerR, y: pos.y - outerR,
                                      width: outerR * 2, height: outerR * 2)),
            with: .color(.red.opacity(0.55 * progress)), lineWidth: 2.5
        )
        context.draw(
            Text("⚠ ONE OF THESE WILL LIE")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.85 * progress)),
            at: CGPoint(x: pos.x + 110, y: pos.y - 50)
        )
    }

    // MARK: - Title

    private func drawTitle(
        in context: inout GraphicsContext, size: CGSize,
        text: String, alpha: Double
    ) {
        context.draw(
            Text(text)
                .font(.system(size: settings.scaled(28), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.95 * alpha)),
            at: CGPoint(x: size.width / 2, y: size.height / 2)
        )
    }

    // MARK: - Beat tag (dev/testbed only)

    private func drawBeatTag(
        in context: inout GraphicsContext, size: CGSize, world: Ch00WorldState
    ) {
        guard let beatId = world.activeBeat?.id else { return }
        context.draw(
            Text(beatId)
                .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.20)),
            at: CGPoint(x: size.width - 14, y: 10),
            anchor: .trailing
        )
    }
}
