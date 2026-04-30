import SwiftUI

/// Ch08: "Data Availability — The Problem" — 4 scenes: gossip≠storage, bootstrapping, sybil, separation.
struct Ch08_DA_Problem: View {
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
        switch sceneIndex {
        case 0: renderGossipNotStorage(context: &context, size: size, time: time)
        case 1: renderBootstrapping(context: &context, size: size, time: time)
        case 2: renderSybilAttack(context: &context, size: size, time: time)
        case 3: renderSeparation(context: &context, size: size, time: time)
        default: break
        }
    }

    // MARK: - Scene 0: Gossip ≠ Storage

    private func renderGossipNotStorage(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2
        let nodeCount = 8
        let radius: CGFloat = min(size.width, size.height) * 0.25

        // Draw nodes
        var positions: [CGPoint] = []
        for i in 0..<nodeCount {
            let angle = Double(i) * (2.0 * .pi / Double(nodeCount)) - .pi / 2.0
            let pos = CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
            positions.append(pos)

            let r: CGFloat = 18
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            let color = DataManager.palette[min(i, DataManager.palette.count - 1)]
            context.fill(Circle().path(in: rect), with: .color(color.opacity(0.7)))
        }

        // Animated outward pulses (push-based gossip)
        for i in 0..<nodeCount {
            let pos = positions[i]
            for wave in 0..<3 {
                let phase = (time * 0.6 + Double(i) * 0.3 + Double(wave) * 0.4).truncatingRemainder(dividingBy: 1.5)
                let pulseR = 18 + 80 * phase
                let alpha = max(0, 0.25 - 0.2 * phase)
                if alpha > 0.01 {
                    let pulseRect = CGRect(x: pos.x - pulseR, y: pos.y - pulseR,
                                            width: pulseR * 2, height: pulseR * 2)
                    let color = DataManager.palette[min(i, DataManager.palette.count - 1)]
                    context.stroke(Circle().path(in: pulseRect),
                                  with: .color(color.opacity(alpha)), lineWidth: 1)
                }
            }
        }

        // Gossip particles between nodes
        for p in 0..<30 {
            let seed = Double(p * 7919)
            let fromIdx = Int(seed) % nodeCount
            let toIdx = (fromIdx + 1 + Int(seed * 0.3) % (nodeCount - 1)) % nodeCount
            let progress = ((time * 0.5 + seed * 0.05).truncatingRemainder(dividingBy: 1.0))

            let from = positions[fromIdx]
            let to = positions[toIdx]
            let px = from.x + (to.x - from.x) * progress
            let py = from.y + (to.y - from.y) * progress
            let particleR: CGFloat = 2.5
            let particleRect = CGRect(x: px - particleR, y: py - particleR,
                                       width: particleR * 2, height: particleR * 2)
            let color = DataManager.palette[min(fromIdx, DataManager.palette.count - 1)]
            context.fill(Circle().path(in: particleRect), with: .color(color.opacity(0.4 * (1 - progress))))
        }

        // Labels
        context.draw(
            Text("PUSH-BASED GOSSIP")
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.3)),
            at: CGPoint(x: cx, y: 50)
        )

        // Bottom: NOT vs IS
        let boxW: CGFloat = 250
        let boxH: CGFloat = 50
        let leftBox = CGRect(x: cx - boxW - 20, y: size.height - 100, width: boxW, height: boxH)
        context.fill(RoundedRectangle(cornerRadius: 8).path(in: leftBox),
                    with: .color(.green.opacity(0.1)))
        context.stroke(RoundedRectangle(cornerRadius: 8).path(in: leftBox),
                      with: .color(.green.opacity(0.3)), lineWidth: 1)
        context.draw(
            Text("✓ FIREHOSE FOR THE PRESENT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.7)),
            at: CGPoint(x: leftBox.midX, y: leftBox.midY)
        )

        let rightBox = CGRect(x: cx + 20, y: size.height - 100, width: boxW, height: boxH)
        context.fill(RoundedRectangle(cornerRadius: 8).path(in: rightBox),
                    with: .color(.red.opacity(0.1)))
        context.stroke(RoundedRectangle(cornerRadius: 8).path(in: rightBox),
                      with: .color(.red.opacity(0.3)), lineWidth: 1)
        context.draw(
            Text("✕ NOT A DATABASE FOR THE PAST")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.7)),
            at: CGPoint(x: rightBox.midX, y: rightBox.midY)
        )
    }

    // MARK: - Scene 1: Bootstrapping Problem

    private func renderBootstrapping(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height * 0.48

        // Existing network (left cluster) — 8 real nodes
        let netRadius: CGFloat = min(size.width, size.height) * 0.18
        let netCenter = CGPoint(x: cx * 0.45, y: cy)
        var netPositions: [CGPoint] = []
        let nodeCount = 8
        let stress = min(1.0, time * 0.1)

        // Draw inter-node connections first
        for i in 0..<nodeCount {
            let angle = Double(i) * (2.0 * .pi / Double(nodeCount)) - .pi / 2
            let pos = CGPoint(x: netCenter.x + netRadius * cos(angle),
                               y: netCenter.y + netRadius * sin(angle))
            netPositions.append(pos)
        }
        for i in 0..<nodeCount {
            for j in (i+1)..<nodeCount {
                if (i + j) % 3 != 0 { continue } // sparse connections
                var edge = Path()
                edge.move(to: netPositions[i])
                edge.addLine(to: netPositions[j])
                context.stroke(edge, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
            }
        }

        for i in 0..<nodeCount {
            let pos = netPositions[i]
            let color = DataManager.palette[min(i, DataManager.palette.count - 1)]
            let stressColor = Color(red: 0.3 + 0.5 * stress, green: 0.7 * (1 - stress * 0.5), blue: 0.9 * (1 - stress))
            let blendedColor = stress > 0.5 ? stressColor : color
            let r: CGFloat = 18
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(blendedColor.opacity(0.7)))

            // Node label
            context.draw(
                Text("N\(i)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6)),
                at: pos
            )

            // Stress radiating lines that grow with time
            if stress > 0.3 {
                for s in 0..<4 {
                    let sAngle = Double(s) * (.pi / 2.0) + time * 0.5 + Double(i) * 0.4
                    let sLen: CGFloat = 8 + 18 * stress
                    var stressLine = Path()
                    stressLine.move(to: CGPoint(x: pos.x + r * cos(sAngle), y: pos.y + r * sin(sAngle)))
                    stressLine.addLine(to: CGPoint(x: pos.x + (r + sLen) * cos(sAngle),
                                                     y: pos.y + (r + sLen) * sin(sAngle)))
                    context.stroke(stressLine, with: .color(.red.opacity(0.35 * stress)), lineWidth: 1.5)
                }
            }

            // Overload indicators (small "!" marks appearing with stress)
            if stress > 0.6 {
                let flash = 0.5 + 0.5 * sin(time * 5 + Double(i))
                context.draw(
                    Text("!")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(.red.opacity(0.6 * flash)),
                    at: CGPoint(x: pos.x + r + 4, y: pos.y - r - 4)
                )
            }
        }

        // "EXISTING NETWORK" label
        context.draw(
            Text("EXISTING NETWORK")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25)),
            at: CGPoint(x: netCenter.x, y: netCenter.y + netRadius + 36)
        )

        // Multiple new nodes joining (right side) — the problem scales
        let joiners = min(5, Int(time * 0.4) + 1)
        var newNodePositions: [CGPoint] = []
        for j in 0..<joiners {
            let yOffset = CGFloat(j - joiners / 2) * 80
            let xStagger = CGFloat(j % 2) * 40
            let newPos = CGPoint(x: size.width * 0.78 + xStagger, y: cy + yOffset)
            newNodePositions.append(newPos)

            let newR: CGFloat = 24
            let pulse = 0.7 + 0.3 * sin(time * 3 + Double(j))
            let newRect = CGRect(x: newPos.x - newR, y: newPos.y - newR, width: newR * 2, height: newR * 2)
            context.fill(Circle().path(in: newRect), with: .color(.yellow.opacity(0.75 * pulse)))
            context.stroke(Circle().path(in: newRect.insetBy(dx: -2, dy: -2)),
                          with: .color(.yellow.opacity(0.3)), lineWidth: 1)
            context.draw(
                Text("NEW")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.black.opacity(0.8)),
                at: newPos
            )
        }

        // "JOINERS" label
        context.draw(
            Text("\(joiners) JOINER\(joiners > 1 ? "S" : "")")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.4)),
            at: CGPoint(x: size.width * 0.8, y: cy + CGFloat(joiners) * 40 + 30)
        )

        // Request flood — each joiner sends requests to every network node
        for j in 0..<newNodePositions.count {
            let newPos = newNodePositions[j]
            let reqPerJoiner = Int(min(12, time * 1.5))
            for r in 0..<reqPerJoiner {
                let seed = Double(j * 997 + r * 3571)
                let targetIdx = Int(seed) % nodeCount
                let target = netPositions[targetIdx]
                let progress = ((time * 0.35 + seed * 0.02).truncatingRemainder(dividingBy: 1.0))
                let px = newPos.x + (target.x - newPos.x) * progress
                let py = newPos.y + (target.y - newPos.y) * progress
                let pRect = CGRect(x: px - 3, y: py - 3, width: 6, height: 6)
                context.fill(RoundedRectangle(cornerRadius: 1).path(in: pRect),
                            with: .color(.yellow.opacity(0.35 * (1 - progress))))
            }
        }

        // Center annotation: O(history) × joiners
        let annotAppear = min(1.0, max(0, time * 0.15 - 0.3))
        if annotAppear > 0 {
            let annotBox = CGRect(x: cx - 130, y: size.height * 0.78, width: 260, height: 50)
            context.fill(RoundedRectangle(cornerRadius: 8).path(in: annotBox),
                        with: .color(.orange.opacity(0.06 * annotAppear)))
            context.stroke(RoundedRectangle(cornerRadius: 8).path(in: annotBox),
                          with: .color(.orange.opacity(0.25 * annotAppear)), lineWidth: 1)
            context.draw(
                Text("COST = O(HISTORY) × JOINERS")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.7 * annotAppear)),
                at: CGPoint(x: annotBox.midX, y: annotBox.midY - 8)
            )
            context.draw(
                Text("each joiner replays entire DAG via gossip")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.4 * annotAppear)),
                at: CGPoint(x: annotBox.midX, y: annotBox.midY + 10)
            )
        }

        // Bandwidth meter (full width at top)
        let barX: CGFloat = 40
        let barY: CGFloat = 40
        let barW = size.width - 80
        let barH: CGFloat = 22
        let bgRect = CGRect(x: barX, y: barY, width: barW, height: barH)
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: bgRect),
                    with: .color(.white.opacity(0.05)))
        context.stroke(RoundedRectangle(cornerRadius: 4).path(in: bgRect),
                      with: .color(.white.opacity(0.15)), lineWidth: 1)

        let fillPct = min(1.0, time * 0.06 * Double(joiners))
        let fillRect = CGRect(x: barX, y: barY, width: barW * fillPct, height: barH)
        let barColor: Color = fillPct > 0.7 ? .red : fillPct > 0.4 ? .orange : .green
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: fillRect),
                    with: .color(barColor.opacity(0.6)))

        // Tick marks on bandwidth bar
        for tick in stride(from: 0.25, through: 0.75, by: 0.25) {
            let tickX = barX + barW * tick
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: tickX, y: barY))
            tickPath.addLine(to: CGPoint(x: tickX, y: barY + barH))
            context.stroke(tickPath, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
        }

        context.draw(
            Text("NETWORK BANDWIDTH: \(Int(fillPct * 100))%")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5)),
            at: CGPoint(x: cx, y: barY + barH + 14)
        )

        context.draw(
            Text("THE BOOTSTRAPPING PROBLEM — GOSSIP DOESN'T SCALE FOR HISTORY REPLAY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.orange.opacity(0.5)),
            at: CGPoint(x: cx, y: size.height - 30)
        )
    }

    // MARK: - Scene 2: Sybil Attack

    private func renderSybilAttack(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2

        // Honest nodes (left cluster)
        let honestCenter = CGPoint(x: cx * 0.4, y: cy)
        for i in 0..<8 {
            let angle = Double(i) * (2.0 * .pi / 8.0)
            let pos = CGPoint(x: honestCenter.x + 90 * cos(angle),
                               y: honestCenter.y + 70 * sin(angle))
            let r: CGFloat = 14
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            let color = DataManager.palette[min(i, DataManager.palette.count - 1)]
            context.fill(Circle().path(in: rect), with: .color(color.opacity(0.7)))
        }

        // Sybil swarm (flooding in from the right)
        let sybilCount = Int(min(200, time * 15))
        for i in 0..<sybilCount {
            let seed = Double(i * 4931)
            let x = cx * 0.8 + (seed.truncatingRemainder(dividingBy: (size.width * 0.55)))
            let y = 30 + (seed * 1.7).truncatingRemainder(dividingBy: (size.height - 60))

            // Ghost-like appearance
            let ghostPhase = (time * 0.5 + seed * 0.01).truncatingRemainder(dividingBy: 2.0)
            let ghostAlpha = ghostPhase < 1.0 ? 0.15 + 0.1 * ghostPhase : 0.25 * (2.0 - ghostPhase)

            let r: CGFloat = 4 + (seed.truncatingRemainder(dividingBy: 4))
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(.red.opacity(ghostAlpha)))
        }

        // Request lines from sybils to honest nodes
        let lineCount = Int(min(40, time * 3))
        for i in 0..<lineCount {
            let seed = Double(i * 7717)
            let fromX = cx * 0.8 + (seed.truncatingRemainder(dividingBy: (size.width * 0.4)))
            let fromY = 50 + (seed * 2.3).truncatingRemainder(dividingBy: (size.height - 100))
            let toIdx = Int(seed) % 8
            let toAngle = Double(toIdx) * (2.0 * .pi / 8.0)
            let toPos = CGPoint(x: honestCenter.x + 90 * cos(toAngle),
                                 y: honestCenter.y + 70 * sin(toAngle))

            let progress = ((time * 0.3 + seed * 0.02).truncatingRemainder(dividingBy: 1.0))
            var line = Path()
            line.move(to: CGPoint(x: fromX, y: fromY))
            line.addLine(to: CGPoint(
                x: fromX + (toPos.x - fromX) * progress,
                y: fromY + (toPos.y - fromY) * progress
            ))
            context.stroke(line, with: .color(.red.opacity(0.08)), lineWidth: 0.5)
        }

        // Bandwidth meter (maxed out)
        let barX: CGFloat = 40
        let barY: CGFloat = 30
        let barW = size.width - 80
        let barH: CGFloat = 24
        let bgRect = CGRect(x: barX, y: barY, width: barW, height: barH)
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: bgRect),
                    with: .color(.white.opacity(0.05)))
        let fillPct = min(1.0, time * 0.12)
        let fillRect = CGRect(x: barX, y: barY, width: barW * fillPct, height: barH)
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: fillRect),
                    with: .color(.red.opacity(0.7)))

        // Sybil count
        let countFlash = 0.6 + 0.4 * sin(time * 4)
        context.draw(
            Text("SYBIL NODES: \(sybilCount)")
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(countFlash)),
            at: CGPoint(x: size.width * 0.75, y: 80)
        )

        context.draw(
            Text("BANDWIDTH: \(Int(fillPct * 100))% — NETWORK COLLAPSE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.5)),
            at: CGPoint(x: cx, y: barY + barH + 14)
        )

        context.draw(
            Text("10,000 SYBIL NODES REQUEST FULL HISTORY — HONEST NETWORK DROWNS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.5)),
            at: CGPoint(x: cx, y: size.height - 40)
        )
    }

    // MARK: - Scene 3: The Separation

    private func renderSeparation(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2
        let appear = min(1.0, time * 0.25)

        // LEFT: Crisis = Order (green)
        let leftW: CGFloat = size.width * 0.35
        let leftH: CGFloat = size.height * 0.45
        let leftRect = CGRect(x: cx - leftW - 40, y: cy - leftH / 2, width: leftW, height: leftH)
        context.fill(RoundedRectangle(cornerRadius: 16).path(in: leftRect),
                    with: .color(.green.opacity(0.08 * appear)))
        context.stroke(RoundedRectangle(cornerRadius: 16).path(in: leftRect),
                      with: .color(.green.opacity(0.5 * appear)), lineWidth: 2)

        context.draw(
            Text("CRISIS")
                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.8 * appear)),
            at: CGPoint(x: leftRect.midX, y: leftRect.midY - 30)
        )
        context.draw(
            Text("CONSENSUS LAYER")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.5 * appear)),
            at: CGPoint(x: leftRect.midX, y: leftRect.midY)
        )
        context.draw(
            Text("deterministic ordering")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.green.opacity(0.4 * appear)),
            at: CGPoint(x: leftRect.midX, y: leftRect.midY + 20)
        )
        context.draw(
            Text("from DAG structure")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.green.opacity(0.3 * appear)),
            at: CGPoint(x: leftRect.midX, y: leftRect.midY + 36)
        )

        // RIGHT: DA Layer = Storage (blue)
        let rightRect = CGRect(x: cx + 40, y: cy - leftH / 2, width: leftW, height: leftH)
        context.fill(RoundedRectangle(cornerRadius: 16).path(in: rightRect),
                    with: .color(.blue.opacity(0.08 * appear)))
        context.stroke(RoundedRectangle(cornerRadius: 16).path(in: rightRect),
                      with: .color(.blue.opacity(0.5 * appear)), lineWidth: 2)

        context.draw(
            Text("DA LAYER")
                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                .foregroundColor(.blue.opacity(0.8 * appear)),
            at: CGPoint(x: rightRect.midX, y: rightRect.midY - 30)
        )
        context.draw(
            Text("STORAGE & RETRIEVAL")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.blue.opacity(0.5 * appear)),
            at: CGPoint(x: rightRect.midX, y: rightRect.midY)
        )
        context.draw(
            Text("erasure coding")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.blue.opacity(0.4 * appear)),
            at: CGPoint(x: rightRect.midX, y: rightRect.midY + 20)
        )
        context.draw(
            Text("incentivized storage")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.blue.opacity(0.3 * appear)),
            at: CGPoint(x: rightRect.midX, y: rightRect.midY + 36)
        )

        // Arrow between them
        let arrowAppear = min(1.0, max(0, time * 0.25 - 0.5))
        if arrowAppear > 0.05 {
            var arrow = Path()
            arrow.move(to: CGPoint(x: leftRect.maxX + 5, y: cy))
            arrow.addLine(to: CGPoint(x: rightRect.minX - 5, y: cy))
            context.stroke(arrow, with: .color(.white.opacity(0.5 * arrowAppear)), lineWidth: 2)

            // Arrowhead
            var head = Path()
            head.move(to: CGPoint(x: rightRect.minX - 5, y: cy))
            head.addLine(to: CGPoint(x: rightRect.minX - 15, y: cy - 6))
            head.addLine(to: CGPoint(x: rightRect.minX - 15, y: cy + 6))
            head.closeSubpath()
            context.fill(head, with: .color(.white.opacity(0.5 * arrowAppear)))

            context.draw(
                Text("HASH COMMITMENTS")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4 * arrowAppear)),
                at: CGPoint(x: cx, y: cy - 20)
            )
        }

        context.draw(
            Text("TWO SEPARATE LAYERS — COUPLED ONLY BY CRYPTOGRAPHIC HASHES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3 * appear)),
            at: CGPoint(x: cx, y: size.height - 40)
        )
    }
}
