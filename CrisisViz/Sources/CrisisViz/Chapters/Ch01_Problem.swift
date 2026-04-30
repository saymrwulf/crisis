import SwiftUI

/// Ch01: "The Problem" — three scenes setting up why distributed consensus is hard.
///
/// Scene 0: literally three nodes, three conflicting transaction orders. The narration
///   says "Three Nodes, Three Truths" — the visual now matches.
/// Scene 1: pull back to reveal the full 9-node network and the question marks of disagreement.
/// Scene 2: the question — "How do we agree?"
struct Ch01_Problem: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager

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
            renderThreeProtagonists(context: &context, size: size, time: time)
        case 1:
            renderFullNetwork(context: &context, size: size, time: time, sim: sim)
        case 2:
            renderTheQuestion(context: &context, size: size, time: time, sim: sim)
        default:
            break
        }
    }

    // MARK: - Scene 0: three nodes, three truths

    private func renderThreeProtagonists(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2

        // Three protagonists: triangle layout, generously spaced
        let triangleRadius: CGFloat = min(size.width, size.height) * 0.28
        var positions: [CGPoint] = []
        for i in 0..<3 {
            let angle: Double = Double(i) * (2.0 * .pi / 3.0) - .pi / 2.0
            let x: CGFloat = cx + triangleRadius * cos(angle)
            let y: CGFloat = cy + triangleRadius * sin(angle)
            positions.append(CGPoint(x: x, y: y))
        }

        // Conflicting transaction orders — each node observed a different sequence
        let txOrders: [[String]] = [
            ["Tx₁", "Tx₂", "Tx₃"],
            ["Tx₂", "Tx₃", "Tx₁"],
            ["Tx₃", "Tx₁", "Tx₂"],
        ]

        // Soft connecting triangle (suggests a network without prescribing topology)
        var triangle = Path()
        triangle.move(to: positions[0])
        triangle.addLine(to: positions[1])
        triangle.addLine(to: positions[2])
        triangle.closeSubpath()
        context.stroke(triangle, with: .color(.white.opacity(0.08)), lineWidth: 0.6)

        // Animated message particles drifting BETWEEN nodes (out-of-order arrival)
        let particleCount = 18
        for p in 0..<particleCount {
            let seed = Double(p * 7919)
            let fromIdx = Int(seed.truncatingRemainder(dividingBy: 3))
            let toIdx = (fromIdx + 1 + Int(seed * 0.3) % 2) % 3
            let phase = (time * 0.18 + seed * 0.071).truncatingRemainder(dividingBy: 1.0)
            let from = positions[fromIdx]
            let to = positions[toIdx]
            let px = from.x + (to.x - from.x) * phase
            let py = from.y + (to.y - from.y) * phase

            let txIdx = Int(seed * 0.13) % 3
            let txColor: Color = [.cyan, .yellow, .pink][txIdx]
            let r: CGFloat = 3
            let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect),
                        with: .color(txColor.opacity(0.5 + 0.4 * (1 - phase))))
        }

        // Draw the three protagonists
        let palette: [Color] = [DataManager.palette[0], DataManager.palette[1], DataManager.palette[2]]
        for i in 0..<3 {
            let pos = positions[i]
            let color = palette[i]
            let pulse: CGFloat = 1.0 + 0.05 * sin(time * 1.6 + Double(i) * 0.9)
            let nodeRadius: CGFloat = 36 * pulse

            // Glow
            let glowR = nodeRadius * 1.9
            let glowRect = CGRect(x: pos.x - glowR, y: pos.y - glowR, width: glowR * 2, height: glowR * 2)
            context.fill(Circle().path(in: glowRect), with: .color(color.opacity(0.10)))

            // Body
            let bodyRect = CGRect(x: pos.x - nodeRadius, y: pos.y - nodeRadius,
                                   width: nodeRadius * 2, height: nodeRadius * 2)
            context.fill(Circle().path(in: bodyRect), with: .color(color.opacity(0.85)))
            context.stroke(Circle().path(in: bodyRect), with: .color(color.opacity(0.6)), lineWidth: 1.5)

            // Node label inside circle
            context.draw(
                Text("Node \(i + 1)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white),
                at: pos
            )
        }

        // Draw each node's observed transaction order as a row of pills above/below the node
        for i in 0..<3 {
            let pos = positions[i]
            let order = txOrders[i]
            let pillSpacing: CGFloat = 56
            let totalWidth: CGFloat = pillSpacing * CGFloat(order.count - 1)

            // Decide vertical placement: top node above, bottom-left/bottom-right below
            let pillY: CGFloat = pos.y < size.height / 2 ? pos.y - 75 : pos.y + 75

            // Reveal one tx at a time across the first 2.5s
            let revealCount = min(order.count, max(1, Int(time / 0.7)))

            for (j, tx) in order.enumerated() {
                let pillX = pos.x - totalWidth / 2 + pillSpacing * CGFloat(j)
                let pillCenter = CGPoint(x: pillX, y: pillY)
                let alpha: Double = j < revealCount ? 1.0 : 0.0
                if alpha == 0 { continue }

                let pillRect = CGRect(x: pillCenter.x - 22, y: pillCenter.y - 11, width: 44, height: 22)
                let txColor: Color = ["Tx₁": Color.cyan, "Tx₂": Color.yellow, "Tx₃": Color.pink][tx] ?? .white
                context.fill(RoundedRectangle(cornerRadius: 11).path(in: pillRect),
                            with: .color(txColor.opacity(0.18 * alpha)))
                context.stroke(RoundedRectangle(cornerRadius: 11).path(in: pillRect),
                              with: .color(txColor.opacity(0.55 * alpha)), lineWidth: 1)
                context.draw(
                    Text(tx)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(txColor.opacity(0.95 * alpha)),
                    at: pillCenter
                )

                // Arrow between pills
                if j < order.count - 1 && j + 1 < revealCount {
                    let arrowStart = CGPoint(x: pillX + 22, y: pillY)
                    let arrowEnd = CGPoint(x: pillX + pillSpacing - 22, y: pillY)
                    var arrowPath = Path()
                    arrowPath.move(to: arrowStart)
                    arrowPath.addLine(to: arrowEnd)
                    context.stroke(arrowPath,
                                  with: .color(.white.opacity(0.35 * alpha)), lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Scene 1: full network, disagreement flashes

    private func renderFullNetwork(context: inout GraphicsContext, size: CGSize, time: Double, sim: SimulationData) {
        let cx = size.width / 2
        let cy = size.height / 2

        let nodes = sim.nodes
        let nodeCount = nodes.count
        let radius: CGFloat = min(size.width, size.height) * 0.30

        var nodePositions: [CGPoint] = []
        for i in 0..<nodeCount {
            let angle = Double(i) * (2.0 * .pi / Double(nodeCount)) - .pi / 2.0
            nodePositions.append(CGPoint(x: cx + radius * cos(angle),
                                         y: cy + radius * sin(angle)))
        }

        // Mesh
        for i in 0..<nodeCount {
            for j in (i+1)..<nodeCount {
                var path = Path()
                path.move(to: nodePositions[i])
                path.addLine(to: nodePositions[j])
                context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 0.5)
            }
        }

        // Drifting message particles in all directions
        let particleCount = 28
        for p in 0..<particleCount {
            let seed = Double(p * 7919)
            let fromIdx = Int(seed.truncatingRemainder(dividingBy: Double(nodeCount)))
            let toIdx = (fromIdx + 1 + Int(seed * 0.3) % (nodeCount - 1)) % nodeCount
            let phase = ((time * 0.32 + seed * 0.1).truncatingRemainder(dividingBy: 1.0))
            let from = nodePositions[fromIdx]
            let to = nodePositions[toIdx]
            let px = from.x + (to.x - from.x) * phase
            let py = from.y + (to.y - from.y) * phase

            let colorIdx = min(fromIdx, DataManager.palette.count - 1)
            let r: CGFloat = 2.5
            let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect),
                        with: .color(DataManager.palette[colorIdx].opacity(0.5)))
        }

        // Disagreement flashes between pairs
        for i in stride(from: 0, to: min(6, nodeCount), by: 2) {
            let j = i + 1
            let mid = CGPoint(
                x: (nodePositions[i].x + nodePositions[j].x) / 2,
                y: (nodePositions[i].y + nodePositions[j].y) / 2
            )
            let flash = 0.5 + 0.5 * sin(time * 2.5 + Double(i))
            context.draw(
                Text("?")
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundColor(.yellow.opacity(flash * 0.85)),
                at: mid
            )
        }

        // Nodes
        for (i, node) in nodes.enumerated() {
            let pos = nodePositions[i]
            let colorIdx = min(i, DataManager.palette.count - 1)
            let color = DataManager.palette[colorIdx]
            let pulse: CGFloat = 1.0 + 0.04 * sin(time * 2.0 + Double(i) * 0.8)
            let nodeRadius: CGFloat = (node.isByzantine ? 22 : 18) * pulse

            let glowRect = CGRect(x: pos.x - nodeRadius * 1.8, y: pos.y - nodeRadius * 1.8,
                                   width: nodeRadius * 3.6, height: nodeRadius * 3.6)
            context.fill(Circle().path(in: glowRect), with: .color(color.opacity(0.08)))

            let rect = CGRect(x: pos.x - nodeRadius, y: pos.y - nodeRadius,
                               width: nodeRadius * 2, height: nodeRadius * 2)
            context.fill(Circle().path(in: rect),
                        with: .color(color.opacity(node.isByzantine ? 0.9 : 0.8)))

            if node.isByzantine {
                context.stroke(Circle().path(in: rect.insetBy(dx: -2, dy: -2)),
                              with: .color(.red.opacity(0.6)), lineWidth: 2)
            }

            let label = node.isByzantine ? "BYZ" : String(node.name.suffix(1))
            context.draw(
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white),
                at: pos
            )
            context.draw(
                Text(node.processIdHex.prefix(4))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4)),
                at: CGPoint(x: pos.x, y: pos.y + nodeRadius + 10)
            )
        }
    }

    // MARK: - Scene 2: the question

    private func renderTheQuestion(context: inout GraphicsContext, size: CGSize, time: Double, sim: SimulationData) {
        // Reuse the full-network backdrop, but dim everything and pose the question.
        renderFullNetwork(context: &context, size: size, time: time, sim: sim)

        // Dim everything with a black overlay that fades in
        let dimAlpha = min(0.55, time * 0.3)
        context.fill(Path(CGRect(origin: .zero, size: size)),
                    with: .color(.black.opacity(dimAlpha)))

        // Question fades in
        let qAlpha = min(1.0, max(0, (time - 1.0) * 0.4))
        context.draw(
            Text("HOW DO WE AGREE?")
                .font(.system(size: 36, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(qAlpha * 0.85)),
            at: CGPoint(x: size.width / 2, y: size.height / 2)
        )

        let subAlpha = min(1.0, max(0, (time - 2.5) * 0.4))
        context.draw(
            Text("WITH NO CENTRAL CLOCK · NO TRUSTED THIRD PARTY · BYZANTINE PARTICIPANTS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(subAlpha * 0.55)),
            at: CGPoint(x: size.width / 2, y: size.height / 2 + 44)
        )
    }
}
