import SwiftUI

/// Ch09 (chapter index 9, file Ch10_Byzantine.swift): "Dave lies. Crisis catches him."
///
/// Renders from `Ch09Timeline`. Dave creates two conflicting messages
/// under the same identity (ζ_a, ζ_b), sends one to Aaron and the
/// other to Ben, and tries to make them disagree. Aaron and Ben
/// gossip; the fork is detected; Dave's vertices are banned; the
/// honest 3 converge anyway.
struct Ch10_Byzantine: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch09Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch09Timeline.state(at: t)

        drawLanes(in: &context, size: size)
        drawCastFigures(in: &context, size: size, t: t)
        drawAcceptedVertices(in: &context, size: size, world: world)
        drawDaveForks(in: &context, size: size, world: world, t: t)

        if let thought = world.thought {
            drawThoughtBubble(in: &context, size: size, thought: thought)
        }
        if let composing = world.composing {
            drawComposingSlot(in: &context, size: size, composing: composing)
        }
        if let flight = world.inFlight {
            drawForkFlight(in: &context, size: size, flight: flight)
        }
        if world.forkDetectedAlpha > 0 {
            drawForkDetected(in: &context, size: size,
                              alpha: world.forkDetectedAlpha)
        }
        if world.thresholdBarAlpha > 0 {
            drawThresholdBar(in: &context, size: size,
                              alpha: world.thresholdBarAlpha)
        }
        if world.convergedAlpha > 0 {
            drawConvergedBadge(in: &context, size: size,
                                alpha: world.convergedAlpha)
        }

        drawPerceptionTowers(in: &context, size: size, world: world)
        drawBeatTag(in: &context, size: size, world: world)
    }

    // MARK: - Geometry / lookups

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
        if mid.hasPrefix("ζ") { return .dave }
        if let m = Ch01Timeline.messages[mid] { return m.author }
        if let m = Ch02Timeline.messages[mid] { return m.author }
        return .aaron
    }

    private func hashOf(_ mid: String) -> String {
        if let info = Ch09Timeline.forkVersions[mid] { return info.hashShort }
        if let m = Ch01Timeline.messages[mid] { return m.hashShort }
        if let m = Ch02Timeline.messages[mid] { return m.hashShort }
        return "????"
    }

    private static let initialMessages: [String] = ["α", "β", "γ", "δ", "ε"]

    // MARK: - Lanes

    private func drawLanes(in context: inout GraphicsContext, size: CGSize) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        for (cast, idx) in casts {
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
                at: CGPoint(x: 24, y: y),
                anchor: .leading
            )
        }
    }

    // MARK: - Cast figures

    private func drawCastFigures(
        in context: inout GraphicsContext, size: CGSize, t: Double
    ) {
        for cast in Ch01Cast.allCases {
            let pos = castPosition(cast: cast, size: size)
            let r: CGFloat = 26
            let color = castColor(cast)
            let haloR = r * 1.5
            context.fill(
                Circle().path(in: CGRect(x: pos.x - haloR, y: pos.y - haloR,
                                          width: haloR * 2, height: haloR * 2)),
                with: .color(color.opacity(0.10))
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
                    .font(.system(size: settings.scaled(18), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white),
                at: pos
            )
            context.draw(
                Text(cast.role.displayName.uppercased())
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(color.opacity(0.95)),
                at: CGPoint(x: pos.x, y: pos.y + r + 12)
            )
        }
    }

    // MARK: - Accepted (carry-forward) vertices on each lane

    private func drawAcceptedVertices(
        in context: inout GraphicsContext, size: CGSize, world: Ch09WorldState
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        for (cast, laneIdx) in casts {
            let lane = castLaneY(laneIdx, size: size)
            let castX = castPosition(cast: cast, size: size).x
            let firstX = castX + 70
            let gap: CGFloat = 56
            for (i, mid) in Self.initialMessages.enumerated() {
                let x = firstX + CGFloat(i) * gap
                if x > size.width - 60 { break }
                drawAcceptedVertex(in: &context,
                                    at: CGPoint(x: x, y: lane),
                                    messageId: mid)
            }
        }
    }

    private func drawAcceptedVertex(
        in context: inout GraphicsContext, at pos: CGPoint,
        messageId: String
    ) {
        let r: CGFloat = 13
        let color = castColor(authorOf(messageId))
        let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        context.fill(Circle().path(in: rect),
                    with: .color(color.opacity(0.85)))
        context.stroke(Circle().path(in: rect),
                      with: .color(.white.opacity(0.55)), lineWidth: 1.0)
        context.draw(
            Text(messageId)
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
    }

    // MARK: - Dave's forks

    private func drawDaveForks(
        in context: inout GraphicsContext, size: CGSize,
        world: Ch09WorldState, t: Double
    ) {
        let lane = castLaneY(3, size: size)
        let castX = castPosition(cast: .dave, size: size).x
        // Forks sit at the right end of Dave's accepted-vertex row,
        // visually past ε.
        let baseX = castX + 70 + CGFloat(Self.initialMessages.count) * 56
        let forkGap: CGFloat = 56

        for (i, vid) in world.forksOnDaveLane.enumerated() {
            let pos = CGPoint(x: baseX + CGFloat(i) * forkGap, y: lane)
            let r: CGFloat = 16
            let pulse: CGFloat = world.daveBanned ? 1.0 : 1.0 + 0.05 * CGFloat(sin(t * 4))
            let rr = r * pulse

            // Outer red fork ring
            let ringR: CGFloat = rr + 4
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - ringR, y: pos.y - ringR,
                                          width: ringR * 2, height: ringR * 2)),
                with: .color(.red.opacity(0.85)), lineWidth: 2.4
            )
            // Inner Dave-violet fill
            context.fill(
                Circle().path(in: CGRect(x: pos.x - rr, y: pos.y - rr,
                                          width: rr * 2, height: rr * 2)),
                with: .color(Cast.violet.opacity(world.daveBanned ? 0.45 : 0.95))
            )
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - rr, y: pos.y - rr,
                                          width: rr * 2, height: rr * 2)),
                with: .color(.white.opacity(0.55)), lineWidth: 1.2
            )
            context.draw(
                Text(vid)
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(world.daveBanned ? 0.6 : 1.0)),
                at: pos
            )
            context.draw(
                Text(hashOf(vid))
                    .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5)),
                at: CGPoint(x: pos.x, y: pos.y + rr + 8)
            )
            // Big red X if Dave is banned
            if world.daveBanned {
                let xr: CGFloat = ringR + 2
                var xPath = Path()
                xPath.move(to: CGPoint(x: pos.x - xr, y: pos.y - xr))
                xPath.addLine(to: CGPoint(x: pos.x + xr, y: pos.y + xr))
                xPath.move(to: CGPoint(x: pos.x - xr, y: pos.y + xr))
                xPath.addLine(to: CGPoint(x: pos.x + xr, y: pos.y - xr))
                context.stroke(xPath,
                              with: .color(.red.opacity(0.95)), lineWidth: 3.0)
            }
        }
    }

    // MARK: - Thought / composing / flight

    private func drawThoughtBubble(
        in context: inout GraphicsContext, size: CGSize,
        thought: Ch09WorldState.Ch09Thought
    ) {
        let pos = castPosition(cast: thought.cast, size: size)
        let bubbleW: CGFloat = max(140, CGFloat(thought.label.count) * 7 + 24)
        let bubbleH: CGFloat = 36
        let bubbleRect = CGRect(
            x: pos.x - bubbleW / 2,
            y: pos.y - 80 - bubbleH,
            width: bubbleW, height: bubbleH
        )
        let color = castColor(thought.cast)
        context.fill(RoundedRectangle(cornerRadius: 18).path(in: bubbleRect),
                    with: .color(.black.opacity(0.78)))
        context.stroke(RoundedRectangle(cornerRadius: 18).path(in: bubbleRect),
                      with: .color(color.opacity(0.85)), lineWidth: 1.4)
        context.draw(
            Text(thought.label)
                .font(.system(size: settings.scaled(11), weight: .medium, design: .default))
                .foregroundColor(.white.opacity(0.92))
                .italic(),
            at: CGPoint(x: bubbleRect.midX, y: bubbleRect.midY)
        )
    }

    private func drawComposingSlot(
        in context: inout GraphicsContext, size: CGSize,
        composing: Ch09WorldState.Ch09Composing
    ) {
        guard let info = Ch09Timeline.forkVersions[composing.versionId] else { return }
        let authorPos = castPosition(cast: .dave, size: size)
        let boxW: CGFloat = min(540, size.width - 80)
        let boxRect = CGRect(x: size.width / 2 - boxW / 2, y: 16,
                             width: boxW, height: 110)
        var connector = Path()
        connector.move(to: CGPoint(x: boxRect.midX, y: boxRect.maxY))
        connector.addLine(to: CGPoint(x: authorPos.x, y: authorPos.y - 36))
        context.stroke(connector,
                      with: .color(Cast.violet.opacity(0.45)),
                      style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
        context.fill(RoundedRectangle(cornerRadius: 10).path(in: boxRect),
                    with: .color(.black.opacity(0.88)))
        // Red ring on the box to flag this is a fork
        context.stroke(RoundedRectangle(cornerRadius: 10).path(in: boxRect),
                      with: .color(.red.opacity(0.95)), lineWidth: 1.8)
        context.draw(
            Text("✎ DAVE WRITING \(info.label)  (FORK)")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.95)),
            at: CGPoint(x: boxRect.minX + 14, y: boxRect.minY + 14),
            anchor: .leading
        )
        context.draw(
            Text(info.claim)
                .font(.system(size: settings.scaled(11), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.88)),
            at: CGPoint(x: boxRect.minX + 14, y: boxRect.minY + 36),
            anchor: .leading
        )
        context.draw(
            Text("parents: ε")
                .font(.system(size: settings.scaled(11), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.88)),
            at: CGPoint(x: boxRect.minX + 14, y: boxRect.minY + 54),
            anchor: .leading
        )
        if composing.sealed {
            context.draw(
                Text("hash:    \(info.hashShort)…  ✓")
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(Cast.violet.opacity(0.95)),
                at: CGPoint(x: boxRect.minX + 14, y: boxRect.minY + 72),
                anchor: .leading
            )
        }
    }

    private func drawForkFlight(
        in context: inout GraphicsContext, size: CGSize,
        flight: Ch09WorldState.Ch09Flight
    ) {
        let lift: CGFloat = 36
        let from = castPosition(cast: flight.from, size: size)
        let to = castPosition(cast: flight.to, size: size)
        let fromTrack = CGPoint(x: from.x, y: from.y - lift)
        let toTrack = CGPoint(x: to.x, y: to.y - lift)
        var path = Path()
        path.move(to: fromTrack)
        path.addLine(to: toTrack)
        context.stroke(path,
                      with: .color(.red.opacity(0.25)),
                      style: StrokeStyle(lineWidth: 1.0, dash: [3, 5]))
        let p = CGFloat(flight.progress)
        let pos = CGPoint(x: fromTrack.x + (toTrack.x - fromTrack.x) * p,
                          y: fromTrack.y + (toTrack.y - fromTrack.y) * p)
        let envW: CGFloat = 80
        let envH: CGFloat = 30
        let rect = CGRect(x: pos.x - envW / 2, y: pos.y - envH / 2,
                          width: envW, height: envH)
        context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                    with: .color(Cast.violet.opacity(0.95)))
        context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                      with: .color(.red.opacity(0.85)), lineWidth: 1.4)
        context.draw(
            Text("\(flight.versionId) · \(hashOf(flight.versionId))")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
    }

    // MARK: - Fork detected / threshold / converged

    private func drawForkDetected(
        in context: inout GraphicsContext, size: CGSize, alpha: Double
    ) {
        let cy: CGFloat = 60
        let label = "⚠ FORK DETECTED — same Dave identity, two different bodies"
        context.draw(
            Text(label)
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.95 * alpha)),
            at: CGPoint(x: size.width / 2, y: cy)
        )
    }

    private func drawThresholdBar(
        in context: inout GraphicsContext, size: CGSize, alpha: Double
    ) {
        // f<n/3 visual: a small bar showing 1 byzantine / 4 total.
        let cy: CGFloat = 92
        let barW: CGFloat = 280
        let barH: CGFloat = 18
        let barX = size.width / 2 - barW / 2
        let rect = CGRect(x: barX, y: cy - barH / 2, width: barW, height: barH)
        context.stroke(RoundedRectangle(cornerRadius: 4).path(in: rect),
                      with: .color(.white.opacity(0.45 * alpha)), lineWidth: 1.0)
        // Threshold: 1/3 of bar marked at 33% line
        let threshFrac = CGFloat(1.0 / 3.0)
        let threshX = barX + threshFrac * barW
        var threshLine = Path()
        threshLine.move(to: CGPoint(x: threshX, y: rect.minY - 4))
        threshLine.addLine(to: CGPoint(x: threshX, y: rect.maxY + 4))
        context.stroke(threshLine,
                      with: .color(.yellow.opacity(0.85 * alpha)),
                      style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
        // Filled portion: 1/4 = 25% (one byzantine of four)
        let fillFrac = CGFloat(1.0 / 4.0)
        let fillRect = CGRect(x: barX, y: rect.minY,
                              width: fillFrac * barW, height: barH)
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: fillRect),
                    with: .color(.green.opacity(0.7 * alpha)))
        context.draw(
            Text("f = 1, n = 4   ·   3f = 3 < n = 4   ·   safety holds")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.9 * alpha)),
            at: CGPoint(x: rect.midX, y: rect.maxY + 14)
        )
    }

    private func drawConvergedBadge(
        in context: inout GraphicsContext, size: CGSize, alpha: Double
    ) {
        context.draw(
            Text("✓ AARON · BEN · CARL CONVERGE — Dave's weight wasted")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.95 * alpha)),
            at: CGPoint(x: size.width / 2, y: size.height - 50)
        )
    }

    // MARK: - Perception towers

    private func drawPerceptionTowers(
        in context: inout GraphicsContext, size: CGSize, world: Ch09WorldState
    ) {
        let casts: [Ch01Cast] = [.aaron, .ben, .carl, .dave]
        let blockH: CGFloat = 18
        let blockGap: CGFloat = 3
        let maxBlocks = 7   // up to 5 honest + 2 fork versions
        let towerH: CGFloat = CGFloat(maxBlocks) * (blockH + blockGap) + 28
        let baseY: CGFloat = size.height - 70
        let towerW: CGFloat = 110
        let totalW = CGFloat(casts.count) * towerW + CGFloat(casts.count - 1) * 24
        let startX = (size.width - totalW) / 2

        for (i, cast) in casts.enumerated() {
            let towerX = startX + CGFloat(i) * (towerW + 24)
            let towerCenter = towerX + towerW / 2
            let color = castColor(cast)

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
            let order = world.views[cast] ?? []
            for (j, mid) in order.enumerated() {
                let blockY = baseY - CGFloat(j + 1) * (blockH + blockGap)
                let rect = CGRect(x: towerX + 6, y: blockY,
                                  width: towerW - 12, height: blockH)
                let isFork = mid.hasPrefix("ζ")
                let blockColor = castColor(authorOf(mid))
                context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                            with: .color(blockColor.opacity(world.daveBanned && isFork ? 0.30 : 0.88)))
                context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                              with: .color(isFork ? .red.opacity(0.85) : .white.opacity(0.45)),
                              lineWidth: isFork ? 1.6 : 1.0)
                context.draw(
                    Text(mid)
                        .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(world.daveBanned && isFork ? 0.55 : 1.0)),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
                if world.daveBanned && isFork {
                    var x = Path()
                    x.move(to: CGPoint(x: rect.minX + 4, y: rect.minY + 4))
                    x.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 4))
                    x.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 4))
                    x.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 4))
                    context.stroke(x, with: .color(.red.opacity(0.9)),
                                  lineWidth: 1.5)
                }
            }
        }
    }

    // MARK: - Beat tag

    private func drawBeatTag(
        in context: inout GraphicsContext, size: CGSize, world: Ch09WorldState
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
