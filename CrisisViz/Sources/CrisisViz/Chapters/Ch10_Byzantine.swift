import SwiftUI

/// Ch10: "Byzantine Resilience" — attacker highlighted, why attacks fail.
struct Ch10_Byzantine: View {
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
        guard let sim = dm.sim,
              let _ = dm.honestData(step: 7) else { return }

        let cx = size.width / 2
        let cy = size.height * 0.4
        let radius: CGFloat = min(size.width, size.height) * 0.25

        let nodes = sim.nodes

        // Draw network edges
        var nodePositions: [CGPoint] = []
        for i in 0..<nodes.count {
            let angle = Double(i) * (2.0 * .pi / Double(nodes.count)) - .pi / 2.0
            let pos = CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
            nodePositions.append(pos)
        }

        for i in 0..<nodes.count {
            for j in (i+1)..<nodes.count {
                var path = Path()
                path.move(to: nodePositions[i])
                path.addLine(to: nodePositions[j])
                context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            }
        }

        // Draw nodes
        for (i, node) in nodes.enumerated() {
            let pos = nodePositions[i]
            let colorIdx = min(i, DataManager.palette.count - 1)
            let color = node.isByzantine ? Color.red : DataManager.palette[colorIdx]
            let isByz = node.isByzantine

            let pulse = isByz ? 1.0 + 0.12 * sin(time * 4) : 1.0
            let nodeR: CGFloat = (isByz ? 24 : 18) * pulse

            // Attack glow for byzantine
            if isByz && sceneIndex == 0 {
                for wave in 0..<3 {
                    let phase = (time * 0.8 + Double(wave) * 0.5).truncatingRemainder(dividingBy: 2.0)
                    let glowR = nodeR + 30 * phase
                    let alpha = max(0, 0.2 - 0.1 * phase)
                    let glowRect = CGRect(x: pos.x - glowR, y: pos.y - glowR,
                                           width: glowR * 2, height: glowR * 2)
                    context.stroke(Circle().path(in: glowRect),
                                  with: .color(.red.opacity(alpha)), lineWidth: 1.5)
                }
            }

            let rect = CGRect(x: pos.x - nodeR, y: pos.y - nodeR,
                               width: nodeR * 2, height: nodeR * 2)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(0.8)))

            if isByz {
                context.stroke(Circle().path(in: rect.insetBy(dx: -3, dy: -3)),
                              with: .color(.red.opacity(0.7)), lineWidth: 2.5)
            }

            let label = isByz ? "BYZ" : String(node.name.suffix(1))
            context.draw(
                Text(label)
                    .font(.system(size: isByz ? 10 : 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white),
                at: pos
            )
        }

        // Scene-specific
        switch sceneIndex {
        case 0:
            // Attack scenarios
            let attacks = [
                "• Send conflicting messages",
                "• Withhold data from peers",
                "• Try to manipulate voting",
                "• Attempt to rewrite history",
            ]
            let attackAlpha = min(1.0, time * 0.2)
            for (i, attack) in attacks.enumerated() {
                let y = size.height * 0.7 + CGFloat(i) * 22
                context.draw(
                    Text(attack)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.red.opacity(0.5 * attackAlpha)),
                    at: CGPoint(x: cx, y: y)
                )
            }

            context.draw(
                Text("THE ATTACKER — 1 BYZANTINE NODE IN A NETWORK OF \(nodes.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.red.opacity(0.5)),
                at: CGPoint(x: cx, y: 30)
            )

        case 1:
            // Why attacks fail — shield + reasons
            let shieldAppear = min(1.0, time * 0.15)

            // Shield circle with rotating segments
            let shieldR = radius + 50
            let shieldRect = CGRect(x: cx - shieldR, y: cy - shieldR,
                                     width: shieldR * 2, height: shieldR * 2)
            context.stroke(Circle().path(in: shieldRect),
                          with: .color(.green.opacity(0.35 * shieldAppear)), lineWidth: 3)

            // Rotating shield arcs
            for arc in 0..<6 {
                let arcAngle = Double(arc) * (.pi / 3) + time * 0.3
                let arcLen: Double = .pi / 4
                var arcPath = Path()
                arcPath.addArc(center: CGPoint(x: cx, y: cy),
                              radius: shieldR + 6,
                              startAngle: .radians(arcAngle),
                              endAngle: .radians(arcAngle + arcLen),
                              clockwise: false)
                context.stroke(arcPath, with: .color(.green.opacity(0.2 * shieldAppear)), lineWidth: 2)
            }

            // Threshold indicator — positioned just below the shield
            let threshold = nodes.count / 3
            let byzCount = nodes.filter { $0.isByzantine }.count
            let thresholdY = cy + shieldR + 24

            context.draw(
                Text("BYZANTINE: \(byzCount)/\(nodes.count) < \(threshold + 1)/\(nodes.count) THRESHOLD")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(.green.opacity(0.7 * shieldAppear)),
                at: CGPoint(x: cx, y: thresholdY)
            )

            // Progress bar showing Byzantine fraction
            let barW: CGFloat = 300
            let barH: CGFloat = 10
            let barX = cx - barW / 2
            let barY = thresholdY + 16
            let bgRect = CGRect(x: barX, y: barY, width: barW, height: barH)
            context.fill(RoundedRectangle(cornerRadius: 4).path(in: bgRect),
                        with: .color(.white.opacity(0.06 * shieldAppear)))
            let byzFraction = Double(byzCount) / Double(nodes.count)
            let threshFraction = 1.0 / 3.0
            let fillRect = CGRect(x: barX, y: barY, width: barW * byzFraction, height: barH)
            context.fill(RoundedRectangle(cornerRadius: 4).path(in: fillRect),
                        with: .color(.red.opacity(0.5 * shieldAppear)))
            // Threshold marker
            let threshX = barX + barW * threshFraction
            var threshLine = Path()
            threshLine.move(to: CGPoint(x: threshX, y: barY - 3))
            threshLine.addLine(to: CGPoint(x: threshX, y: barY + barH + 3))
            context.stroke(threshLine, with: .color(.green.opacity(0.7 * shieldAppear)), lineWidth: 2)
            context.draw(
                Text("1/3")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.5 * shieldAppear)),
                at: CGPoint(x: threshX, y: barY + barH + 12)
            )

            // Defense checklist — positioned below the bar with adequate spacing
            let defenseStartY = barY + barH + 30
            let defenses = [
                "✓ < 1/3 Byzantine weight — protocol tolerates",
                "✓ SHA-256 hashes cannot be forged",
                "✓ PoW outcomes are unpredictable",
                "✓ Same graph → same deterministic result",
            ]
            for (i, defense) in defenses.enumerated() {
                let y = defenseStartY + CGFloat(i) * 24
                let itemAppear = min(1.0, max(0, time * 0.2 - Double(i) * 0.15))
                context.draw(
                    Text(defense)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.green.opacity(0.6 * itemAppear)),
                    at: CGPoint(x: cx, y: y)
                )
            }

            context.draw(
                Text("WHY ATTACKS FAIL")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(.green.opacity(0.5 * shieldAppear)),
                at: CGPoint(x: cx, y: 30)
            )

        default: break
        }
    }
}
