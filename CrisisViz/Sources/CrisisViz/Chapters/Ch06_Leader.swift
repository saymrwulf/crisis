import SwiftUI

/// Ch05 (chapter index 5, file Ch06_Leader.swift):
/// "One vertex per round becomes the spokesperson."
struct Ch06_Leader: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch05Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch05Timeline.state(at: t)
        drawLanes(in: &context, size: size)
        drawCastFigures(in: &context, size: size)
        drawAcceptedVertices(in: &context, size: size, world: world, t: t)
        if world.tiebreakerActive != nil {
            drawTiebreaker(in: &context, size: size, world: world)
        }
        if world.determinismAlpha > 0 {
            drawDeterminismBadge(in: &context, size: size,
                                  alpha: world.determinismAlpha)
        }
        drawPerceptionTowers(in: &context, size: size, world: world)
        drawBeatTag(in: &context, size: size, world: world)
    }

    // MARK: - Geometry

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

    // MARK: - Vertices with candidate rings + leader crown

    private func drawAcceptedVertices(
        in context: inout GraphicsContext, size: CGSize,
        world: Ch05WorldState, t: Double
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
        world: Ch05WorldState, t: Double
    ) {
        let r: CGFloat = 13
        let color = castColor(authorOf(messageId))
        let round = Ch05Timeline.roundOf[messageId] ?? 0

        if let cands = world.candidates[round], cands.contains(messageId) {
            let candR: CGFloat = 19
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - candR, y: pos.y - candR,
                                          width: candR * 2, height: candR * 2)),
                with: .color(.yellow.opacity(0.85)), lineWidth: 1.6
            )
        }
        if world.leaders[round] == messageId {
            let pulse = 0.85 + 0.15 * sin(t * 2.5)
            let crownR: CGFloat = 24
            context.stroke(
                Circle().path(in: CGRect(x: pos.x - crownR, y: pos.y - crownR,
                                          width: crownR * 2, height: crownR * 2)),
                with: .color(.yellow.opacity(0.98 * pulse)), lineWidth: 3.0
            )
            context.draw(
                Text("♛ LEADER · r\(round)")
                    .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.95)),
                at: CGPoint(x: pos.x, y: pos.y - crownR - 10)
            )
        }

        let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        context.fill(Circle().path(in: rect), with: .color(color.opacity(0.85)))
        context.stroke(Circle().path(in: rect),
                      with: .color(.white.opacity(0.55)), lineWidth: 1.0)
        context.draw(
            Text(messageId)
                .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
        if world.weightsVisible[round] == true {
            context.draw(
                Text("w=1 · \(hashOf(messageId))")
                    .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55)),
                at: CGPoint(x: pos.x, y: pos.y + r + 8)
            )
        }
    }

    // MARK: - Tiebreaker

    private func drawTiebreaker(
        in context: inout GraphicsContext, size: CGSize, world: Ch05WorldState
    ) {
        guard let round = world.tiebreakerActive else { return }
        let cands = world.candidates[round] ?? []
        guard !cands.isEmpty else { return }
        let lane = castLaneY(0, size: size) - 50
        let sorted = cands.sorted { hashOf($0) < hashOf($1) }
        let textW: CGFloat = 70
        let totalW = CGFloat(sorted.count) * textW
        let startX = size.width / 2 - totalW / 2
        for (i, mid) in sorted.enumerated() {
            let x = startX + CGFloat(i) * textW
            let isWinner = i == 0
            context.draw(
                Text(hashOf(mid))
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(isWinner ? .yellow.opacity(0.95) : .white.opacity(0.7)),
                at: CGPoint(x: x + textW / 2, y: lane)
            )
            if i < sorted.count - 1 {
                context.draw(
                    Text("<")
                        .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6)),
                    at: CGPoint(x: x + textW, y: lane)
                )
            }
        }
        context.draw(
            Text("LEXICOGRAPHIC HASH COMPARE  →  smallest wins")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.85)),
            at: CGPoint(x: size.width / 2, y: lane - 18)
        )
    }

    private func drawDeterminismBadge(
        in context: inout GraphicsContext, size: CGSize, alpha: Double
    ) {
        context.draw(
            Text("DETERMINISTIC  ·  same DAG → same leaders  ·  no comms required")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.95 * alpha)),
            at: CGPoint(x: size.width / 2, y: size.height - 40)
        )
    }

    // MARK: - Perception towers (with crown indicator on leader blocks)

    private func drawPerceptionTowers(
        in context: inout GraphicsContext, size: CGSize, world: Ch05WorldState
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
                let round = Ch05Timeline.roundOf[mid] ?? 0
                let isLeader = world.leaders[round] == mid
                context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                              with: .color(isLeader ? .yellow.opacity(0.95)
                                                    : .white.opacity(0.45)),
                              lineWidth: isLeader ? 2.2 : 1.0)
                context.draw(
                    Text(isLeader ? "♛ \(mid)" : mid)
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
        }
    }

    private func drawBeatTag(
        in context: inout GraphicsContext, size: CGSize, world: Ch05WorldState
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
