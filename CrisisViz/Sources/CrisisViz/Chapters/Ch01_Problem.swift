import SwiftUI

/// Ch00 (chapter index 0): "Four friends, one ledger, no boss."
///
/// The redesigned opener. Where the original chapter showed three anonymous
/// "Node 1/2/3" circles in a triangle, this version introduces the four
/// named cast members — Aaron, Ben, Carl, Dave — one at a time. By the
/// time the chapter ends, the viewer can match each name to a color and
/// has met Dave as the Byzantine actor. Every later chapter morphs from
/// that established cast.
///
/// Scene 0: Cast intro. Four portraits fade in sequentially, each holding
///          for ~1.5 s with a personality cue. Dave arrives last with a
///          BYZ badge so the viewer sees the trouble coming.
/// Scene 1: Conflicting logs. Each cast member writes a different ordering
///          of three transactions to make "no shared truth yet" concrete.
/// Scene 2: The question. Network backdrop dims; the framing question
///          ("HOW DO WE AGREE?") fades in.
struct Ch01_Problem: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            render(context: &context, size: size, time: localTime)
        }
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard let sim = dm.sim else {
            context.draw(Text("Loading...").foregroundColor(.white),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        switch sceneIndex {
        case 0:
            renderCastIntro(context: &context, size: size, time: time)
        case 1:
            renderConflictingLogs(context: &context, size: size, time: time)
        case 2:
            renderTheQuestion(context: &context, size: size, time: time, sim: sim)
        default:
            break
        }
    }

    // MARK: - Scene 0: cast intro
    //
    // Four portraits arranged in a 2x2 grid. They appear one at a time,
    // each pinned at ~1.5 s, so the viewer has time to read the name and
    // the personality cue before the next character arrives. Dave appears
    // last and is the only one with a BYZ badge.

    private func renderCastIntro(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2

        // 2x2 layout, generous spacing.
        let dx: CGFloat = min(size.width * 0.22, 220)
        let dy: CGFloat = min(size.height * 0.22, 180)
        let positions: [CGPoint] = [
            CGPoint(x: cx - dx, y: cy - dy),  // Aaron — top left
            CGPoint(x: cx + dx, y: cy - dy),  // Ben   — top right
            CGPoint(x: cx - dx, y: cy + dy),  // Carl  — bottom left
            CGPoint(x: cx + dx, y: cy + dy),  // Dave  — bottom right
        ]

        let leads = Cast.leads
        let arrivalInterval: Double = 1.5

        for (i, role) in leads.enumerated() {
            let arriveAt = Double(i) * arrivalInterval
            let appear = max(0, min(1, (time - arriveAt) / 0.6))
            if appear < 0.01 { continue }

            drawCastPortrait(
                context: &context,
                center: positions[i],
                role: role,
                appear: appear,
                pulse: 1.0 + 0.04 * sin(time * 1.6 + Double(i) * 0.9)
            )
        }

        // Title fades in at the start, lingers throughout.
        let titleAlpha = min(1.0, time / 0.8)
        context.draw(
            Text("Meet the cast.")
                .font(.system(size: settings.scaled(20), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.85 * titleAlpha)),
            at: CGPoint(x: cx, y: 56)
        )
    }

    private func drawCastPortrait(
        context: inout GraphicsContext,
        center: CGPoint, role: CastRole,
        appear: Double, pulse: CGFloat
    ) {
        let nodeRadius: CGFloat = 44 * pulse

        // Soft glow halo.
        let glowR: CGFloat = nodeRadius * 1.9
        let glowRect = CGRect(x: center.x - glowR, y: center.y - glowR,
                              width: glowR * 2, height: glowR * 2)
        context.fill(
            Circle().path(in: glowRect),
            with: .color(role.color.opacity(0.10 * appear))
        )

        // Body circle.
        let bodyRect = CGRect(x: center.x - nodeRadius, y: center.y - nodeRadius,
                              width: nodeRadius * 2, height: nodeRadius * 2)
        context.fill(
            Circle().path(in: bodyRect),
            with: .color(role.color.opacity(0.85 * appear))
        )
        context.stroke(
            Circle().path(in: bodyRect),
            with: .color(role.color.opacity(0.6 * appear)),
            lineWidth: 1.5
        )

        // Initial inside the circle.
        let initial = String(role.displayName.prefix(1))
        context.draw(
            Text(initial)
                .font(.system(size: settings.scaled(28), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.95 * appear)),
            at: center
        )

        // Display name beneath.
        context.draw(
            Text(role.displayName)
                .font(.system(size: settings.scaled(15), weight: .heavy, design: .monospaced))
                .foregroundColor(role.color.opacity(0.95 * appear)),
            at: CGPoint(x: center.x, y: center.y + nodeRadius + 18)
        )

        // Personality cue.
        context.draw(
            Text(role.cue)
                .font(.system(size: settings.scaled(11), weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.62 * appear)),
            at: CGPoint(x: center.x, y: center.y + nodeRadius + 36)
        )

        // BYZ badge for Dave.
        if role.isByzantineSlot {
            let badgeRect = CGRect(x: center.x + nodeRadius - 14, y: center.y - nodeRadius - 6,
                                   width: 36, height: 16)
            context.fill(
                RoundedRectangle(cornerRadius: 3).path(in: badgeRect),
                with: .color(.red.opacity(0.30 * appear))
            )
            context.stroke(
                RoundedRectangle(cornerRadius: 3).path(in: badgeRect),
                with: .color(.red.opacity(0.85 * appear)),
                lineWidth: 1
            )
            context.draw(
                Text("BYZ")
                    .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                    .foregroundColor(.red.opacity(0.95 * appear)),
                at: CGPoint(x: badgeRect.midX, y: badgeRect.midY)
            )
        }
    }

    // MARK: - Scene 1: conflicting logs
    //
    // Each of the four cast members writes a DIFFERENT ordering of three
    // transactions (tx-A, tx-B, tx-C), to make "everyone has their own
    // story" concrete. Aaron's order, Ben's order, Carl's order, Dave's
    // order — all internally consistent, all different.

    private func renderConflictingLogs(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2

        let dx: CGFloat = min(size.width * 0.22, 220)
        let dy: CGFloat = min(size.height * 0.22, 180)
        let positions: [CGPoint] = [
            CGPoint(x: cx - dx, y: cy - dy),
            CGPoint(x: cx + dx, y: cy - dy),
            CGPoint(x: cx - dx, y: cy + dy),
            CGPoint(x: cx + dx, y: cy + dy),
        ]

        // Four different orderings. Aaron's matches the "true" arrival
        // order tx-A → tx-B → tx-C; the others have permuted views.
        let txOrders: [[String]] = [
            ["tx-A", "tx-B", "tx-C"],   // Aaron
            ["tx-B", "tx-A", "tx-C"],   // Ben
            ["tx-C", "tx-A", "tx-B"],   // Carl
            ["tx-B", "tx-C", "tx-A"],   // Dave
        ]
        let txColors: [String: Color] = [
            "tx-A": .cyan,
            "tx-B": .yellow,
            "tx-C": .pink,
        ]
        let leads = Cast.leads

        // Soft connecting lines between every pair (suggests a network).
        for i in 0..<leads.count {
            for j in (i + 1)..<leads.count {
                var line = Path()
                line.move(to: positions[i])
                line.addLine(to: positions[j])
                context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            }
        }

        // Drifting message particles between random pairs (out-of-order arrival).
        let particleCount = 24
        for p in 0..<particleCount {
            let seed = Double(p * 7919)
            let fromIdx = Int(seed.truncatingRemainder(dividingBy: 4))
            let toIdx = (fromIdx + 1 + Int(seed * 0.3) % 3) % 4
            let phase = (time * 0.20 + seed * 0.071).truncatingRemainder(dividingBy: 1.0)
            let from = positions[fromIdx]
            let to = positions[toIdx]
            let px = from.x + (to.x - from.x) * phase
            let py = from.y + (to.y - from.y) * phase

            let txKeys = ["tx-A", "tx-B", "tx-C"]
            let txKey = txKeys[Int(seed * 0.13) % 3]
            let txColor = txColors[txKey] ?? .white
            let r: CGFloat = 3
            let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
            context.fill(
                Circle().path(in: rect),
                with: .color(txColor.opacity(0.5 + 0.4 * (1 - phase)))
            )
        }

        // Cast portraits + each one's log of three transactions.
        for (i, role) in leads.enumerated() {
            let pos = positions[i]
            let pulse: CGFloat = 1.0 + 0.05 * sin(time * 1.6 + Double(i) * 0.9)
            drawCastPortrait(context: &context, center: pos, role: role,
                             appear: 1.0, pulse: pulse)

            let order = txOrders[i]
            let pillSpacing: CGFloat = 56
            let totalWidth: CGFloat = pillSpacing * CGFloat(order.count - 1)
            let pillY: CGFloat = pos.y < cy ? pos.y - 90 : pos.y + 90
            let revealCount = min(order.count, max(1, Int(time / 0.7)))

            for (j, tx) in order.enumerated() {
                if j >= revealCount { continue }
                let pillX = pos.x - totalWidth / 2 + pillSpacing * CGFloat(j)
                let pillCenter = CGPoint(x: pillX, y: pillY)
                let txColor: Color = txColors[tx] ?? .white
                let pillRect = CGRect(x: pillCenter.x - 24, y: pillCenter.y - 11,
                                      width: 48, height: 22)
                context.fill(
                    RoundedRectangle(cornerRadius: 11).path(in: pillRect),
                    with: .color(txColor.opacity(0.18))
                )
                context.stroke(
                    RoundedRectangle(cornerRadius: 11).path(in: pillRect),
                    with: .color(txColor.opacity(0.55)),
                    lineWidth: 1
                )
                context.draw(
                    Text(tx)
                        .font(.system(size: settings.scaled(12), weight: .bold, design: .monospaced))
                        .foregroundColor(txColor.opacity(0.95)),
                    at: pillCenter
                )

                if j < order.count - 1 && j + 1 < revealCount {
                    let arrowStart = CGPoint(x: pillX + 24, y: pillY)
                    let arrowEnd   = CGPoint(x: pillX + pillSpacing - 24, y: pillY)
                    var arrowPath = Path()
                    arrowPath.move(to: arrowStart)
                    arrowPath.addLine(to: arrowEnd)
                    context.stroke(arrowPath, with: .color(.white.opacity(0.35)), lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Scene 2: the question
    //
    // Reuse the conflicting-logs backdrop dimmed to ~40% and overlay the
    // framing question. This gives Scene 2 visual continuity with Scene 1
    // (no hard cut) while elevating the question itself.

    private func renderTheQuestion(
        context: inout GraphicsContext, size: CGSize, time: Double, sim: SimulationData
    ) {
        renderConflictingLogs(context: &context, size: size, time: time)

        let dimAlpha = min(0.55, time * 0.3)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(.black.opacity(dimAlpha))
        )

        let qAlpha = min(1.0, max(0, (time - 1.0) * 0.4))
        context.draw(
            Text("HOW DO WE ALL AGREE?")
                .font(.system(size: settings.scaled(36), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(qAlpha * 0.85)),
            at: CGPoint(x: size.width / 2, y: size.height / 2)
        )

        let subAlpha = min(1.0, max(0, (time - 2.5) * 0.4))
        context.draw(
            Text("NO BOSS · NO CLOCK · ONE OF US (DAVE) MIGHT BE LYING")
                .font(.system(size: settings.scaled(12), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(subAlpha * 0.55)),
            at: CGPoint(x: size.width / 2, y: size.height / 2 + 44)
        )
    }
}
