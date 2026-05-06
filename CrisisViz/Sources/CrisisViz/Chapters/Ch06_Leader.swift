import SwiftUI

/// Ch06: "Leader Election" — candidates ranked by PoW weight, highest wins.
struct Ch06_Leader: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    // Convergence happens at step 40 in the regenerated 80-step simulation.
    // We pick a step shortly after so the elected leader is recorded and
    // the candidate set is rich enough to make weight comparisons meaningful.
    private let dataStep = 45

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

        // Show the DAG in the top half
        let dagSize = CGSize(width: size.width, height: size.height * 0.55)
        let layout = DAGLayout.compute(vertices: vertices, edges: edges, nodes: dm.castOrderedNodes(),
                                        canvasSize: dagSize, margin: 50)
        let minRound = vertices.map { $0.round }.min() ?? 0
        layout.drawRoundSeparators(in: &context, canvasSize: dagSize, minRound: minRound, alpha: 0.2, textScale: settings.textScale)
        layout.drawEdges(in: &context, edges: edges, alpha: 0.3)

        // Find candidates: isLast vertices in a specific round (e.g., round 3)
        let targetRound = min(3, snap.maxRound)
        let candidates = vertices.filter { $0.isLast && $0.round == targetRound }
            .sorted { $0.weight > $1.weight }

        let candidateSet = Set(candidates.map { $0.digestHex })
        let winner = candidates.first

        layout.drawVertices(in: &context, vertices: vertices, nodes: dm.castOrderedNodes(), dm: dm,
                           showLabels: true, showWeight: true, highlightSet: candidateSet, textScale: settings.textScale)

        // Winner crown
        if let winner, let pos = layout.positions[winner.digestHex] {
            let crown = 0.6 + 0.4 * sin(time * 3)
            context.draw(
                Text("★ LEADER")
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(.yellow.opacity(crown)),
                at: CGPoint(x: pos.x, y: pos.y - 22)
            )
        }

        // Bottom half: candidate ranking bar chart
        let chartY = size.height * 0.6
        let chartH = size.height * 0.3
        let maxWeight = Double(candidates.map { $0.weight }.max() ?? 1)
        let barSpacing = min(100.0, (size.width - 100) / CGFloat(max(candidates.count, 1)))
        let chartStartX = (size.width - barSpacing * CGFloat(candidates.count)) / 2

        for (i, candidate) in candidates.enumerated() {
            let x = chartStartX + CGFloat(i) * barSpacing + barSpacing * 0.15
            let barW = barSpacing * 0.7
            let barH = chartH * (Double(candidate.weight) / maxWeight)
            let barRect = CGRect(x: x, y: chartY + chartH - barH, width: barW, height: barH)

            let isWinner = candidate.digestHex == winner?.digestHex
            let color = dm.castColor(for: candidate.processIdHex)

            context.fill(RoundedRectangle(cornerRadius: 4).path(in: barRect),
                        with: .color(color.opacity(isWinner ? 0.9 : 0.5)))

            if isWinner {
                context.stroke(RoundedRectangle(cornerRadius: 4).path(in: barRect.insetBy(dx: -2, dy: -2)),
                              with: .color(.yellow.opacity(0.7)), lineWidth: 2)
            }

            // Labels
            context.draw(
                Text("w=\(candidate.weight)")
                    .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7)),
                at: CGPoint(x: x + barW / 2, y: chartY + chartH + 14)
            )
            context.draw(
                Text(String(candidate.digestHex.prefix(6)))
                    .font(.system(size: settings.scaled(10), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4)),
                at: CGPoint(x: x + barW / 2, y: chartY + chartH + 26)
            )
        }

        let subtitle: String = sceneIndex == 0
            ? "ROUND \(targetRound) CANDIDATES — RANKED BY POW WEIGHT"
            : "HIGHEST WEIGHT WINS — UNPREDICTABLE HASH LOTTERY"
        context.draw(
            Text(subtitle)
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.4)),
            at: CGPoint(x: size.width / 2, y: chartY - 14)
        )
    }
}
