import SwiftUI

/// Ch07: "Total Order" — Kahn's topological sort, animated from DAG positions to ordered sequence.
struct Ch07_Order: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    // Post-convergence step (leader-decided round produces ordered prefix at step 31).
    private let dataStep = 33

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

        // Separate: ordered vertices and unordered
        let ordered = vertices.filter { $0.totalPosition != nil }
            .sorted { ($0.totalPosition ?? 0) < ($1.totalPosition ?? 0) }
        let unordered = vertices.filter { $0.totalPosition == nil }

        // DAG layout for starting positions
        let layout = DAGLayout.compute(vertices: vertices, edges: edges, nodes: sim.nodes,
                                        canvasSize: size, margin: 60)

        // Sort progress animation
        let sortProgress: Double = switch sceneIndex {
        case 0: min(1.0, time * 0.08)        // slow reveal
        case 1: min(1.0, time * 0.15)        // faster
        case 2: 1.0                            // fully sorted
        default: 0.0
        }

        // Draw edges (fade as sort progresses)
        let edgeAlpha = max(0.03, 0.12 * (1 - sortProgress * 0.7))
        layout.drawEdges(in: &context, edges: edges, alpha: edgeAlpha)

        // Compute ordered target positions (horizontal strip)
        let stripY = size.height * 0.5
        let stripMargin: CGFloat = 40
        let stripSpacing = (size.width - stripMargin * 2) / CGFloat(max(ordered.count, 1))

        // Draw ordered vertices: interpolate from DAG position to strip position
        for (i, vertex) in ordered.enumerated() {
            let dagPos = layout.positions[vertex.digestHex] ?? CGPoint(x: size.width / 2, y: size.height / 2)
            let targetX = stripMargin + CGFloat(i) * stripSpacing + stripSpacing / 2
            let targetY = stripY

            let vertexProgress = min(1.0, max(0, sortProgress * Double(ordered.count) - Double(i) * 0.7) / Double(ordered.count) * 3)
            let x = dagPos.x + (targetX - dagPos.x) * vertexProgress
            let y = dagPos.y + (targetY - dagPos.y) * vertexProgress

            let pos = CGPoint(x: x, y: y)
            let colorIdx = dm.colorIndex(for: vertex.processIdHex)
            let color = DataManager.palette[min(colorIdx, DataManager.palette.count - 1)]

            let radius: CGFloat = 5 + CGFloat(min(vertex.weight, 8)) * 0.8
            let rect = CGRect(x: pos.x - radius, y: pos.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(0.85)))

            // Position number when settled
            if vertexProgress > 0.8 {
                context.draw(
                    Text("\(i + 1)")
                        .font(.system(size: settings.scaled(max(6, radius * 0.7)), weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8)),
                    at: CGPoint(x: pos.x, y: pos.y + radius + 8)
                )
            }

            // Hash label when sorted
            if vertexProgress > 0.9 && stripSpacing > 20 {
                context.draw(
                    Text(String(vertex.digestHex.prefix(4)))
                        .font(.system(size: settings.scaled(6), weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3)),
                    at: CGPoint(x: pos.x, y: pos.y + radius + 18)
                )
            }
        }

        // Draw unordered vertices (stay in DAG position, dimmed)
        for vertex in unordered {
            guard let pos = layout.positions[vertex.digestHex] else { continue }
            let radius: CGFloat = 4
            let rect = CGRect(x: pos.x - radius, y: pos.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Circle().path(in: rect), with: .color(.white.opacity(0.15)))
        }

        // Arrow showing sort direction
        if sortProgress > 0.1 {
            var arrow = Path()
            arrow.move(to: CGPoint(x: stripMargin, y: stripY + 30))
            arrow.addLine(to: CGPoint(x: size.width - stripMargin, y: stripY + 30))
            context.stroke(arrow, with: .color(.white.opacity(0.15)), lineWidth: 1)

            context.draw(
                Text("→ TOTAL ORDER")
                    .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2)),
                at: CGPoint(x: size.width - stripMargin - 50, y: stripY + 30)
            )
        }

        let subtitle: String = switch sceneIndex {
        case 0: "KAHN'S TOPOLOGICAL SORT + POW WEIGHT TIE-BREAKING"
        case 1: "VERTICES SLIDE INTO ORDERED POSITIONS"
        default: "ALL NODES PRODUCE IDENTICAL ORDER — CONVERGENCE"
        }

        context.draw(
            Text(subtitle)
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.4)),
            at: CGPoint(x: size.width / 2, y: size.height - 30)
        )

        context.draw(
            Text("\(ordered.count) ORDERED / \(vertices.count) TOTAL")
                .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.2)),
            at: CGPoint(x: size.width / 2, y: 14)
        )
    }
}
