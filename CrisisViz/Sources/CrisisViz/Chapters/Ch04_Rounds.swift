import SwiftUI

/// Ch03 (chapter index 3): "Counting witnesses to mark a round."
///
/// Renders from `Ch03Timeline`. Picks up Ch02's final state ({α, β, γ,
/// δ, ε} on every player's lane), then walks through each message in
/// turn — adding its proof-of-work weight to a thermometer at the top
/// of the canvas — until the threshold is crossed and the round
/// boundary is marked. The chapter shows that round numbers are
/// DERIVED from arithmetic on weight, not declared or negotiated.
struct Ch04_Rounds: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch03Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch03Timeline.state(at: t)

        drawLanes(in: &context, size: size)
        drawCastFigures(in: &context, size: size, t: t)
        drawAcceptedVertices(in: &context, size: size, world: world)
        drawAcceptedEdges(in: &context, size: size, world: world)

        drawThermometer(in: &context, size: size, world: world)

        if let bookkeeping = world.bookkeepingText {
            drawBookkeepingNote(in: &context, size: size, text: bookkeeping)
        }
        if let regossip = world.reGossipFlash {
            drawReGossipDuplicate(in: &context, size: size, regossip: regossip)
        }

        drawPerceptionTowers(in: &context, size: size, world: world)
        drawBeatTag(in: &context, size: size, world: world)
    }

    // MARK: - Geometry / lookup helpers

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

    /// All four cast members hold {α, β, γ, δ, ε} from the carry-forward.
    private var allMessages: [String] { Ch03Timeline.messageOrder }

    // MARK: - Lanes + cast

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

    // MARK: - Accepted vertices on each lane

    private func drawAcceptedVertices(
        in context: inout GraphicsContext, size: CGSize, world: Ch03WorldState
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        for (cast, laneIdx) in casts {
            let lane = castLaneY(laneIdx, size: size)
            let castX = castPosition(cast: cast, size: size).x
            let firstX = castX + 70
            let gap: CGFloat = 56
            for (i, mid) in allMessages.enumerated() {
                let x = firstX + CGFloat(i) * gap
                if x > size.width - 60 { break }
                drawAcceptedVertex(
                    in: &context, at: CGPoint(x: x, y: lane),
                    messageId: mid, world: world
                )
            }
        }
    }

    private func drawAcceptedVertex(
        in context: inout GraphicsContext, at pos: CGPoint,
        messageId: String, world: Ch03WorldState
    ) {
        let r: CGFloat = 14
        let color = castColor(authorOf(messageId))
        let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)

        // Highlight halo if this vertex is the active focus.
        if world.highlighted == messageId {
            let haloR: CGFloat = 24
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - haloR, y: pos.y - haloR,
                                          width: haloR * 2, height: haloR * 2)),
                with: .color(.white.opacity(0.55)), lineWidth: 1.5
            )
        }

        // is_last yellow ring
        if world.isLastSet.contains(messageId) {
            let ringR: CGFloat = 21
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - ringR, y: pos.y - ringR,
                                          width: ringR * 2, height: ringR * 2)),
                with: .color(.yellow.opacity(0.95)), lineWidth: 2.4
            )
        }

        context.fill(Circle().path(in: rect), with: .color(color.opacity(0.85)))
        context.stroke(Circle().path(in: rect),
                      with: .color(.white.opacity(0.55)), lineWidth: 1.2)
        context.draw(
            Text(messageId)
                .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )

        // Hash + weight + round number below
        var sub: String = hashOf(messageId)
        if world.weightsVisible {
            let round = world.roundOf[messageId] ?? 0
            sub = "w=1  r=\(round)"
        }
        context.draw(
            Text(sub)
                .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.55)),
            at: CGPoint(x: pos.x, y: pos.y + r + 8)
        )

        // is_last label
        if world.isLastSet.contains(messageId) {
            context.draw(
                Text("is_last")
                    .font(.system(size: settings.scaled(8), weight: .heavy, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.95)),
                at: CGPoint(x: pos.x, y: pos.y - r - 10)
            )
        }
    }

    private func drawAcceptedEdges(
        in context: inout GraphicsContext, size: CGSize, world: Ch03WorldState
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        for (_, laneIdx) in casts {
            let lane = castLaneY(laneIdx, size: size)
            let castX = castPosition(cast: .aaron, size: size).x  // all use same x
            let firstX = castX + 70
            let gap: CGFloat = 56
            var positions: [String: CGPoint] = [:]
            for (i, mid) in allMessages.enumerated() {
                positions[mid] = CGPoint(x: firstX + CGFloat(i) * gap, y: lane)
            }
            for (mid, childPos) in positions {
                for parentId in parentsOf(mid) {
                    guard let parentPos = positions[parentId] else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: childPos.x - 14, y: childPos.y))
                    path.addLine(to: CGPoint(x: parentPos.x + 14, y: parentPos.y))
                    context.stroke(path,
                                  with: .color(castColor(authorOf(mid)).opacity(0.55)),
                                  lineWidth: 1.0)
                }
            }
        }
    }

    // MARK: - Weight thermometer (top of canvas)

    private func drawThermometer(
        in context: inout GraphicsContext, size: CGSize, world: Ch03WorldState
    ) {
        // Horizontal bar near the top of the canvas. Width sized so the
        // composing-slot space is preserved, although Ch03 doesn't use
        // the slot.
        let barW: CGFloat = min(560, size.width - 100)
        let barH: CGFloat = 26
        let barX = size.width / 2 - barW / 2
        let barY: CGFloat = 18
        let rect = CGRect(x: barX, y: barY, width: barW, height: barH)

        // Frame
        context.fill(RoundedRectangle(cornerRadius: 6).path(in: rect),
                    with: .color(.black.opacity(0.7)))
        context.stroke(RoundedRectangle(cornerRadius: 6).path(in: rect),
                      with: .color(.white.opacity(0.5)), lineWidth: 1.0)

        // Threshold tick (proportional to threshold within max=5)
        let maxBar: Double = 5
        let threshFrac = world.thermometerThreshold / maxBar
        let threshX = barX + CGFloat(threshFrac) * barW
        var threshLine = Path()
        threshLine.move(to: CGPoint(x: threshX, y: barY - 4))
        threshLine.addLine(to: CGPoint(x: threshX, y: barY + barH + 4))
        context.stroke(threshLine,
                      with: .color(.yellow.opacity(0.85)),
                      style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
        context.draw(
            Text("threshold = \(Int(world.thermometerThreshold))")
                .font(.system(size: settings.scaled(8), weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.85)),
            at: CGPoint(x: threshX, y: barY - 14)
        )

        // Fill
        let fillFrac = min(1.0, world.thermometerWeight / maxBar)
        let fillW = CGFloat(fillFrac) * barW
        if fillW > 0 {
            let fillRect = CGRect(x: barX, y: barY, width: fillW, height: barH)
            context.fill(RoundedRectangle(cornerRadius: 6).path(in: fillRect),
                        with: .color(.green.opacity(0.7)))
        }

        // Label
        let label = String(format: "ROUND %d  ·  weight = %.0f / %d",
                           world.currentRound,
                           world.thermometerWeight,
                           Int(world.thermometerThreshold))
        context.draw(
            Text(label)
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.95)),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    // MARK: - Bookkeeping note + re-gossip duplicate

    private func drawBookkeepingNote(
        in context: inout GraphicsContext, size: CGSize, text: String
    ) {
        // Sits under the thermometer.
        let cy: CGFloat = 64
        let rect = CGRect(x: size.width / 2 - 280, y: cy - 14,
                          width: 560, height: 28)
        context.fill(RoundedRectangle(cornerRadius: 6).path(in: rect),
                    with: .color(.black.opacity(0.55)))
        context.stroke(RoundedRectangle(cornerRadius: 6).path(in: rect),
                      with: .color(.white.opacity(0.35)), lineWidth: 0.8)
        context.draw(
            Text(text)
                .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85)),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    private func drawReGossipDuplicate(
        in context: inout GraphicsContext, size: CGSize,
        regossip: Ch03WorldState.ReGossip
    ) {
        // The duplicate envelope flies from Aaron toward the recipient,
        // arrives, then displays a "DROP — duplicate" label that fades.
        let from = castPosition(cast: .aaron, size: size)
        let to = castPosition(cast: regossip.recipient, size: size)
        let lift: CGFloat = 36
        let fromTrack = CGPoint(x: from.x, y: from.y - lift)
        let toTrack = CGPoint(x: to.x, y: to.y - lift)
        // Path
        var path = Path()
        path.move(to: fromTrack)
        path.addLine(to: toTrack)
        context.stroke(path,
                      with: .color(.white.opacity(0.18)),
                      style: StrokeStyle(lineWidth: 1.0, dash: [3, 5]))
        let p = CGFloat(min(1.0, regossip.progress * 1.5))  // arrives at 0.67
        let pos = CGPoint(x: fromTrack.x + (toTrack.x - fromTrack.x) * p,
                          y: fromTrack.y + (toTrack.y - fromTrack.y) * p)
        let envW: CGFloat = 78
        let envH: CGFloat = 28
        let rect = CGRect(x: pos.x - envW / 2, y: pos.y - envH / 2,
                          width: envW, height: envH)
        let envFade = regossip.progress < 0.7 ? 1.0 : Double(max(0, 1 - (regossip.progress - 0.7) / 0.3))
        context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                    with: .color(Cast.coral.opacity(0.85 * envFade)))
        context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                      with: .color(.white.opacity(0.55 * envFade)),
                      lineWidth: 1.0)
        context.draw(
            Text("\(regossip.messageId) (re-gossip)")
                .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(envFade)),
            at: pos
        )
        // "✗ duplicate dropped" label appears once envelope is at recipient
        if regossip.progress > 0.65 {
            let alpha = min(1.0, (regossip.progress - 0.65) / 0.2)
            context.draw(
                Text("✗ DUPLICATE — DROPPED")
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(.red.opacity(0.95 * alpha)),
                at: CGPoint(x: to.x, y: to.y - 60)
            )
        }
    }

    // MARK: - Perception towers

    private func drawPerceptionTowers(
        in context: inout GraphicsContext, size: CGSize, world: Ch03WorldState
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

            // Blocks: all five messages in alphabetical order
            for (j, mid) in allMessages.enumerated() {
                let blockY = baseY - CGFloat(j + 1) * (blockH + blockGap)
                let rect = CGRect(x: towerX + 6, y: blockY,
                                  width: towerW - 12, height: blockH)
                let blockColor = castColor(authorOf(mid))
                context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                            with: .color(blockColor.opacity(0.88)))
                context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                              with: .color(.white.opacity(0.45)), lineWidth: 1.0)
                // is_last yellow accent
                if world.isLastSet.contains(mid) {
                    context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                                  with: .color(.yellow.opacity(0.95)),
                                  lineWidth: 2.0)
                }
                let round = world.roundOf[mid] ?? 0
                context.draw(
                    Text("\(mid)  r\(round)")
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
        }
    }

    // MARK: - Beat tag

    private func drawBeatTag(
        in context: inout GraphicsContext, size: CGSize, world: Ch03WorldState
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
