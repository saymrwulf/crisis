import SwiftUI

/// Ch04: "Rounds from Weight" — PoW weight accumulation triggers round boundaries.
struct Ch04_Rounds: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    private var dataStep: Int { sceneIndex + 2 }  // steps 2, 3, 4

    var body: some View {
        Canvas { context, size in
            render(context: &context, size: size, time: localTime)
        }
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard dm.sim != nil,
              let snap = dm.honestData(step: dataStep) else { return }

        let vertices = snap.vertices
        let edges = snap.edges

        // Draw the DAG with round separators prominent
        let layout = DAGLayout.compute(vertices: vertices, edges: edges, nodes: dm.castOrderedNodes(),
                                        canvasSize: size, margin: 60)
        let minRound = vertices.map { $0.round }.min() ?? 0
        layout.drawNodeLanes(in: &context, nodes: dm.castOrderedNodes(), canvasSize: size, dm: dm, textScale: settings.textScale)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: minRound, alpha: 0.4, textScale: settings.textScale)
        layout.drawEdges(in: &context, edges: edges, alpha: 0.3)

        // Highlight isLast vertices (round boundary markers) with bright rings
        let roundMarkers = Set(vertices.filter { $0.isLast }.map { $0.digestHex })
        layout.drawVertices(in: &context, vertices: vertices, nodes: dm.castOrderedNodes(), dm: dm,
                           showLabels: true, showWeight: true, highlightSet: roundMarkers, textScale: settings.textScale)

        // Weight bars per round at the bottom
        let rounds = Dictionary(grouping: vertices, by: { $0.round })
        let barY = size.height - 80.0
        let barHeight: CGFloat = 20
        let roundCount = rounds.keys.count
        let barSpacing = min(120.0, (size.width - 120) / CGFloat(max(roundCount, 1)))
        let startX = 60.0

        for (round, verts) in rounds.sorted(by: { $0.key < $1.key }) {
            let totalWeight = verts.reduce(0) { $0 + $1.weight }
            let x = startX + CGFloat(round - minRound) * barSpacing
            let barW = barSpacing * 0.7
            let maxWeight = 30.0  // scale factor

            // Background
            let bgRect = CGRect(x: x, y: barY, width: barW, height: barHeight)
            context.fill(RoundedRectangle(cornerRadius: 3).path(in: bgRect),
                        with: .color(.white.opacity(0.05)))

            // Fill proportional to weight
            let fillPct = min(1.0, Double(totalWeight) / maxWeight)
            let fillW = barW * fillPct
            let fillRect = CGRect(x: x, y: barY, width: fillW, height: barHeight)
            let allIsLast = verts.allSatisfy { $0.isLast }
            let fillColor: Color = allIsLast ? .yellow : .cyan
            context.fill(RoundedRectangle(cornerRadius: 3).path(in: fillRect),
                        with: .color(fillColor.opacity(0.5)))

            // Label
            context.draw(
                Text("R\(round): Σw=\(totalWeight)")
                    .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5)),
                at: CGPoint(x: x + barW / 2, y: barY + barHeight + 12)
            )
        }

        // isLast annotation
        context.draw(
            Text("○ = isLast (ROUND BOUNDARY) — WEIGHT TRIGGERS TRANSITION")
                .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.4)),
            at: CGPoint(x: size.width / 2, y: barY - 16)
        )

        context.draw(
            Text("\(snap.vertices.count) VERTICES · MAX ROUND \(snap.maxRound)")
                .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.2)),
            at: CGPoint(x: size.width / 2, y: 14)
        )
    }
}
