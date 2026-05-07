import SwiftUI

/// Ch02 (chapter index 2): "Dave can't hear Aaron. The graph splits."
///
/// Renders from `Ch02Timeline`. Picks up Ch01's final state (all four
/// hold {α, β, γ}), then dramatizes the partition: Dave's link breaks,
/// Aaron writes δ that reaches the honest 3 but not Dave, Dave writes
/// ε that gets stuck on his side, the partition heals, and the
/// missing messages flood through. Perception towers at the bottom
/// make the divergence + reunion visible at a glance.
struct Ch03_Partition: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch02Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch02Timeline.state(at: t)

        drawLanes(in: &context, size: size)
        drawCastFigures(in: &context, size: size, world: world, t: t)
        drawAcceptedVertices(in: &context, size: size, world: world)
        drawAcceptedEdges(in: &context, size: size, world: world)

        if world.linkHealth < 0.999 {
            drawPartitionBarrier(in: &context, size: size, health: world.linkHealth)
        }
        if let thought = world.thought {
            drawThoughtBubble(in: &context, size: size, thought: thought)
        }
        if let composing = world.composing {
            drawComposingSlot(in: &context, size: size, composing: composing)
        }
        if let flight = world.inFlight {
            drawInFlight(in: &context, size: size, flight: flight)
        }
        if let failed = world.failedFlight {
            drawFailedFlight(in: &context, size: size, failed: failed)
        }

        drawPerceptionTowers(in: &context, size: size, world: world)
        drawBeatTag(in: &context, size: size, world: world)
    }

    // MARK: - Lane geometry / colors / lookups

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

    private func hashOf(_ mid: String) -> String {
        if let m = Ch01Timeline.messages[mid] { return m.hashShort }
        if let m = Ch02Timeline.messages[mid] { return m.hashShort }
        return "????"
    }

    private func parentsOf(_ mid: String) -> [String] {
        if let m = Ch01Timeline.messages[mid] { return m.parents }
        if let m = Ch02Timeline.messages[mid] { return m.parents }
        return []
    }

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
        in context: inout GraphicsContext, size: CGSize,
        world: Ch02WorldState, t: Double
    ) {
        for cast in Ch01Cast.allCases {
            let pos = castPosition(cast: cast, size: size)
            let isActive: Bool = {
                switch world.activeBeat?.kind {
                case .think(let c, _): return c == cast
                case .compose(let mid), .seal(let mid):
                    return Ch02Timeline.messages[mid]?.author == cast
                case .fly(let from, _, _), .flyFailed(let from, _, _):
                    return from == cast
                case .acceptIntoView(let at, _):
                    return at == cast
                default: return false
                }
            }()
            let pulse: CGFloat = isActive ? 1.0 + 0.06 * CGFloat(sin(t * 4)) : 1.0
            let r: CGFloat = 28 * pulse
            let color = castColor(cast)
            let haloR = r * 1.6
            context.fill(
                Circle().path(in: CGRect(x: pos.x - haloR, y: pos.y - haloR,
                                          width: haloR * 2, height: haloR * 2)),
                with: .color(color.opacity(isActive ? 0.22 : 0.10))
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
                    .font(.system(size: settings.scaled(20), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white),
                at: pos
            )
            context.draw(
                Text(cast.role.displayName.uppercased())
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(color.opacity(0.95)),
                at: CGPoint(x: pos.x, y: pos.y + r + 12)
            )
        }
    }

    // MARK: - Accepted vertices on cast lanes

    private func drawAcceptedVertices(
        in context: inout GraphicsContext, size: CGSize, world: Ch02WorldState
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        for (cast, laneIdx) in casts {
            let order = world.viewOrder[cast] ?? []
            let lane = castLaneY(laneIdx, size: size)
            let castX = castPosition(cast: cast, size: size).x
            let firstX = castX + 70
            let gap: CGFloat = 56
            for (i, mid) in order.enumerated() {
                let x = firstX + CGFloat(i) * gap
                if x > size.width - 60 { break }
                drawAcceptedVertex(in: &context, at: CGPoint(x: x, y: lane), messageId: mid)
            }
        }
    }

    private func drawAcceptedVertex(
        in context: inout GraphicsContext, at pos: CGPoint, messageId: String
    ) {
        let r: CGFloat = 14
        let color = castColor(authorOf(messageId))
        let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        context.fill(Circle().path(in: rect),
                    with: .color(color.opacity(0.85)))
        context.stroke(Circle().path(in: rect),
                      with: .color(.white.opacity(0.55)), lineWidth: 1.2)
        context.draw(
            Text(messageId)
                .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
        context.draw(
            Text(hashOf(messageId))
                .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.5)),
            at: CGPoint(x: pos.x, y: pos.y + r + 8)
        )
    }

    private func drawAcceptedEdges(
        in context: inout GraphicsContext, size: CGSize, world: Ch02WorldState
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        for (cast, laneIdx) in casts {
            let order = world.viewOrder[cast] ?? []
            let lane = castLaneY(laneIdx, size: size)
            let castX = castPosition(cast: cast, size: size).x
            let firstX = castX + 70
            let gap: CGFloat = 56
            var positions: [String: CGPoint] = [:]
            for (i, mid) in order.enumerated() {
                positions[mid] = CGPoint(x: firstX + CGFloat(i) * gap, y: lane)
            }
            for (mid, childPos) in positions {
                for parentId in parentsOf(mid) {
                    guard let parentPos = positions[parentId] else { continue }
                    var path = Path()
                    let from = CGPoint(x: childPos.x - 14, y: childPos.y)
                    let to = CGPoint(x: parentPos.x + 14, y: parentPos.y)
                    path.move(to: from)
                    path.addLine(to: to)
                    context.stroke(path,
                                  with: .color(castColor(authorOf(mid)).opacity(0.65)),
                                  lineWidth: 1.2)
                }
            }
        }
    }

    // MARK: - Partition barrier

    private func drawPartitionBarrier(
        in context: inout GraphicsContext, size: CGSize, health: Double
    ) {
        let carlY = castLaneY(2, size: size)
        let daveY = castLaneY(3, size: size)
        let barrierY = (carlY + daveY) / 2
        let intensity = 1.0 - health
        var path = Path()
        path.move(to: CGPoint(x: 36, y: barrierY))
        path.addLine(to: CGPoint(x: size.width - 24, y: barrierY))
        let dashLen = CGFloat(8 + 6 * intensity)
        let gapLen = CGFloat(4 + 4 * intensity)
        context.stroke(path,
                      with: .color(.red.opacity(0.65 * intensity)),
                      style: StrokeStyle(lineWidth: 2.0 + 1.5 * intensity,
                                          dash: [dashLen, gapLen]))
        if intensity > 0.6 {
            let badgeAlpha = (intensity - 0.6) / 0.4
            context.draw(
                Text("⚠ DAVE PARTITIONED")
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(.red.opacity(0.95 * badgeAlpha)),
                at: CGPoint(x: size.width / 2, y: barrierY - 14)
            )
        }
    }

    // MARK: - Thought bubble

    private func drawThoughtBubble(
        in context: inout GraphicsContext, size: CGSize,
        thought: Ch02WorldState.Thought
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

    // MARK: - Composing slot

    private func drawComposingSlot(
        in context: inout GraphicsContext, size: CGSize,
        composing: Ch02WorldState.Composing
    ) {
        guard let msg = Ch02Timeline.messages[composing.messageId] else { return }
        let authorPos = castPosition(cast: composing.author, size: size)
        let boxW: CGFloat = min(540, size.width - 80)
        let boxRect = CGRect(x: size.width / 2 - boxW / 2, y: 16,
                             width: boxW, height: 110)
        let color = castColor(composing.author)
        var connector = Path()
        connector.move(to: CGPoint(x: boxRect.midX, y: boxRect.maxY))
        connector.addLine(to: CGPoint(x: authorPos.x, y: authorPos.y - 36))
        context.stroke(connector,
                      with: .color(color.opacity(0.45)),
                      style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
        context.fill(RoundedRectangle(cornerRadius: 10).path(in: boxRect),
                    with: .color(.black.opacity(0.88)))
        context.stroke(RoundedRectangle(cornerRadius: 10).path(in: boxRect),
                      with: .color(color.opacity(0.95)), lineWidth: 1.5)
        context.draw(
            Text("✎ \(composing.author.role.displayName.uppercased()) WRITING \(composing.messageId)")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(color),
            at: CGPoint(x: boxRect.minX + 14, y: boxRect.minY + 14),
            anchor: .leading
        )
        context.draw(
            Text("payload: \(msg.payload)")
                .font(.system(size: settings.scaled(11), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.88)),
            at: CGPoint(x: boxRect.minX + 14, y: boxRect.minY + 36),
            anchor: .leading
        )
        let parentsText = msg.parents.isEmpty ? "(genesis)" : msg.parents.joined(separator: ", ")
        context.draw(
            Text("parents: \(parentsText)")
                .font(.system(size: settings.scaled(11), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.88)),
            at: CGPoint(x: boxRect.minX + 14, y: boxRect.minY + 54),
            anchor: .leading
        )
        if composing.sealed {
            context.draw(
                Text("hash:    \(msg.hashShort)…  ✓")
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(color.opacity(0.95)),
                at: CGPoint(x: boxRect.minX + 14, y: boxRect.minY + 72),
                anchor: .leading
            )
        }
    }

    // MARK: - In-flight (success)

    private func drawInFlight(
        in context: inout GraphicsContext, size: CGSize,
        flight: Ch02WorldState.InFlight
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
                      with: .color(castColor(flight.from).opacity(0.22)),
                      style: StrokeStyle(lineWidth: 1.0, dash: [3, 5]))
        let p = CGFloat(flight.progress)
        let pos = CGPoint(x: fromTrack.x + (toTrack.x - fromTrack.x) * p,
                          y: fromTrack.y + (toTrack.y - fromTrack.y) * p)
        let envW: CGFloat = 80
        let envH: CGFloat = 30
        let rect = CGRect(x: pos.x - envW / 2, y: pos.y - envH / 2,
                          width: envW, height: envH)
        context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                    with: .color(castColor(flight.from).opacity(0.95)))
        context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                      with: .color(.white.opacity(0.7)), lineWidth: 1.0)
        context.draw(
            Text("\(flight.messageId) · \(hashOf(flight.messageId))")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
    }

    // MARK: - Failed flight (envelope hits the partition barrier)

    private func drawFailedFlight(
        in context: inout GraphicsContext, size: CGSize,
        failed: Ch02WorldState.FailedFlight
    ) {
        let lift: CGFloat = 36
        let from = castPosition(cast: failed.from, size: size)
        let to = castPosition(cast: failed.to, size: size)
        let fromTrack = CGPoint(x: from.x, y: from.y - lift)
        let toTrack = CGPoint(x: to.x, y: to.y - lift)
        let raw = CGFloat(failed.progress)
        let traveled = min(raw, 0.55)
        let fade: Double = raw <= 0.55 ? 1.0 : Double(max(0, 1 - (raw - 0.55) / 0.45))
        let pos = CGPoint(x: fromTrack.x + (toTrack.x - fromTrack.x) * traveled,
                          y: fromTrack.y + (toTrack.y - fromTrack.y) * traveled)

        var path = Path()
        path.move(to: fromTrack)
        path.addLine(to: toTrack)
        context.stroke(path,
                      with: .color(.red.opacity(0.18)),
                      style: StrokeStyle(lineWidth: 1.0, dash: [3, 5]))

        let envW: CGFloat = 80
        let envH: CGFloat = 30
        let rect = CGRect(x: pos.x - envW / 2, y: pos.y - envH / 2,
                          width: envW, height: envH)
        context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                    with: .color(castColor(failed.from).opacity(0.85 * fade)))
        context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                      with: .color(.white.opacity(0.6 * fade)), lineWidth: 1.0)
        context.draw(
            Text("\(failed.messageId) · \(hashOf(failed.messageId))")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(fade)),
            at: pos
        )

        if raw >= 0.55 {
            let impactPos = CGPoint(
                x: fromTrack.x + (toTrack.x - fromTrack.x) * 0.55,
                y: fromTrack.y + (toTrack.y - fromTrack.y) * 0.55
            )
            context.draw(
                Text("✗")
                    .font(.system(size: settings.scaled(24), weight: .heavy, design: .monospaced))
                    .foregroundColor(.red.opacity(0.9)),
                at: impactPos
            )
        }
    }

    // MARK: - Perception towers (5-block height to fit α/β/γ/δ/ε)

    private func drawPerceptionTowers(
        in context: inout GraphicsContext, size: CGSize, world: Ch02WorldState
    ) {
        let casts: [Ch01Cast] = [.aaron, .ben, .carl, .dave]
        let blockH: CGFloat = 22
        let blockGap: CGFloat = 3
        let maxBlocks = 5
        let towerH: CGFloat = CGFloat(maxBlocks) * (blockH + blockGap) + 28
        let baseY: CGFloat = size.height - 90
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

            let order = world.viewOrder[cast] ?? []
            for (j, mid) in order.enumerated() {
                let blockY = baseY - CGFloat(j + 1) * (blockH + blockGap)
                let rect = CGRect(x: towerX + 6, y: blockY,
                                  width: towerW - 12, height: blockH)
                let blockColor = castColor(authorOf(mid))
                context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                            with: .color(blockColor.opacity(0.88)))
                context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                              with: .color(.white.opacity(0.45)), lineWidth: 1.0)
                context.draw(
                    Text("\(mid)  \(hashOf(mid))")
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
        }
    }

    // MARK: - Beat tag

    private func drawBeatTag(
        in context: inout GraphicsContext, size: CGSize, world: Ch02WorldState
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
