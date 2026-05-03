import SwiftUI

/// Ch09: "Data Availability — A Design" — erasure coding, Merkle tree, on-demand retrieval, fee market, full stack.
struct Ch09_DA_Design: View {
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
        switch sceneIndex {
        case 0: renderErasureCoding(context: &context, size: size, time: time)
        case 1: renderMerkleTree(context: &context, size: size, time: time)
        case 2: renderOnDemand(context: &context, size: size, time: time)
        case 3: renderFeeMarket(context: &context, size: size, time: time)
        case 4: renderFullStack(context: &context, size: size, time: time)
        default: break
        }
    }

    // MARK: - Scene 0: Erasure Coding

    private func renderErasureCoding(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2
        let k = 4
        let n = 8
        let splitProgress = min(1.0, time * 0.2)
        let distributeProgress = min(1.0, max(0, time * 0.15 - 0.8))

        // Original message block (top center)
        let origW: CGFloat = 200
        let origH: CGFloat = 60
        let origRect = CGRect(x: cx - origW / 2, y: cy - 160, width: origW, height: origH)
        let origAlpha = max(0, 1.0 - splitProgress * 0.5)
        context.fill(RoundedRectangle(cornerRadius: 10).path(in: origRect),
                    with: .color(.white.opacity(0.15 * origAlpha)))
        context.stroke(RoundedRectangle(cornerRadius: 10).path(in: origRect),
                      with: .color(.white.opacity(0.3 * origAlpha)), lineWidth: 1.5)
        context.draw(
            Text("MESSAGE PAYLOAD")
                .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.7 * origAlpha)),
            at: CGPoint(x: origRect.midX, y: origRect.midY)
        )

        // Chunks splitting out
        let chunkW: CGFloat = 60
        let chunkH: CGFloat = 40
        let totalChunkW = CGFloat(n) * chunkW + CGFloat(n - 1) * 12
        let chunksStartX = cx - totalChunkW / 2
        let chunksY = cy - 30.0

        let chunkColors: [Color] = (0..<n).map { i in
            let hue = Double(i) / Double(n) * 0.75
            let sat = i < k ? 0.7 : 0.35
            return Color(hue: hue, saturation: sat, brightness: 0.85)
        }

        for i in 0..<n {
            let targetX = chunksStartX + CGFloat(i) * (chunkW + 12)
            let startX = cx - chunkW / 2
            let startY = origRect.maxY
            let x = startX + (targetX - startX) * splitProgress
            let y = startY + (chunksY - startY) * splitProgress

            let rect = CGRect(x: x, y: y, width: chunkW, height: chunkH)
            context.fill(RoundedRectangle(cornerRadius: 6).path(in: rect),
                        with: .color(chunkColors[i].opacity(0.7 * splitProgress)))
            context.stroke(RoundedRectangle(cornerRadius: 6).path(in: rect),
                          with: .color(chunkColors[i].opacity(0.4 * splitProgress)), lineWidth: 1)

            let label = i < k ? "D\(i + 1)" : "P\(i - k + 1)"
            let typeLabel = i < k ? "data" : "parity"
            context.draw(
                Text(label)
                    .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8 * splitProgress)),
                at: CGPoint(x: rect.midX, y: rect.midY - 6)
            )
            context.draw(
                Text(typeLabel)
                    .font(.system(size: settings.scaled(10), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4 * splitProgress)),
                at: CGPoint(x: rect.midX, y: rect.midY + 10)
            )
        }

        // Distribution to storage nodes (phase 2)
        if distributeProgress > 0 {
            let storageY = cy + 100.0
            let storageR: CGFloat = 20

            for i in 0..<n {
                let chunkX = chunksStartX + CGFloat(i) * (chunkW + 12) + chunkW / 2
                let storageX = chunkX
                let storePos = CGPoint(x: storageX, y: storageY + 50)

                // Arrow from chunk to storage
                var arrow = Path()
                arrow.move(to: CGPoint(x: chunkX, y: chunksY + chunkH))
                let arrowEndY = storageY + 50 - storageR
                arrow.addLine(to: CGPoint(x: storageX, y: chunksY + chunkH + (arrowEndY - chunksY - chunkH) * distributeProgress))
                context.stroke(arrow, with: .color(chunkColors[i].opacity(0.3 * distributeProgress)), lineWidth: 1)

                // Storage node
                if distributeProgress > 0.3 {
                    let nodeRect = CGRect(x: storePos.x - storageR, y: storePos.y - storageR,
                                           width: storageR * 2, height: storageR * 2)
                    context.fill(RoundedRectangle(cornerRadius: 6).path(in: nodeRect),
                                with: .color(chunkColors[i].opacity(0.3 * distributeProgress)))
                    context.draw(
                        Text("S\(i + 1)")
                            .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6 * distributeProgress)),
                        at: storePos
                    )
                }
            }
        }

        // Labels
        context.draw(
            Text("ERASURE CODING: \(k)-of-\(n) REDUNDANCY")
                .font(.system(size: settings.scaled(14), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)),
            at: CGPoint(x: cx, y: 30)
        )
        context.draw(
            Text("ANY \(k) CHUNKS SUFFICE TO RECONSTRUCT — NO FULL REPLICATION NEEDED")
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.4)),
            at: CGPoint(x: cx, y: size.height - 40)
        )
    }

    // MARK: - Scene 1: Merkle Tree

    private func renderMerkleTree(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let levels = 4
        let nodeR: CGFloat = 16
        let topY: CGFloat = 80
        let levelSpacing: CGFloat = (size.height - 200) / CGFloat(levels)

        // Highlighted proof path
        let proofPath: [Int] = [0, 1, 2, 5]  // indices along the tree path

        func drawNode(level: Int, index: Int, parentPos: CGPoint?) {
            let nodesAtLevel = 1 << level
            let spacing = (size.width - 100) / CGFloat(nodesAtLevel)
            let x = 50 + spacing * (CGFloat(index) + 0.5)
            let y = topY + CGFloat(level) * levelSpacing
            let pos = CGPoint(x: x, y: y)

            let appear = min(1.0, max(0, time * 0.4 - Double(level) * 0.15))
            if appear < 0.02 { return }

            // Edge to parent
            if let parent = parentPos {
                var edge = Path()
                edge.move(to: parent)
                edge.addLine(to: pos)
                context.stroke(edge, with: .color(.white.opacity(0.15 * appear)), lineWidth: 1)
            }

            let isLeaf = level == levels - 1
            let isOnProofPath = proofPath.contains(level * 10 + index) || (level == 0 && index == 0)

            let color: Color = isOnProofPath ? .yellow : (isLeaf ? .cyan : .purple)
            let rect = CGRect(x: pos.x - nodeR, y: pos.y - nodeR, width: nodeR * 2, height: nodeR * 2)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(0.6 * appear)))

            if isOnProofPath {
                context.stroke(Circle().path(in: rect.insetBy(dx: -3, dy: -3)),
                              with: .color(.yellow.opacity(0.5 * appear)), lineWidth: 2)
            }

            // Hash label
            let hashLabel = isLeaf ? "chunk\(index)" : "h(\(index))"
            context.draw(
                Text(hashLabel)
                    .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5 * appear)),
                at: CGPoint(x: pos.x, y: pos.y + nodeR + 8)
            )

            if level < levels - 1 {
                drawNode(level: level + 1, index: index * 2, parentPos: pos)
                drawNode(level: level + 1, index: index * 2 + 1, parentPos: pos)
            }
        }

        drawNode(level: 0, index: 0, parentPos: nil)

        context.draw(
            Text("MERKLE TREE OF CHUNKS")
                .font(.system(size: settings.scaled(14), weight: .heavy, design: .monospaced))
                .foregroundColor(.purple.opacity(0.5)),
            at: CGPoint(x: cx, y: 30)
        )
        context.draw(
            Text("YELLOW PATH = PROOF — VERIFY ANY CHUNK WITHOUT DOWNLOADING ALL")
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.4)),
            at: CGPoint(x: cx, y: size.height - 40)
        )
    }

    // MARK: - Scene 2: On-Demand Retrieval

    private func renderOnDemand(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2

        // Requester Z (left)
        let zPos = CGPoint(x: size.width * 0.15, y: cy)
        let zR: CGFloat = 30
        let zRect = CGRect(x: zPos.x - zR, y: zPos.y - zR, width: zR * 2, height: zR * 2)
        context.fill(Circle().path(in: zRect), with: .color(.yellow.opacity(0.8)))
        context.draw(Text("Z").font(.system(size: settings.scaled(16), weight: .heavy, design: .monospaced)).foregroundColor(.black), at: zPos)
        context.draw(
            Text("REQUESTER")
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.5)),
            at: CGPoint(x: zPos.x, y: zPos.y + zR + 14)
        )

        // Storage node S (right)
        let sPos = CGPoint(x: size.width * 0.85, y: cy)
        let sR: CGFloat = 30
        let sRect = CGRect(x: sPos.x - sR, y: sPos.y - sR, width: sR * 2, height: sR * 2)
        context.fill(Circle().path(in: sRect), with: .color(.blue.opacity(0.8)))
        context.draw(Text("S").font(.system(size: settings.scaled(16), weight: .heavy, design: .monospaced)).foregroundColor(.white), at: sPos)
        context.draw(
            Text("STORAGE NODE")
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.blue.opacity(0.5)),
            at: CGPoint(x: sPos.x, y: sPos.y + sR + 14)
        )

        // PoW fee attached to request
        let feeBox = CGRect(x: cx - 80, y: cy - 80, width: 160, height: 30)
        context.fill(RoundedRectangle(cornerRadius: 6).path(in: feeBox),
                    with: .color(.yellow.opacity(0.1)))
        context.stroke(RoundedRectangle(cornerRadius: 6).path(in: feeBox),
                      with: .color(.yellow.opacity(0.3)), lineWidth: 1)
        context.draw(
            Text("REQUEST + FEE (anti-sybil)")
                .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.6)),
            at: CGPoint(x: feeBox.midX, y: feeBox.midY)
        )

        // Request arrow (Z → S, top lane)
        let reqProgress = min(1.0, time * 0.2)
        let reqY = cy - 25.0
        if reqProgress > 0 {
            var arrow = Path()
            arrow.move(to: CGPoint(x: zPos.x + zR, y: reqY))
            arrow.addLine(to: CGPoint(x: zPos.x + zR + (sPos.x - zPos.x - 2 * sR) * reqProgress, y: reqY))
            context.stroke(arrow, with: .color(.yellow.opacity(0.6)), lineWidth: 2.5)

            // Animated packet
            let packetX = zPos.x + zR + (sPos.x - zPos.x - 2 * sR) * ((time * 0.3).truncatingRemainder(dividingBy: 1.0))
            let packetRect = CGRect(x: packetX - 6, y: reqY - 6, width: 12, height: 12)
            context.fill(RoundedRectangle(cornerRadius: 3).path(in: packetRect),
                        with: .color(.yellow.opacity(0.7)))
        }

        // Response arrow (S → Z, bottom lane)
        let respProgress = min(1.0, max(0, time * 0.2 - 0.7))
        let respY = cy + 25.0
        if respProgress > 0 {
            var arrow = Path()
            arrow.move(to: CGPoint(x: sPos.x - sR, y: respY))
            arrow.addLine(to: CGPoint(x: sPos.x - sR - (sPos.x - zPos.x - 2 * sR) * respProgress, y: respY))
            context.stroke(arrow, with: .color(.blue.opacity(0.6)), lineWidth: 2.5)

            // Response box
            let respBox = CGRect(x: cx - 80, y: cy + 50, width: 160, height: 30)
            context.fill(RoundedRectangle(cornerRadius: 6).path(in: respBox),
                        with: .color(.blue.opacity(0.1 * respProgress)))
            context.stroke(RoundedRectangle(cornerRadius: 6).path(in: respBox),
                          with: .color(.blue.opacity(0.3 * respProgress)), lineWidth: 1)
            context.draw(
                Text("CHUNK + MERKLE PROOF")
                    .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                    .foregroundColor(.blue.opacity(0.6 * respProgress)),
                at: CGPoint(x: respBox.midX, y: respBox.midY)
            )
        }

        context.draw(
            Text("POINT-TO-POINT RETRIEVAL — NOT BROADCAST")
                .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.3)),
            at: CGPoint(x: cx, y: 40)
        )
        context.draw(
            Text("REQUESTING COSTS SOMETHING → SYBIL ATTACK BECOMES EXPENSIVE")
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.4)),
            at: CGPoint(x: cx, y: size.height - 40)
        )
    }

    // MARK: - Scene 3: Fee Market

    private func renderFeeMarket(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let graphW: CGFloat = min(550, size.width * 0.5)
        let graphH: CGFloat = min(320, size.height * 0.42)
        let graphCenterY = size.height * 0.38
        let origin = CGPoint(x: cx - graphW / 2, y: graphCenterY + graphH / 2)

        // Grid lines
        for tick in stride(from: 0.2, through: 0.8, by: 0.2) {
            var hGrid = Path()
            hGrid.move(to: CGPoint(x: origin.x, y: origin.y - graphH * tick))
            hGrid.addLine(to: CGPoint(x: origin.x + graphW, y: origin.y - graphH * tick))
            context.stroke(hGrid, with: .color(.white.opacity(0.03)), lineWidth: 0.5)

            var vGrid = Path()
            vGrid.move(to: CGPoint(x: origin.x + graphW * tick, y: origin.y))
            vGrid.addLine(to: CGPoint(x: origin.x + graphW * tick, y: origin.y - graphH))
            context.stroke(vGrid, with: .color(.white.opacity(0.03)), lineWidth: 0.5)
        }

        // Axes
        var xAxis = Path()
        xAxis.move(to: origin)
        xAxis.addLine(to: CGPoint(x: origin.x + graphW, y: origin.y))
        context.stroke(xAxis, with: .color(.white.opacity(0.3)), lineWidth: 1.5)

        var yAxis = Path()
        yAxis.move(to: origin)
        yAxis.addLine(to: CGPoint(x: origin.x, y: origin.y - graphH))
        context.stroke(yAxis, with: .color(.white.opacity(0.3)), lineWidth: 1.5)

        // Supply curve (upward, green) — animated
        let supplyAppear = min(1.0, time * 0.2)
        if supplyAppear > 0 {
            // Fill under supply curve
            var supplyFill = Path()
            supplyFill.move(to: origin)
            let steps = 40
            for s in 0...steps {
                let t = Double(s) / Double(steps) * supplyAppear
                let x = origin.x + graphW * t
                let y = origin.y - graphH * 0.05 - graphH * 0.8 * t * t
                supplyFill.addLine(to: CGPoint(x: x, y: y))
            }
            supplyFill.addLine(to: CGPoint(x: origin.x + graphW * supplyAppear, y: origin.y))
            supplyFill.closeSubpath()
            context.fill(supplyFill, with: .color(.green.opacity(0.04 * supplyAppear)))

            var supply = Path()
            for s in 0...steps {
                let t = Double(s) / Double(steps) * supplyAppear
                let x = origin.x + graphW * t
                let y = origin.y - graphH * 0.05 - graphH * 0.8 * t * t
                if s == 0 { supply.move(to: CGPoint(x: x, y: y)) }
                else { supply.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(supply, with: .color(.green.opacity(0.7)), lineWidth: 2.5)

            context.draw(
                Text("SUPPLY")
                    .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.6)),
                at: CGPoint(x: origin.x + graphW * supplyAppear + 30, y: origin.y - graphH * 0.8 * supplyAppear * supplyAppear)
            )
        }

        // Demand curve (downward, orange) — animated
        let demandAppear = min(1.0, max(0, time * 0.2 - 0.4))
        if demandAppear > 0 {
            // Fill under demand curve
            var demandFill = Path()
            demandFill.move(to: CGPoint(x: origin.x, y: origin.y - graphH * 0.9))
            let steps = 40
            for s in 0...steps {
                let t = Double(s) / Double(steps) * demandAppear
                let x = origin.x + graphW * t
                let y = origin.y - graphH * 0.9 + graphH * 0.8 * t * t
                demandFill.addLine(to: CGPoint(x: x, y: y))
            }
            demandFill.addLine(to: CGPoint(x: origin.x + graphW * demandAppear, y: origin.y))
            demandFill.addLine(to: origin)
            demandFill.closeSubpath()
            context.fill(demandFill, with: .color(.orange.opacity(0.03 * demandAppear)))

            var demand = Path()
            for s in 0...steps {
                let t = Double(s) / Double(steps) * demandAppear
                let x = origin.x + graphW * t
                let y = origin.y - graphH * 0.9 + graphH * 0.8 * t * t
                if s == 0 { demand.move(to: CGPoint(x: x, y: y)) }
                else { demand.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(demand, with: .color(.orange.opacity(0.7)), lineWidth: 2.5)

            context.draw(
                Text("DEMAND")
                    .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.6)),
                at: CGPoint(x: origin.x + graphW * demandAppear + 30,
                             y: origin.y - graphH * 0.9 + graphH * 0.8 * demandAppear * demandAppear)
            )
        }

        // Equilibrium point + shading
        if supplyAppear > 0.7 && demandAppear > 0.7 {
            let eqX = origin.x + graphW * 0.42
            let eqY = origin.y - graphH * 0.42
            let eqR: CGFloat = 8
            let flash = 0.5 + 0.5 * sin(time * 3)
            let eqRect = CGRect(x: eqX - eqR, y: eqY - eqR, width: eqR * 2, height: eqR * 2)
            context.fill(Circle().path(in: eqRect), with: .color(.white.opacity(0.8 * flash)))

            // Glow around equilibrium
            for ring in 1...3 {
                let ringR = eqR + CGFloat(ring) * 6
                let ringRect = CGRect(x: eqX - ringR, y: eqY - ringR, width: ringR * 2, height: ringR * 2)
                context.stroke(Circle().path(in: ringRect),
                              with: .color(.white.opacity(0.1 * flash / Double(ring))), lineWidth: 1)
            }

            // Dashed lines to axes
            let dashStyle = StrokeStyle(lineWidth: 1, dash: [4, 4])
            var hLine = Path()
            hLine.move(to: CGPoint(x: origin.x, y: eqY))
            hLine.addLine(to: CGPoint(x: eqX, y: eqY))
            context.stroke(hLine, with: .color(.white.opacity(0.2)), style: dashStyle)

            var vLine = Path()
            vLine.move(to: CGPoint(x: eqX, y: origin.y))
            vLine.addLine(to: CGPoint(x: eqX, y: eqY))
            context.stroke(vLine, with: .color(.white.opacity(0.2)), style: dashStyle)

            context.draw(
                Text("P*")
                    .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5)),
                at: CGPoint(x: origin.x - 14, y: eqY)
            )
            context.draw(
                Text("Q*")
                    .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5)),
                at: CGPoint(x: eqX, y: origin.y + 14)
            )

            // Equilibrium label
            context.draw(
                Text("EQUILIBRIUM PRICE")
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4)),
                at: CGPoint(x: eqX + 60, y: eqY - 14)
            )
        }

        // Axis labels
        context.draw(
            Text("PRICE (fee per chunk)")
                .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35)),
            at: CGPoint(x: origin.x - 10, y: origin.y - graphH / 2)
        )
        context.draw(
            Text("QUANTITY (storage served)")
                .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35)),
            at: CGPoint(x: origin.x + graphW / 2, y: origin.y + 30)
        )

        // Bottom: comparative data cards showing popular vs rare pricing
        let cardsY = origin.y + 70
        let cardW: CGFloat = 200
        let cardH: CGFloat = 55

        // Popular data card (left)
        let popRect = CGRect(x: cx - cardW - 30, y: cardsY, width: cardW, height: cardH)
        context.fill(RoundedRectangle(cornerRadius: 8).path(in: popRect),
                    with: .color(.green.opacity(0.06)))
        context.stroke(RoundedRectangle(cornerRadius: 8).path(in: popRect),
                      with: .color(.green.opacity(0.2)), lineWidth: 1)
        context.draw(
            Text("POPULAR DATA")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.6)),
            at: CGPoint(x: popRect.midX, y: popRect.midY - 10)
        )
        context.draw(
            Text("many providers → low fee")
                .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
                .foregroundColor(.green.opacity(0.35)),
            at: CGPoint(x: popRect.midX, y: popRect.midY + 8)
        )

        // Rare data card (right)
        let rareRect = CGRect(x: cx + 30, y: cardsY, width: cardW, height: cardH)
        context.fill(RoundedRectangle(cornerRadius: 8).path(in: rareRect),
                    with: .color(.orange.opacity(0.06)))
        context.stroke(RoundedRectangle(cornerRadius: 8).path(in: rareRect),
                      with: .color(.orange.opacity(0.2)), lineWidth: 1)
        context.draw(
            Text("RARE DATA")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.orange.opacity(0.6)),
            at: CGPoint(x: rareRect.midX, y: rareRect.midY - 10)
        )
        context.draw(
            Text("few providers → premium fee")
                .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
                .foregroundColor(.orange.opacity(0.35)),
            at: CGPoint(x: rareRect.midX, y: rareRect.midY + 8)
        )

        context.draw(
            Text("INCENTIVIZED STORAGE — FEE MARKET DISCOVERY")
                .font(.system(size: settings.scaled(14), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.3)),
            at: CGPoint(x: cx, y: 30)
        )
        context.draw(
            Text("STORAGE NODES EARN FEES — PRICE DISCOVERY EMERGES NATURALLY")
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.orange.opacity(0.4)),
            at: CGPoint(x: cx, y: size.height - 30)
        )
    }

    // MARK: - Scene 4: Full Stack

    private func renderFullStack(context: inout GraphicsContext, size: CGSize, time: Double) {
        let cx = size.width / 2
        let cy = size.height / 2
        let layerW: CGFloat = min(600, size.width * 0.6)
        let layerH: CGFloat = 100
        let gap: CGFloat = 50
        let appear = min(1.0, time * 0.2)

        // Top: Crisis consensus
        let topRect = CGRect(x: cx - layerW / 2, y: cy - layerH - gap / 2, width: layerW, height: layerH)
        context.fill(RoundedRectangle(cornerRadius: 14).path(in: topRect),
                    with: .color(.green.opacity(0.08 * appear)))
        context.stroke(RoundedRectangle(cornerRadius: 14).path(in: topRect),
                      with: .color(.green.opacity(0.5 * appear)), lineWidth: 2)
        context.draw(
            Text("CRISIS CONSENSUS")
                .font(.system(size: settings.scaled(18), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.7 * appear)),
            at: CGPoint(x: topRect.midX, y: topRect.midY - 12)
        )
        context.draw(
            Text("DAG · PoW · Virtual Voting · Total Order")
                .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
                .foregroundColor(.green.opacity(0.4 * appear)),
            at: CGPoint(x: topRect.midX, y: topRect.midY + 12)
        )

        // Bottom: DA Layer
        let botRect = CGRect(x: cx - layerW / 2, y: cy + gap / 2, width: layerW, height: layerH)
        context.fill(RoundedRectangle(cornerRadius: 14).path(in: botRect),
                    with: .color(.blue.opacity(0.08 * appear)))
        context.stroke(RoundedRectangle(cornerRadius: 14).path(in: botRect),
                      with: .color(.blue.opacity(0.5 * appear)), lineWidth: 2)
        context.draw(
            Text("DATA AVAILABILITY LAYER")
                .font(.system(size: settings.scaled(18), weight: .heavy, design: .monospaced))
                .foregroundColor(.blue.opacity(0.7 * appear)),
            at: CGPoint(x: botRect.midX, y: botRect.midY - 12)
        )
        context.draw(
            Text("Erasure Coding · Merkle Proofs · Fee Market")
                .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
                .foregroundColor(.blue.opacity(0.4 * appear)),
            at: CGPoint(x: botRect.midX, y: botRect.midY + 12)
        )

        // Connecting arrows
        let arrowAppear = min(1.0, max(0, time * 0.2 - 0.5))
        if arrowAppear > 0.05 {
            for xOff in stride(from: -layerW * 0.3, through: layerW * 0.3, by: layerW * 0.3) {
                var arrow = Path()
                arrow.move(to: CGPoint(x: cx + xOff, y: topRect.maxY + 3))
                arrow.addLine(to: CGPoint(x: cx + xOff, y: botRect.minY - 3))
                context.stroke(arrow, with: .color(.white.opacity(0.3 * arrowAppear)), lineWidth: 1.5)

                // Arrowhead
                let aY = botRect.minY - 3
                var head = Path()
                head.move(to: CGPoint(x: cx + xOff, y: aY))
                head.addLine(to: CGPoint(x: cx + xOff - 4, y: aY - 8))
                head.addLine(to: CGPoint(x: cx + xOff + 4, y: aY - 8))
                head.closeSubpath()
                context.fill(head, with: .color(.white.opacity(0.3 * arrowAppear)))
            }

            context.draw(
                Text("HASH COMMITMENTS")
                    .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35 * arrowAppear)),
                at: CGPoint(x: cx, y: cy)
            )
        }

        context.draw(
            Text("NODES PAY FOR WHAT THEY NEED — TWO LAYERS, ONE PROTOCOL")
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3 * appear)),
            at: CGPoint(x: cx, y: size.height - 40)
        )
    }
}
