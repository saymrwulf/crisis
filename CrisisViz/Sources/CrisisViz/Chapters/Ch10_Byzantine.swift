import SwiftUI

/// Ch09 (file Ch10_Byzantine, user-facing chapter index 9): "Dave lies. Crisis catches him."
///
/// Two beats from the narration:
///
///   - Scene 0 ("Dave forks his message."): on the persistent lane base,
///     Dave's `isByzantineSource` vertices are highlighted with red rings,
///     multi-parent fork lines, and contrasting payloads. The viewer SEES
///     Dave producing two contradictory messages from the same lane.
///
///   - Scene 1 ("The protocol routes around him."): Aaron, Ben, Carl
///     converge on a total order DESPITE Dave's forks. Dave's vertices
///     are X'd out; the f<n/3 shield asserts the byzantine resilience
///     guarantee. The threshold bar appears below.
struct Ch10_Byzantine: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    private let dataStep = 60  // post-convergence

    var body: some View {
        Canvas { context, size in
            render(context: &context, size: size, time: localTime)
        }
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard let sim = dm.sim,
              let snap = dm.honestData(step: dataStep) else { return }

        let lanes = dm.castOrderedNodes()
        let layout = DAGLayout.compute(
            vertices: snap.vertices, edges: snap.edges, nodes: lanes,
            canvasSize: CGSize(width: size.width, height: size.height * 0.65),
            margin: 50
        )

        let minRound = snap.vertices.map { $0.round }.min() ?? 0
        layout.drawNodeLanes(in: &context, nodes: lanes,
                             canvasSize: CGSize(width: size.width, height: size.height * 0.65),
                             dm: dm, textScale: settings.textScale)
        layout.drawRoundSeparators(
            in: &context,
            canvasSize: CGSize(width: size.width, height: size.height * 0.65),
            minRound: minRound, alpha: 0.20, textScale: settings.textScale
        )

        // ─── Identify Dave and his byzantine vertices ────────────────────
        let davePid = dm.castByPid.first(where: { $0.value.id == Cast.dave.id })?.key
        let daveVertices = davePid.map { pid in
            snap.vertices.filter { $0.processIdHex == pid }
        } ?? []
        let forkedVertices = daveVertices.filter { $0.isByzantineSource }

        // Edges: dim everything; brighten edges that touch a forked vertex.
        let forkedSet = Set(forkedVertices.map(\.digestHex))
        for edge in snap.edges {
            guard let from = layout.positions[edge.from],
                  let to = layout.positions[edge.to] else { continue }
            let touchesFork = forkedSet.contains(edge.from) || forkedSet.contains(edge.to)
            let alpha = touchesFork ? 0.55 : 0.18
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path,
                          with: .color((touchesFork ? Color.red : Color.white).opacity(alpha)),
                          lineWidth: touchesFork ? 1.6 : 0.9)
        }

        // Vertices.
        for vertex in snap.vertices {
            guard let pos = layout.positions[vertex.digestHex] else { continue }
            let role = dm.castRole(for: vertex.processIdHex)
            let isForked = forkedSet.contains(vertex.digestHex)

            let r: CGFloat = 7 + CGFloat(min(vertex.weight, 8)) * 0.5
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            let baseColor = isForked ? Color.red : role.color
            let alpha: Double = sceneIndex == 1 && isForked ? 0.4 : 0.85
            context.fill(Circle().path(in: rect), with: .color(baseColor.opacity(alpha)))

            if isForked {
                // Pulsing red halo around forked vertices.
                let pulse = 0.5 + 0.5 * sin(time * 3 + Double(vertex.weight))
                let haloR = r * 1.9 * pulse
                let haloRect = CGRect(x: pos.x - haloR, y: pos.y - haloR,
                                       width: haloR * 2, height: haloR * 2)
                context.stroke(Circle().path(in: haloRect),
                              with: .color(.red.opacity(0.4 * pulse)), lineWidth: 1.5)

                // Scene 1: X out the forked vertex (banned).
                if sceneIndex == 1 {
                    let banAppear = min(1, time / 1.5)
                    let xLen: CGFloat = r * 1.3 * CGFloat(banAppear)
                    var x1 = Path()
                    x1.move(to: CGPoint(x: pos.x - xLen, y: pos.y - xLen))
                    x1.addLine(to: CGPoint(x: pos.x + xLen, y: pos.y + xLen))
                    var x2 = Path()
                    x2.move(to: CGPoint(x: pos.x + xLen, y: pos.y - xLen))
                    x2.addLine(to: CGPoint(x: pos.x - xLen, y: pos.y + xLen))
                    context.stroke(x1, with: .color(.red.opacity(0.95)), lineWidth: 2.5)
                    context.stroke(x2, with: .color(.red.opacity(0.95)), lineWidth: 2.5)
                }
            }
            if vertex.isLast && !isForked && sceneIndex == 1 {
                context.stroke(Circle().path(in: rect.insetBy(dx: -2, dy: -2)),
                              with: .color(.green.opacity(0.6)), lineWidth: 1.6)
            }
        }

        // ─── Scene-specific bottom panel ─────────────────────────────────
        switch sceneIndex {
        case 0:
            renderScene0Bottom(in: &context, size: size, time: time,
                               forkedCount: forkedVertices.count, daveTotal: daveVertices.count)
        case 1:
            renderScene1Bottom(in: &context, size: size, time: time, sim: sim,
                               forkedCount: forkedVertices.count)
        default: break
        }

        // Top header reads the same in both scenes — anchors the chapter.
        context.draw(
            Text("DAVE LIES — CRISIS CATCHES HIM")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.55))
                .kerning(2),
            at: CGPoint(x: size.width / 2, y: 28)
        )
    }

    // MARK: - Scene 0: forks revealed

    private func renderScene0Bottom(
        in context: inout GraphicsContext, size: CGSize, time: Double,
        forkedCount: Int, daveTotal: Int
    ) {
        let bandY = size.height * 0.7
        let appear = min(1.0, time * 0.4)

        context.draw(
            Text("DAVE'S FORKS — VIOLET LANE, RED RINGS")
                .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.7 * appear)),
            at: CGPoint(x: size.width / 2, y: bandY)
        )

        // Stats row
        let stats: [(String, String, Color)] = [
            ("DAVE TOTAL", "\(daveTotal) MSGS", Cast.violet),
            ("CONFLICTS",  "\(forkedCount)",     .red),
            ("STRATEGY",   "FORK SAME ID, DIFFERENT PARENTS", .orange)
        ]
        let pillW: CGFloat = 220
        let pillH: CGFloat = 46
        let totalW = pillW * CGFloat(stats.count) + 24 * CGFloat(stats.count - 1)
        let startX = (size.width - totalW) / 2
        for (i, stat) in stats.enumerated() {
            let appearI = max(0, min(1, time * 0.4 - Double(i) * 0.5))
            if appearI < 0.05 { continue }
            let x = startX + CGFloat(i) * (pillW + 24)
            let rect = CGRect(x: x, y: bandY + 26, width: pillW, height: pillH)
            context.fill(RoundedRectangle(cornerRadius: 8).path(in: rect),
                        with: .color(.black.opacity(0.55 * appearI)))
            context.stroke(RoundedRectangle(cornerRadius: 8).path(in: rect),
                          with: .color(stat.2.opacity(0.7 * appearI)),
                          lineWidth: 1.5)
            context.draw(
                Text(stat.0)
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(stat.2.opacity(0.95 * appearI)),
                at: CGPoint(x: rect.midX, y: rect.minY + 14)
            )
            context.draw(
                Text(stat.1)
                    .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95 * appearI)),
                at: CGPoint(x: rect.midX, y: rect.minY + 32)
            )
        }

        let hintAppear = max(0, min(1, time * 0.3 - 1.5))
        context.draw(
            Text("EACH FORKED VERTEX SHARES DAVE'S ID BUT POINTS AT DIFFERENT PARENTS — TRYING TO TRICK AARON & BEN INTO DISAGREEING")
                .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55 * hintAppear)),
            at: CGPoint(x: size.width / 2, y: size.height - 36)
        )
    }

    // MARK: - Scene 1: protocol routes around

    private func renderScene1Bottom(
        in context: inout GraphicsContext, size: CGSize, time: Double,
        sim: SimulationData, forkedCount: Int
    ) {
        let bandY = size.height * 0.7

        // Threshold bar.
        let n = sim.nodes.count
        let f = sim.nodes.filter { $0.isByzantine }.count
        let appear = min(1.0, time * 0.3)

        context.draw(
            Text("BYZANTINE RESILIENCE  —  f < n/3")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.7 * appear))
                .kerning(1.5),
            at: CGPoint(x: size.width / 2, y: bandY)
        )

        let barW: CGFloat = size.width * 0.55
        let barH: CGFloat = 14
        let barX = (size.width - barW) / 2
        let barY = bandY + 32

        // Track
        let bgRect = CGRect(x: barX, y: barY, width: barW, height: barH)
        context.fill(RoundedRectangle(cornerRadius: 7).path(in: bgRect),
                    with: .color(.white.opacity(0.06 * appear)))

        // Byzantine fill.
        let byzFrac = Double(f) / Double(n)
        let fillRect = CGRect(x: barX, y: barY, width: barW * byzFrac, height: barH)
        context.fill(RoundedRectangle(cornerRadius: 7).path(in: fillRect),
                    with: .color(.red.opacity(0.55 * appear)))

        // Threshold marker at 1/3.
        let threshX = barX + barW * (1.0 / 3.0)
        var threshLine = Path()
        threshLine.move(to: CGPoint(x: threshX, y: barY - 5))
        threshLine.addLine(to: CGPoint(x: threshX, y: barY + barH + 5))
        context.stroke(threshLine, with: .color(.green.opacity(0.85 * appear)), lineWidth: 2.5)
        context.draw(
            Text("1/3 THRESHOLD")
                .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.7 * appear)),
            at: CGPoint(x: threshX, y: barY + barH + 16)
        )

        context.draw(
            Text("\(f)/\(n) BYZANTINE  =  \(String(format: "%.1f", byzFrac * 100))%")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.85 * appear)),
            at: CGPoint(x: barX + barW / 2, y: barY - 14)
        )

        // Defense line.
        let defenseAppear = max(0, min(1, time * 0.3 - 1.5))
        context.draw(
            Text("✓ \(forkedCount) FORKS DETECTED  ·  ✓ DAVE'S VERTICES BANNED  ·  ✓ AARON·BEN·CARL CONVERGE")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.7 * defenseAppear)),
            at: CGPoint(x: size.width / 2, y: barY + barH + 44)
        )

        let footerAppear = max(0, min(1, time * 0.3 - 2.5))
        context.draw(
            Text("CRISIS GUARANTEES TOTAL ORDER WHENEVER FEWER THAN ONE-THIRD OF VALIDATORS LIE.")
                .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55 * footerAppear)),
            at: CGPoint(x: size.width / 2, y: size.height - 36)
        )
    }
}
