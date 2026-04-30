import SwiftUI

/// Ch03: "Network Partition" — 4 scenes showing partition, diverging realities, reconnection.
/// Uses real data: majority sees step 3 (33 vertices), isolated see ~17.
struct Ch03_Partition: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager

    // Partition config: honest-6 and honest-7 are isolated
    private let isolatedProcessIds = Set(["1058280f", "9e42015f"])
    private let majorityStep = 3
    private let fullStep = 5  // post-reconnection

    var body: some View {
        Canvas { context, size in
            render(context: &context, size: size, time: localTime)
        }
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard let sim = dm.sim,
              let snap = dm.honestData(step: majorityStep) else {
            context.draw(Text("Loading...").foregroundColor(.white),
                        at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        switch sceneIndex {
        case 0: renderPartitionBreak(context: &context, size: size, time: time, sim: sim)
        case 1: renderDivergingDAGs(context: &context, size: size, time: time, sim: sim, snap: snap)
        case 2: renderVotingDiverge(context: &context, size: size, time: time, sim: sim, snap: snap)
        case 3: renderReconnection(context: &context, size: size, time: time, sim: sim)
        default: break
        }
    }

    // Scene 0: Network connections breaking
    private func renderPartitionBreak(context: inout GraphicsContext, size: CGSize, time: Double, sim: SimulationData) {
        let cx = size.width / 2
        let cy = size.height / 2
        let radius: CGFloat = min(size.width, size.height) * 0.28
        let splitProgress = min(1.0, time * 0.25)

        // All nodes in a circle, but isolated ones drift right
        for (i, node) in sim.nodes.enumerated() {
            let baseAngle = Double(i) * (2.0 * .pi / Double(sim.nodes.count)) - .pi / 2.0
            var x = cx + radius * cos(baseAngle)
            var y = cy + radius * sin(baseAngle)

            let isIsolated = isolatedProcessIds.contains(node.processIdHex)
            if isIsolated {
                x += size.width * 0.2 * splitProgress
            } else {
                x -= size.width * 0.04 * splitProgress
            }

            let colorIdx = dm.colorIndex(for: node.processIdHex)
            let color = DataManager.palette[min(colorIdx, DataManager.palette.count - 1)]
            let nodeR: CGFloat = 16

            // Draw edges to other nodes (fading for cross-partition)
            for (j, other) in sim.nodes.enumerated() where j > i {
                let otherIsolated = isolatedProcessIds.contains(other.processIdHex)
                let crossPartition = isIsolated != otherIsolated

                let otherAngle = Double(j) * (2.0 * .pi / Double(sim.nodes.count)) - .pi / 2.0
                var ox = cx + radius * cos(otherAngle)
                var oy = cy + radius * sin(otherAngle)
                if otherIsolated {
                    ox += size.width * 0.2 * splitProgress
                } else {
                    ox -= size.width * 0.04 * splitProgress
                }

                let alpha = crossPartition ? max(0, 0.15 * (1 - splitProgress * 2)) : 0.1
                if alpha > 0.01 {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: ox, y: oy))
                    context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 0.5)
                }
            }

            // Node circle
            let rect = CGRect(x: x - nodeR, y: y - nodeR, width: nodeR * 2, height: nodeR * 2)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(0.8)))

            if isIsolated && splitProgress > 0.5 {
                context.stroke(Circle().path(in: rect.insetBy(dx: -3, dy: -3)),
                              with: .color(.red.opacity(0.6 * splitProgress)), lineWidth: 2)
            }

            context.draw(
                Text(node.name.suffix(1))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white),
                at: CGPoint(x: x, y: y)
            )
        }

        // Breaking connection effect
        if splitProgress > 0.3 {
            let breakAlpha = min(1.0, (splitProgress - 0.3) * 2)
            // Red X marks where connections break
            let midX = cx + size.width * 0.08
            for yOff in [-40.0, 0.0, 40.0] {
                context.draw(
                    Text("✕")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.red.opacity(breakAlpha * 0.7)),
                    at: CGPoint(x: midX, y: cy + yOff)
                )
            }
        }

        context.draw(
            Text("NETWORK PARTITION — 2 NODES ISOLATED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.4)),
            at: CGPoint(x: cx, y: size.height - 30)
        )
    }

    // Scene 1: Split-screen DAGs — majority vs isolated
    private func renderDivergingDAGs(context: inout GraphicsContext, size: CGSize, time: Double,
                                      sim: SimulationData, snap: NodeSnapshot) {
        let midX = size.width / 2
        let gap: CGFloat = 30

        // Partition line
        let dash: [CGFloat] = [6, 6]
        var line = Path()
        line.move(to: CGPoint(x: midX, y: 20))
        line.addLine(to: CGPoint(x: midX, y: size.height - 20))
        context.stroke(line, with: .color(.red.opacity(0.4)),
                      style: StrokeStyle(lineWidth: 2, dash: dash))

        // LEFT: Majority DAG (all vertices)
        let leftSize = CGSize(width: midX - gap, height: size.height)
        let majorityLayout = DAGLayout.compute(
            vertices: snap.vertices, edges: snap.edges, nodes: sim.nodes,
            canvasSize: leftSize, margin: 40
        )
        let minRound = snap.vertices.map { $0.round }.min() ?? 0
        majorityLayout.drawRoundSeparators(in: &context, canvasSize: leftSize, minRound: minRound, alpha: 0.1)
        majorityLayout.drawEdges(in: &context, edges: snap.edges, alpha: 0.3)
        majorityLayout.drawVertices(in: &context, vertices: snap.vertices, nodes: sim.nodes, dm: dm,
                                   showLabels: false, animationTime: time)

        context.draw(
            Text("MAJORITY: \(snap.vertices.count) VERTICES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.6)),
            at: CGPoint(x: midX * 0.5, y: 20)
        )

        // RIGHT: Isolated view — only vertices from isolated nodes + their genesis knowledge
        let isolatedVertices = snap.vertices.filter { v in
            isolatedProcessIds.contains(v.processIdHex) || v.round == 0
        }
        let isolatedDigests = Set(isolatedVertices.map { $0.digestHex })
        let isolatedEdges = snap.edges.filter { e in
            isolatedDigests.contains(e.from) && isolatedDigests.contains(e.to)
        }

        // Offset context for right side
        var rightContext = context
        rightContext.translateBy(x: midX + gap, y: 0)
        let rightSize = CGSize(width: midX - gap, height: size.height)
        let isolatedLayout = DAGLayout.compute(
            vertices: isolatedVertices, edges: isolatedEdges, nodes: sim.nodes,
            canvasSize: rightSize, margin: 40
        )
        isolatedLayout.drawEdges(in: &rightContext, edges: isolatedEdges, alpha: 0.3)
        isolatedLayout.drawVertices(in: &rightContext, vertices: isolatedVertices, nodes: sim.nodes, dm: dm,
                                   showLabels: false, animationTime: time)

        context.draw(
            Text("ISOLATED: \(isolatedVertices.count) VERTICES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.orange.opacity(0.6)),
            at: CGPoint(x: midX + midX * 0.5, y: 20)
        )

        context.draw(
            Text("SAME ALGORITHM — DIFFERENT GRAPH → DIFFERENT REALITY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3)),
            at: CGPoint(x: midX, y: size.height - 20)
        )
    }

    // Scene 2: Virtual voting diverges
    private func renderVotingDiverge(context: inout GraphicsContext, size: CGSize, time: Double,
                                      sim: SimulationData, snap: NodeSnapshot) {
        // Same as scene 1 but with "VOTE: X" overlays
        renderDivergingDAGs(context: &context, size: size, time: time, sim: sim, snap: snap)

        // Overlay voting results
        let flash = 0.5 + 0.5 * sin(time * 2)
        context.draw(
            Text("MAJORITY VOTES: LEADER = 0dd9...")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan.opacity(flash)),
            at: CGPoint(x: size.width * 0.25, y: size.height - 60)
        )
        context.draw(
            Text("ISOLATED VOTES: LEADER = ???")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.orange.opacity(flash)),
            at: CGPoint(x: size.width * 0.75, y: size.height - 60)
        )
    }

    // Scene 3: Reconnection — gossip floods the gap
    private func renderReconnection(context: inout GraphicsContext, size: CGSize, time: Double, sim: SimulationData) {
        guard let snap = dm.honestData(step: fullStep) else { return }

        // Show the full merged DAG
        let layout = DAGLayout.compute(
            vertices: snap.vertices, edges: snap.edges, nodes: sim.nodes,
            canvasSize: size, margin: 60
        )

        let minRound = snap.vertices.map { $0.round }.min() ?? 0
        layout.drawNodeLanes(in: &context, nodes: sim.nodes, canvasSize: size, dm: dm)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: minRound)
        layout.drawEdges(in: &context, edges: snap.edges, alpha: 0.3)
        layout.drawVertices(in: &context, vertices: snap.vertices, nodes: sim.nodes, dm: dm,
                           showLabels: true, animationTime: time)

        // Flood animation: particles flowing from left to right
        let floodProgress = min(1.0, time * 0.15)
        let floodCount = Int(30 * floodProgress)
        for p in 0..<floodCount {
            let seed = Double(p * 3571)
            let progress = ((time * 0.4 + seed * 0.05).truncatingRemainder(dividingBy: 1.0))
            let px = size.width * 0.3 + size.width * 0.5 * progress
            let py = 80 + (seed.truncatingRemainder(dividingBy: (size.height - 160)))
            let particleRect = CGRect(x: px - 2, y: py - 2, width: 4, height: 4)
            context.fill(Circle().path(in: particleRect),
                        with: .color(.green.opacity(0.3 * (1 - progress))))
        }

        context.draw(
            Text("RECONNECTED — GOSSIP FLOODS THE GAP — \(snap.vertices.count) VERTICES CONVERGED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.5)),
            at: CGPoint(x: size.width / 2, y: size.height - 30)
        )
    }
}
