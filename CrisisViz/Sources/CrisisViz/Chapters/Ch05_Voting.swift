import SwiftUI

/// Ch04 (chapter index 4, file Ch05_Voting.swift):
/// "Did you see what I saw?" — virtual voting via strongly-seeing paths.
///
/// Renders from `Ch04Timeline`. Picks Aaron's recent vertex ε on his
/// lane, picks Carl's ε on his, walks each ancestor cone (ε → γ → α)
/// edge by edge, then highlights the overlap.
struct Ch05_Voting: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch04Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch04Timeline.state(at: t)
        drawLanes(in: &context, size: size)
        drawCastFigures(in: &context, size: size)
        drawAcceptedVertices(in: &context, size: size, world: world, t: t)
        drawAcceptedEdges(in: &context, size: size)
        if let edge = world.tracingEdge {
            drawTracingEdge(in: &context, size: size, edge: edge)
        }
        if world.voteCompleteAlpha > 0 {
            drawVoteComplete(in: &context, size: size, alpha: world.voteCompleteAlpha)
        }
        drawPerceptionTowers(in: &context, size: size)
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
        if let m = Ch01Timeline.messages[mid] { return m.author }
        if let m = Ch02Timeline.messages[mid] { return m.author }
        return .aaron
    }

    private func parentsOf(_ mid: String) -> [String] {
        if let m = Ch01Timeline.messages[mid] { return m.parents }
        if let m = Ch02Timeline.messages[mid] { return m.parents }
        return []
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

    // MARK: - Lanes / cast

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

    // MARK: - Vertices with cone halos + overlap pulse

    private func drawAcceptedVertices(
        in context: inout GraphicsContext, size: CGSize,
        world: Ch04WorldState, t: Double
    ) {
        for (cast, _) in Self.castLanes {
            for mid in Self.allMessages {
                guard let pos = vertexPosition(cast: cast, mid: mid, size: size) else { continue }
                drawVertex(in: &context, at: pos, messageId: mid,
                           cast: cast, world: world, t: t)
            }
        }
    }

    private func drawVertex(
        in context: inout GraphicsContext, at pos: CGPoint,
        messageId: String, cast: Ch01Cast,
        world: Ch04WorldState, t: Double
    ) {
        let r: CGFloat = 13
        let color = castColor(authorOf(messageId))

        // Leaf halo
        if world.leaves[cast] == messageId {
            let leafR: CGFloat = 22
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - leafR, y: pos.y - leafR,
                                          width: leafR * 2, height: leafR * 2)),
                with: .color(.yellow.opacity(0.95)), lineWidth: 2.4
            )
        }
        // Cone ring
        let inCone = world.cones[cast]?.contains(messageId) ?? false
        if inCone && world.leaves[cast] != messageId {
            let coneR: CGFloat = 19
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - coneR, y: pos.y - coneR,
                                          width: coneR * 2, height: coneR * 2)),
                with: .color(.yellow.opacity(0.85)), lineWidth: 1.8
            )
        }
        // Overlap pulse
        let isOverlapMember = world.overlapAlpha > 0
            && world.overlap.contains(messageId)
            && (cast == .aaron || cast == .carl)
        if isOverlapMember {
            let pulse = 0.7 + 0.3 * sin(t * 3)
            let oR: CGFloat = 26
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - oR, y: pos.y - oR,
                                          width: oR * 2, height: oR * 2)),
                with: .color(.white.opacity(0.9 * world.overlapAlpha * pulse)),
                lineWidth: 2.0
            )
        }

        let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        context.fill(Circle().path(in: rect),
                    with: .color(color.opacity(0.85)))
        context.stroke(Circle().path(in: rect),
                      with: .color(.white.opacity(0.55)), lineWidth: 1.0)
        context.draw(
            Text(messageId)
                .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
    }

    private func drawAcceptedEdges(in context: inout GraphicsContext, size: CGSize) {
        for (cast, _) in Self.castLanes {
            for mid in Self.allMessages {
                guard let childPos = vertexPosition(cast: cast, mid: mid, size: size) else { continue }
                for parent in parentsOf(mid) {
                    guard let parentPos = vertexPosition(cast: cast, mid: parent, size: size) else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: childPos.x - 14, y: childPos.y))
                    path.addLine(to: CGPoint(x: parentPos.x + 14, y: parentPos.y))
                    context.stroke(path,
                                  with: .color(castColor(authorOf(mid)).opacity(0.45)),
                                  lineWidth: 1.0)
                }
            }
        }
    }

    // MARK: - Tracing edge

    private func drawTracingEdge(
        in context: inout GraphicsContext, size: CGSize,
        edge: Ch04WorldState.TracingEdge
    ) {
        guard let childPos = vertexPosition(cast: edge.cast, mid: edge.from, size: size),
              let parentPos = vertexPosition(cast: edge.cast, mid: edge.to, size: size) else { return }
        let p = CGFloat(edge.progress)
        let from = CGPoint(x: childPos.x - 14, y: childPos.y)
        let to = CGPoint(x: parentPos.x + 14, y: parentPos.y)
        let head = CGPoint(x: from.x + (to.x - from.x) * p,
                           y: from.y + (to.y - from.y) * p)
        var full = Path(); full.move(to: from); full.addLine(to: to)
        context.stroke(full, with: .color(.yellow.opacity(0.45)),
                      lineWidth: 1.8)
        var trace = Path(); trace.move(to: from); trace.addLine(to: head)
        context.stroke(trace, with: .color(.yellow.opacity(0.95)),
                      lineWidth: 3.0)
        context.fill(Circle().path(in: CGRect(x: head.x - 4, y: head.y - 4,
                                               width: 8, height: 8)),
                    with: .color(.yellow.opacity(0.95)))
    }

    // MARK: - Vote complete banner

    private func drawVoteComplete(
        in context: inout GraphicsContext, size: CGSize, alpha: Double
    ) {
        context.draw(
            Text("✓ IMPLICIT VOTE COMPLETE — no 'vote' message was ever sent")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.95 * alpha)),
            at: CGPoint(x: size.width / 2, y: size.height - 50)
        )
    }

    // MARK: - Perception towers

    private func drawPerceptionTowers(in context: inout GraphicsContext, size: CGSize) {
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
            context.stroke(baseline, with: .color(color.opacity(0.45)), lineWidth: 1.2)
            for railX in [towerX, towerX + towerW] {
                var rail = Path()
                rail.move(to: CGPoint(x: railX, y: baseY))
                rail.addLine(to: CGPoint(x: railX, y: baseY - towerH + 26))
                context.stroke(rail, with: .color(color.opacity(0.18)),
                              style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
            }
            for (j, mid) in Self.allMessages.enumerated() {
                let blockY = baseY - CGFloat(j + 1) * (blockH + blockGap)
                let rect = CGRect(x: towerX + 6, y: blockY,
                                  width: towerW - 12, height: blockH)
                let blockColor = castColor(authorOf(mid))
                context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                            with: .color(blockColor.opacity(0.88)))
                context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                              with: .color(.white.opacity(0.45)), lineWidth: 1.0)
                context.draw(
                    Text(mid)
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
        }
    }

    private func drawBeatTag(
        in context: inout GraphicsContext, size: CGSize, world: Ch04WorldState
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
