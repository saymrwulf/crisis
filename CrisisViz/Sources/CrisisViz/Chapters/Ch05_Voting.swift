import SwiftUI

/// Ch05: "Virtual Voting" — votes inferred from graph structure, no vote messages.
struct Ch05_Voting: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager

    private let dataStep = 5

    var body: some View {
        Canvas { context, size in
            render(context: &context, size: size, time: localTime)
        }
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard let sim = dm.sim,
              let snap = dm.honestData(step: dataStep) else { return }

        let vertices = snap.vertices
        let edges = snap.edges

        let layout = DAGLayout.compute(vertices: vertices, edges: edges, nodes: sim.nodes,
                                        canvasSize: size, margin: 60)
        let minRound = vertices.map { $0.round }.min() ?? 0
        layout.drawNodeLanes(in: &context, nodes: sim.nodes, canvasSize: size, dm: dm)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: minRound, alpha: 0.3)
        layout.drawEdges(in: &context, edges: edges, alpha: 0.3)

        // Find a candidate (round 1 isLast) and a deciding vertex (round 3+)
        let candidates = vertices.filter { $0.isLast && $0.round == 1 }
        let deciders = vertices.filter { $0.round >= 3 }

        // Build reachability for SVP trace
        var childMap: [String: [String]] = [:]  // parent -> [children]
        for e in edges {
            childMap[e.to, default: []].append(e.from)
        }

        // Trace path from a candidate to a decider via BFS
        var svpPath: [String] = []
        if let candidate = candidates.first, let decider = deciders.first {
            svpPath = bfsPath(from: candidate.digestHex, to: decider.digestHex, childMap: childMap)
        }
        let svpSet = Set(svpPath)

        switch sceneIndex {
        case 0:
            // No vote messages — just graph
            layout.drawVertices(in: &context, vertices: vertices, nodes: sim.nodes, dm: dm,
                              showLabels: true, animationTime: time)

            let alpha = 0.4 + 0.2 * sin(time * 1.5)
            context.draw(
                Text("NO VOTE MESSAGES — VOTES INFERRED FROM GRAPH PATHS")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.green.opacity(alpha)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )

        case 1:
            // SVP trace highlighted
            layout.drawVertices(in: &context, vertices: vertices, nodes: sim.nodes, dm: dm,
                              showLabels: true, highlightSet: svpSet)

            // Draw SVP path edges in green
            for i in 0..<(svpPath.count - 1) {
                if let from = layout.positions[svpPath[i]],
                   let to = layout.positions[svpPath[i + 1]] {
                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)

                    let progress = min(1.0, max(0, time * 0.3 - Double(i) * 0.1))
                    context.stroke(path, with: .color(.green.opacity(0.7 * progress)), lineWidth: 2.5)
                }
            }

            // Label start and end
            if let cPos = layout.positions[svpPath.first ?? ""] {
                context.draw(
                    Text("CANDIDATE")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(.green),
                    at: CGPoint(x: cPos.x, y: cPos.y - 18)
                )
            }
            if let dPos = layout.positions[svpPath.last ?? ""] {
                context.draw(
                    Text("DECIDER")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(.green),
                    at: CGPoint(x: dPos.x, y: dPos.y - 18)
                )
            }

            context.draw(
                Text("SVP: STRONGLY-SEEING PATH — \(svpPath.count) VERTICES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.5)),
                at: CGPoint(x: size.width / 2, y: size.height - 30)
            )

        case 2:
            // Deterministic outcome
            layout.drawVertices(in: &context, vertices: vertices, nodes: sim.nodes, dm: dm,
                              showLabels: true, highlightSet: svpSet)

            // Draw all SVP edges
            for i in 0..<(svpPath.count - 1) {
                if let from = layout.positions[svpPath[i]],
                   let to = layout.positions[svpPath[i + 1]] {
                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)
                    context.stroke(path, with: .color(.green.opacity(0.5)), lineWidth: 2)
                }
            }

            context.draw(
                Text("SAME GRAPH → SAME PATHS → SAME VOTES — DETERMINISTIC")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.green.opacity(0.4 + 0.2 * sin(time * 1.5))),
                at: CGPoint(x: size.width / 2, y: size.height - 30)
            )

        default:
            layout.drawVertices(in: &context, vertices: vertices, nodes: sim.nodes, dm: dm, showLabels: true)
        }

        context.draw(
            Text("\(vertices.count) VERTICES · STEP \(dataStep)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.2)),
            at: CGPoint(x: size.width / 2, y: 14)
        )
    }

    private func bfsPath(from start: String, to end: String, childMap: [String: [String]]) -> [String] {
        var queue: [(String, [String])] = [(start, [start])]
        var visited = Set<String>()
        visited.insert(start)

        while !queue.isEmpty {
            let (current, path) = queue.removeFirst()
            if current == end { return path }
            for child in childMap[current] ?? [] {
                if !visited.contains(child) {
                    visited.insert(child)
                    queue.append((child, path + [child]))
                }
            }
            if path.count > 20 { break }
        }

        // Fallback: return start + some intermediate + end
        return [start, end]
    }
}
