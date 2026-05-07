import SwiftUI

/// Ch07 (chapter index 7, file Ch08_DA_Problem.swift):
/// "The leader knows. Did the leader tell anyone?" — DA problem.
struct Ch08_DA_Problem: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch07Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch07Timeline.state(at: t)
        drawLanes(in: &context, size: size)
        drawCastFigures(in: &context, size: size)
        drawAcceptedVertices(in: &context, size: size, world: world)
        drawAaronVault(in: &context, size: size, world: world, t: t)
        if let flight = world.hashFlight {
            drawHashFlight(in: &context, size: size, flight: flight)
        }
        if let ask = world.askArrow {
            drawAskArrow(in: &context, size: size, ask: ask)
        }
        if let asker = world.timeoutFlash {
            drawTimeoutFlash(in: &context, size: size, asker: asker, t: t)
        }
        if world.stuckAlpha > 0 {
            drawStuckBadge(in: &context, size: size, alpha: world.stuckAlpha)
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
        return CGPoint(x: size.width * 0.18, y: castLaneY(laneIdx, size: size))
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
        if mid == "ξ" { return .aaron }
        if let m = Ch01Timeline.messages[mid] { return m.author }
        if let m = Ch02Timeline.messages[mid] { return m.author }
        return .aaron
    }

    private static let initialMessages: [String] = ["α", "β", "γ", "δ", "ε"]
    private static let castLanes: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]

    /// X position for ξ on a lane — it sits past ε, in the rightmost slot.
    private func xiPosition(cast: Ch01Cast, size: CGSize) -> CGPoint {
        let laneIdx: Int
        switch cast {
        case .aaron: laneIdx = 0
        case .ben:   laneIdx = 1
        case .carl:  laneIdx = 2
        case .dave:  laneIdx = 3
        }
        let lane = castLaneY(laneIdx, size: size)
        let baseX = castPosition(cast: cast, size: size).x + 70
        // 5 initial messages + ξ as #6
        return CGPoint(x: baseX + 5 * 50, y: lane)
    }

    private func vertexPosition(cast: Ch01Cast, mid: String, size: CGSize) -> CGPoint? {
        if mid == "ξ" { return xiPosition(cast: cast, size: size) }
        guard let i = Self.initialMessages.firstIndex(of: mid) else { return nil }
        let laneIdx: Int
        switch cast {
        case .aaron: laneIdx = 0
        case .ben:   laneIdx = 1
        case .carl:  laneIdx = 2
        case .dave:  laneIdx = 3
        }
        let lane = castLaneY(laneIdx, size: size)
        let castX = castPosition(cast: cast, size: size).x
        return CGPoint(x: castX + 70 + CGFloat(i) * 50, y: lane)
    }

    // MARK: - Lanes / cast / vertices

    private func drawLanes(in context: inout GraphicsContext, size: CGSize) {
        for (cast, idx) in Self.castLanes {
            let y = castLaneY(idx, size: size)
            var path = Path()
            path.move(to: CGPoint(x: 36, y: y))
            path.addLine(to: CGPoint(x: size.width - 200, y: y))  // leave room for vault
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
            let r: CGFloat = 22
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
                    .font(.system(size: settings.scaled(15), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white),
                at: pos
            )
        }
    }

    private func drawAcceptedVertices(
        in context: inout GraphicsContext, size: CGSize, world: Ch07WorldState
    ) {
        for (cast, _) in Self.castLanes {
            // Carry-forward α-ε on every lane
            for mid in Self.initialMessages {
                guard let pos = vertexPosition(cast: cast, mid: mid, size: size) else { continue }
                let r: CGFloat = 11
                let color = castColor(authorOf(mid))
                let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                context.fill(Circle().path(in: rect), with: .color(color.opacity(0.85)))
                context.draw(
                    Text(mid)
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white),
                    at: pos
                )
            }
            // ξ: only on lanes that have it (Aaron always once sealed; Ben/Carl after sendHashOnly)
            let hasXi: Bool = (cast == .aaron && world.xiSealed)
                || world.xiInView.contains(cast)
            if hasXi {
                let pos = xiPosition(cast: cast, size: size)
                let r: CGFloat = 14
                let color = Cast.coral  // Aaron is the author
                let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                context.fill(Circle().path(in: rect),
                            with: .color(color.opacity(0.85)))
                context.stroke(Circle().path(in: rect),
                              with: .color(.white.opacity(0.6)), lineWidth: 1.0)
                context.draw(
                    Text("ξ")
                        .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white),
                    at: pos
                )
                // ⚠ BODY MISSING flag
                if world.bodyMissingAt.contains(cast) {
                    context.draw(
                        Text("⚠ BODY MISSING")
                            .font(.system(size: settings.scaled(8), weight: .heavy, design: .monospaced))
                            .foregroundColor(.red.opacity(0.95)),
                        at: CGPoint(x: pos.x, y: pos.y - r - 10)
                    )
                }
            }
        }
    }

    // MARK: - Aaron's vault (storage column on the right)

    private func drawAaronVault(
        in context: inout GraphicsContext, size: CGSize,
        world: Ch07WorldState, t: Double
    ) {
        // Vault sits in the right margin, vertically aligned roughly
        // with Aaron's lane.
        let vaultW: CGFloat = 160
        let vaultH: CGFloat = 130
        let vaultX = size.width - vaultW - 24
        let vaultY = castLaneY(0, size: size) - vaultH / 2
        let rect = CGRect(x: vaultX, y: vaultY, width: vaultW, height: vaultH)

        context.fill(RoundedRectangle(cornerRadius: 8).path(in: rect),
                    with: .color(.black.opacity(0.6)))
        context.stroke(RoundedRectangle(cornerRadius: 8).path(in: rect),
                      with: .color(Cast.coral.opacity(0.7)),
                      style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
        context.draw(
            Text("AARON'S VAULT")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(Cast.coral.opacity(0.9)),
            at: CGPoint(x: rect.midX, y: rect.minY + 12)
        )
        // Body chunks visible as small filled rectangles inside the vault
        if world.xiBodyInAaronVault {
            let chunksRows = 4
            let chunksCols = 6
            let chunkW: CGFloat = 18
            let chunkH: CGFloat = 12
            let gridX = rect.minX + (rect.width - CGFloat(chunksCols) * (chunkW + 2)) / 2
            let gridY = rect.minY + 30
            for row in 0..<chunksRows {
                for col in 0..<chunksCols {
                    let x = gridX + CGFloat(col) * (chunkW + 2)
                    let y = gridY + CGFloat(row) * (chunkH + 2)
                    let chunkRect = CGRect(x: x, y: y, width: chunkW, height: chunkH)
                    context.fill(RoundedRectangle(cornerRadius: 2).path(in: chunkRect),
                                with: .color(Cast.coral.opacity(0.85)))
                }
            }
            context.draw(
                Text("ξ body  ·  1 MB")
                    .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85)),
                at: CGPoint(x: rect.midX, y: rect.maxY - 12)
            )
        } else {
            context.draw(
                Text("(empty)")
                    .font(.system(size: settings.scaled(9), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4)),
                at: CGPoint(x: rect.midX, y: rect.midY)
            )
        }
    }

    // MARK: - Hash-only flight envelope (small, with ⚠)

    private func drawHashFlight(
        in context: inout GraphicsContext, size: CGSize,
        flight: Ch07WorldState.HashFlight
    ) {
        let lift: CGFloat = 36
        let from = castPosition(cast: .aaron, size: size)
        let to = castPosition(cast: flight.to, size: size)
        let fromTrack = CGPoint(x: from.x, y: from.y - lift)
        let toTrack = CGPoint(x: to.x, y: to.y - lift)
        var path = Path()
        path.move(to: fromTrack)
        path.addLine(to: toTrack)
        context.stroke(path, with: .color(Cast.coral.opacity(0.22)),
                      style: StrokeStyle(lineWidth: 1.0, dash: [3, 5]))
        let p = CGFloat(flight.progress)
        let pos = CGPoint(x: fromTrack.x + (toTrack.x - fromTrack.x) * p,
                          y: fromTrack.y + (toTrack.y - fromTrack.y) * p)
        // Smaller envelope (hash only, no body)
        let envW: CGFloat = 52
        let envH: CGFloat = 22
        let rect = CGRect(x: pos.x - envW / 2, y: pos.y - envH / 2,
                          width: envW, height: envH)
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: rect),
                    with: .color(Cast.coral.opacity(0.95)))
        context.stroke(RoundedRectangle(cornerRadius: 4).path(in: rect),
                      with: .color(.white.opacity(0.7)), lineWidth: 1.0)
        context.draw(
            Text("ξ hash")
                .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
    }

    // MARK: - Ask arrow + timeout flash

    private func drawAskArrow(
        in context: inout GraphicsContext, size: CGSize,
        ask: Ch07WorldState.AskArrow
    ) {
        let from = castPosition(cast: ask.asker, size: size)
        let to = castPosition(cast: .aaron, size: size)
        let p = CGFloat(ask.progress)
        let endX = from.x + (to.x - from.x) * p
        let endY = from.y + (to.y - from.y) * p
        var path = Path()
        path.move(to: from)
        path.addLine(to: CGPoint(x: endX, y: endY))
        context.stroke(path,
                      with: .color(.white.opacity(0.6)),
                      style: StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
        context.draw(
            Text("? ξ body please")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.85)),
            at: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - 14)
        )
    }

    private func drawTimeoutFlash(
        in context: inout GraphicsContext, size: CGSize,
        asker: Ch01Cast, t: Double
    ) {
        let from = castPosition(cast: asker, size: size)
        let to = castPosition(cast: .aaron, size: size)
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let pulse = 0.7 + 0.3 * sin(t * 4)
        context.draw(
            Text("✗")
                .font(.system(size: settings.scaled(28), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.95 * pulse)),
            at: mid
        )
        context.draw(
            Text("AARON SILENT — REQUEST TIMED OUT")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.95)),
            at: CGPoint(x: mid.x, y: mid.y + 24)
        )
    }

    // MARK: - Stuck badge

    private func drawStuckBadge(
        in context: inout GraphicsContext, size: CGSize, alpha: Double
    ) {
        context.draw(
            Text("⛔ DA PROBLEM — Aaron knows ξ's body. Nobody else can use it.")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.95 * alpha)),
            at: CGPoint(x: size.width / 2, y: size.height - 60)
        )
        context.draw(
            Text("→ erasure coding (next chapter) makes data un-loseable.")
                .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.85 * alpha)),
            at: CGPoint(x: size.width / 2, y: size.height - 40)
        )
    }

    private func drawBeatTag(
        in context: inout GraphicsContext, size: CGSize, world: Ch07WorldState
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
