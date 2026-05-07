import SwiftUI

/// Ch08 (chapter index 8, file Ch09_DA_Design.swift):
/// "Erasure shards make the data un-loseable." — DA fix.
struct Ch09_DA_Design: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch08Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch08Timeline.state(at: t)
        drawLanes(in: &context, size: size)
        drawCastFigures(in: &context, size: size, world: world)
        drawAaronVault(in: &context, size: size, world: world)
        drawCastVaults(in: &context, size: size, world: world, t: t)
        if let flight = world.shardFlight {
            drawShardFlight(in: &context, size: size, flight: flight)
        }
        if world.aaronOffline {
            drawAaronOfflineBadge(in: &context, size: size)
        }
        if world.reconstructedAlpha > 0 {
            drawReconstructedBadge(in: &context, size: size,
                                    alpha: world.reconstructedAlpha)
        }
        if world.finalAlpha > 0 {
            drawFinalSummary(in: &context, size: size,
                              alpha: world.finalAlpha)
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

    private static let castLanes: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]

    private func drawLanes(in context: inout GraphicsContext, size: CGSize) {
        for (cast, idx) in Self.castLanes {
            let y = castLaneY(idx, size: size)
            var path = Path()
            path.move(to: CGPoint(x: 36, y: y))
            path.addLine(to: CGPoint(x: size.width - 220, y: y))
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

    private func drawCastFigures(
        in context: inout GraphicsContext, size: CGSize, world: Ch08WorldState
    ) {
        for cast in Ch01Cast.allCases {
            let pos = castPosition(cast: cast, size: size)
            let r: CGFloat = 22
            let color = castColor(cast)
            let dim = (cast == .aaron && world.aaronOffline) ? 0.35 : 0.95
            context.fill(
                Circle().path(in: CGRect(x: pos.x - r, y: pos.y - r,
                                          width: r * 2, height: r * 2)),
                with: .color(color.opacity(dim))
            )
            context.draw(
                Text(String(cast.role.displayName.prefix(1)))
                    .font(.system(size: settings.scaled(15), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(dim)),
                at: pos
            )
        }
    }

    /// Aaron's vault on the right showing ξ body + 4 shards once split.
    private func drawAaronVault(
        in context: inout GraphicsContext, size: CGSize, world: Ch08WorldState
    ) {
        let vaultW: CGFloat = 180
        let vaultH: CGFloat = 130
        let vaultX = size.width - vaultW - 24
        let vaultY = castLaneY(0, size: size) - vaultH / 2
        let rect = CGRect(x: vaultX, y: vaultY, width: vaultW, height: vaultH)
        context.fill(RoundedRectangle(cornerRadius: 8).path(in: rect),
                    with: .color(.black.opacity(0.6)))
        let aaronOff = world.aaronOffline
        context.stroke(RoundedRectangle(cornerRadius: 8).path(in: rect),
                      with: .color(Cast.coral.opacity(aaronOff ? 0.3 : 0.7)),
                      style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
        context.draw(
            Text("AARON'S VAULT")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(Cast.coral.opacity(aaronOff ? 0.4 : 0.9)),
            at: CGPoint(x: rect.midX, y: rect.minY + 12)
        )

        // Show 4 shards or full body.
        if world.split {
            // 4 shards stacked horizontally.
            let aaronShards = world.shardsAt[.aaron] ?? []
            let shardW: CGFloat = 32
            let shardH: CGFloat = 56
            let gap: CGFloat = 6
            let totalW = CGFloat(Ch08Timeline.shardIds.count) * (shardW + gap) - gap
            let startX = rect.midX - totalW / 2
            let shardY = rect.minY + 30
            for (i, sid) in Ch08Timeline.shardIds.enumerated() {
                let x = startX + CGFloat(i) * (shardW + gap)
                let chunk = CGRect(x: x, y: shardY, width: shardW, height: shardH)
                let inAaron = aaronShards.contains(sid)
                context.fill(RoundedRectangle(cornerRadius: 3).path(in: chunk),
                            with: .color(Cast.coral.opacity(inAaron ? 0.85
                                                            : (aaronOff ? 0.18 : 0.30))))
                context.stroke(RoundedRectangle(cornerRadius: 3).path(in: chunk),
                              with: .color(.white.opacity(0.4)), lineWidth: 0.8)
                context.draw(
                    Text(sid)
                        .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(inAaron ? 0.95 : 0.45)),
                    at: CGPoint(x: chunk.midX, y: chunk.midY)
                )
            }
            context.draw(
                Text("split: 4 shards · k=2 of 4")
                    .font(.system(size: settings.scaled(9), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55)),
                at: CGPoint(x: rect.midX, y: rect.maxY - 12)
            )
        } else {
            // Full body grid (4×6 chunks).
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
        }
    }

    /// Each non-Aaron cast gets a small vault next to their cast circle
    /// showing whichever shard(s) they currently hold.
    private func drawCastVaults(
        in context: inout GraphicsContext, size: CGSize,
        world: Ch08WorldState, t: Double
    ) {
        for (cast, idx) in Self.castLanes where cast != .aaron {
            let lane = castLaneY(idx, size: size)
            let castX = castPosition(cast: cast, size: size).x
            let vaultX = castX + 50
            let vaultW: CGFloat = 70
            let vaultH: CGFloat = 36
            let rect = CGRect(x: vaultX, y: lane - vaultH / 2,
                              width: vaultW, height: vaultH)
            context.stroke(RoundedRectangle(cornerRadius: 4).path(in: rect),
                          with: .color(castColor(cast).opacity(0.4)),
                          style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            let shards = (world.shardsAt[cast] ?? []).sorted()
            if shards.isEmpty {
                context.draw(
                    Text("(empty)")
                        .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.30)),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            } else {
                // Render shards as small filled chips.
                let chipW: CGFloat = 18
                let chipGap: CGFloat = 4
                let totalW = CGFloat(shards.count) * (chipW + chipGap) - chipGap
                let startX = rect.midX - totalW / 2
                for (i, sid) in shards.enumerated() {
                    let x = startX + CGFloat(i) * (chipW + chipGap)
                    let chip = CGRect(x: x, y: rect.midY - 10,
                                      width: chipW, height: 20)
                    context.fill(RoundedRectangle(cornerRadius: 3).path(in: chip),
                                with: .color(Cast.coral.opacity(0.85)))
                    context.draw(
                        Text(sid)
                            .font(.system(size: settings.scaled(8), weight: .heavy, design: .monospaced))
                            .foregroundColor(.white),
                        at: CGPoint(x: chip.midX, y: chip.midY)
                    )
                }
                // Reconstruction halo: pulsing if Carl just reconstructed.
                let isReconstructing = world.reconstructFlash == cast
                let hasFullBody = world.reconstructedAt.contains(cast)
                    || (world.reconstructedAlpha > 0 && cast == .carl)
                if isReconstructing || hasFullBody {
                    let pulse = isReconstructing ? 0.6 + 0.4 * sin(t * 4) : 0.9
                    context.stroke(RoundedRectangle(cornerRadius: 4).path(in: rect),
                                  with: .color(.green.opacity(pulse)),
                                  lineWidth: 2.0)
                    if hasFullBody {
                        context.draw(
                            Text("✓ ξ body reconstructed")
                                .font(.system(size: settings.scaled(8), weight: .heavy, design: .monospaced))
                                .foregroundColor(.green.opacity(0.95)),
                            at: CGPoint(x: rect.midX, y: rect.maxY + 10)
                        )
                    }
                }
            }
        }
    }

    private func drawShardFlight(
        in context: inout GraphicsContext, size: CGSize,
        flight: Ch08WorldState.ShardFlight
    ) {
        let lift: CGFloat = 30
        let from = castPosition(cast: flight.from, size: size)
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
        let envW: CGFloat = 44
        let envH: CGFloat = 22
        let rect = CGRect(x: pos.x - envW / 2, y: pos.y - envH / 2,
                          width: envW, height: envH)
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: rect),
                    with: .color(Cast.coral.opacity(0.95)))
        context.draw(
            Text(flight.id)
                .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
    }

    private func drawAaronOfflineBadge(
        in context: inout GraphicsContext, size: CGSize
    ) {
        let pos = castPosition(cast: .aaron, size: size)
        context.draw(
            Text("⚠ OFFLINE")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.95)),
            at: CGPoint(x: pos.x, y: pos.y - 38)
        )
    }

    private func drawReconstructedBadge(
        in context: inout GraphicsContext, size: CGSize, alpha: Double
    ) {
        context.draw(
            Text("✓ ξ BODY RECONSTRUCTED — k=2 of 4 shards was enough — Aaron NOT NEEDED")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.95 * alpha)),
            at: CGPoint(x: size.width / 2, y: size.height - 80)
        )
    }

    private func drawFinalSummary(
        in context: inout GraphicsContext, size: CGSize, alpha: Double
    ) {
        context.draw(
            Text("CRISIS COMPLETE  ·  consensus + DA + Byzantine resilience")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.95 * alpha)),
            at: CGPoint(x: size.width / 2, y: size.height - 50)
        )
    }

    private func drawBeatTag(
        in context: inout GraphicsContext, size: CGSize, world: Ch08WorldState
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
