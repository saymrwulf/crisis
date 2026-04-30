import SwiftUI

/// Live-driven overlay used by `ImmersiveView`: wraps `VertexInspector` in its
/// own TimelineView so the recursive reveal animates from the moment the user
/// clicks (independent of the underlying scene's clock).
@MainActor
struct VertexInspectorOverlay: View {
    let state: InspectionState
    let dm: DataManager
    let onDismiss: () -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            VertexInspector(
                state: state,
                dm: dm,
                localTime: state.localTime(at: timeline.date),
                onDismiss: onDismiss
            )
        }
    }
}

/// Vertex Inspection overlay — answers the question: "what does THIS vertex know?"
///
/// Animates a recursive uncovering of the selected vertex's causal history:
///
///   t=0.0 → root card enters (sealed)
///   t=0.6 → root card cracks open: payload + parent-hash chips revealed
///   t=1.5 → parent cards enter (sealed); arrows draw from root's chips to them
///   t=2.1 → parent cards crack open
///   …
///
/// Up to `maxDepth` levels, then a "← genesis" indicator. Tap anywhere to dismiss.
@MainActor
struct VertexInspector: View {
    let state: InspectionState
    let dm: DataManager
    let localTime: Double
    let onDismiss: () -> Void

    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 168
    private let columnGap: CGFloat = 32
    private let levelStagger: Double = 1.5      // seconds between depth levels
    private let crackOffset: Double = 0.6       // seconds after entry that the seal cracks
    private let maxDepth: Int = 4
    private let maxParentsPerCard: Int = 4

    var body: some View {
        Canvas(opaque: false) { context, size in
            render(context: &context, size: size, time: localTime)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .transition(.opacity.combined(with: .scale(scale: 1.02)))
    }

    // MARK: - Rendering

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard let sim = dm.sim,
              let digest = state.selectedDigest,
              let snap = dm.honestData(step: 9) else {
            context.draw(
                Text("Loading inspection…").foregroundColor(.white.opacity(0.7)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            return
        }

        // Vertex / parent lookups from the FULL snapshot (so the recursive
        // walk is complete, not limited to the currently visible Ch02 subset).
        let vertexByDigest: [String: VertexData] =
            Dictionary(uniqueKeysWithValues: snap.vertices.map { ($0.digestHex, $0) })
        var parentMap: [String: [String]] = [:]
        for e in snap.edges { parentMap[e.from, default: []].append(e.to) }

        guard let root = vertexByDigest[digest] else {
            context.draw(
                Text("Vertex \(String(digest.prefix(8))) not in current snapshot")
                    .foregroundColor(.red.opacity(0.85)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            return
        }

        // BFS upward through ancestors. Each vertex appears once at its earliest depth.
        var levels: [[VertexData]] = [[root]]
        var seen: Set<String> = [root.digestHex]
        var displayedParents: [String: [String]] = [:]

        for d in 0..<maxDepth {
            var next: [VertexData] = []
            for v in levels[d] {
                let parents = (parentMap[v.digestHex] ?? []).prefix(maxParentsPerCard).map { $0 }
                displayedParents[v.digestHex] = parents
                for p in parents where !seen.contains(p) {
                    if let pv = vertexByDigest[p] {
                        next.append(pv)
                        seen.insert(p)
                    }
                }
            }
            if next.isEmpty { break }
            levels.append(next)
        }

        // Layout: depth 0 (clicked vertex) on the right; ancestors expand leftward.
        let levelCount = levels.count
        let totalWidth = CGFloat(levelCount) * cardWidth + CGFloat(max(0, levelCount - 1)) * columnGap
        let topReserved: CGFloat = 70   // title bar
        let bottomReserved: CGFloat = 50
        let usableHeight = size.height - topReserved - bottomReserved
        let originX = (size.width - totalWidth) / 2

        var positions: [String: CGPoint] = [:]
        for (depth, vs) in levels.enumerated() {
            let columnIdx = (levelCount - 1) - depth
            let cx = originX + CGFloat(columnIdx) * (cardWidth + columnGap) + cardWidth / 2

            let count = max(1, vs.count)
            // Distribute evenly across usable height
            let step = usableHeight / CGFloat(count)
            for (i, v) in vs.enumerated() {
                let cy = topReserved + step * (CGFloat(i) + 0.5)
                positions[v.digestHex] = CGPoint(x: cx, y: cy)
            }
        }

        // ── Backdrop accent: a faint horizontal time-arrow strip ──────────────
        let timeArrowY = topReserved + usableHeight + 18
        var arrowTrack = Path()
        arrowTrack.move(to: CGPoint(x: originX - 30, y: timeArrowY))
        arrowTrack.addLine(to: CGPoint(x: originX + totalWidth + 30, y: timeArrowY))
        context.stroke(arrowTrack, with: .color(.white.opacity(0.12)), lineWidth: 0.8)
        context.draw(
            Text("← past   ·   causal time   ·   present →")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.32)),
            at: CGPoint(x: originX + totalWidth / 2, y: timeArrowY + 12)
        )

        // ── Arrows (drawn under cards, but parents arrive AFTER the chip is visible) ──
        for (depth, vs) in levels.enumerated() {
            // Arrows from this level to its parents come in slightly before the next
            // level's cards — they "guide the eye" toward the arriving parents.
            let arrowAppear = Double(depth + 1) * levelStagger - 0.2
            let p = clamp((time - arrowAppear) / 0.55, 0, 1)
            if p <= 0 { continue }

            for v in vs {
                guard let from = positions[v.digestHex] else { continue }
                let parents = displayedParents[v.digestHex] ?? []
                for ph in parents {
                    guard let to = positions[ph] else { continue }
                    drawArrow(context: &context, from: from, to: to, progress: p)
                }
            }
        }

        // ── Cards ──
        for (depth, vs) in levels.enumerated() {
            // Depth 0 starts pre-entered so the root is visible immediately at t=0
            // (the user just clicked it — no need for a fade-in there).
            let revealStart = depth == 0 ? -0.4 : Double(depth) * levelStagger
            let entry = clamp((time - revealStart) / 0.4, 0, 1)
            let crack = clamp((time - revealStart - crackOffset) / 0.6, 0, 1)
            for v in vs {
                guard let pos = positions[v.digestHex] else { continue }
                drawCard(
                    context: &context,
                    at: pos,
                    vertex: v,
                    parents: displayedParents[v.digestHex] ?? [],
                    isRoot: depth == 0,
                    entry: entry,
                    crack: crack
                )
            }
        }

        // ── Title bar + dismiss hint ──
        drawTitleBar(context: &context, size: size, root: root, sim: sim)
        context.draw(
            Text("CLICK ANYWHERE TO RETURN TO THE GRAPH")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45)),
            at: CGPoint(x: size.width / 2, y: size.height - 22)
        )
    }

    // MARK: - Title bar

    private func drawTitleBar(
        context: inout GraphicsContext,
        size: CGSize,
        root: VertexData,
        sim: SimulationData
    ) {
        let bg = CGRect(x: 0, y: 0, width: size.width, height: 60)
        context.fill(Rectangle().path(in: bg), with: .color(.black.opacity(0.75)))
        var sep = Path()
        sep.move(to: CGPoint(x: 0, y: 60))
        sep.addLine(to: CGPoint(x: size.width, y: 60))
        context.stroke(sep, with: .color(.white.opacity(0.12)), lineWidth: 0.5)

        context.draw(
            Text("KNOWLEDGE STATE OF VERTEX")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .kerning(2),
            at: CGPoint(x: size.width / 2, y: 14)
        )
        let nodeName = sim.nodes.first(where: { $0.processIdHex == root.processIdHex })?.name ?? "?"
        context.draw(
            Text("0x\(String(root.digestFull.prefix(20)))…  ·  origin \(nodeName)  ·  round \(root.round)  ·  weight \(root.weight)")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.92)),
            at: CGPoint(x: size.width / 2, y: 36)
        )
    }

    // MARK: - Arrow

    private func drawArrow(
        context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        progress: Double
    ) {
        // `from` is the CHILD (depth k, on the right); `to` is the PARENT (depth k+1, on the left).
        let fromAttach = CGPoint(x: from.x - cardWidth / 2 - 2, y: from.y)
        let toAttach = CGPoint(x: to.x + cardWidth / 2 + 2, y: to.y)

        // Bezier through midpoint (slight upward bow for elegance)
        let mid = CGPoint(
            x: (fromAttach.x + toAttach.x) / 2,
            y: (fromAttach.y + toAttach.y) / 2 - 12
        )
        let endX = fromAttach.x + (toAttach.x - fromAttach.x) * progress
        let endY = fromAttach.y + (toAttach.y - fromAttach.y) * progress
        let endPoint = CGPoint(x: endX, y: endY)

        var path = Path()
        path.move(to: fromAttach)
        path.addQuadCurve(to: endPoint, control: mid)
        context.stroke(path, with: .color(.yellow.opacity(0.55)), lineWidth: 1.2)

        // Arrowhead when fully drawn
        if progress > 0.93 {
            let head: CGFloat = 7
            var headPath = Path()
            headPath.move(to: toAttach)
            headPath.addLine(to: CGPoint(x: toAttach.x + head, y: toAttach.y - head / 2))
            headPath.addLine(to: CGPoint(x: toAttach.x + head, y: toAttach.y + head / 2))
            headPath.closeSubpath()
            context.fill(headPath, with: .color(.yellow.opacity(0.85)))
        }
    }

    // MARK: - Card

    private func drawCard(
        context: inout GraphicsContext,
        at pos: CGPoint,
        vertex: VertexData,
        parents: [String],
        isRoot: Bool,
        entry: Double,
        crack: Double
    ) {
        if entry <= 0.001 { return }

        let scale = 0.85 + 0.15 * entry
        let alpha = entry
        let w = cardWidth * scale
        let h = cardHeight * scale
        let rect = CGRect(x: pos.x - w / 2, y: pos.y - h / 2, width: w, height: h)

        let nodeColor = self.nodeColor(for: vertex.processIdHex)
        let closedA = (1 - crack) * alpha
        let openA = crack * alpha
        let isGenesis = parents.isEmpty || vertex.round == 0

        // Glow halo for the root vertex
        if isRoot {
            let halo = rect.insetBy(dx: -16, dy: -16)
            context.fill(
                RoundedRectangle(cornerRadius: 22).path(in: halo),
                with: .color(.cyan.opacity(0.10 * alpha))
            )
        }

        // Card body
        context.fill(
            RoundedRectangle(cornerRadius: 12).path(in: rect),
            with: .color(.black.opacity(0.88 * alpha))
        )
        context.stroke(
            RoundedRectangle(cornerRadius: 12).path(in: rect),
            with: .color(nodeColor.opacity((isRoot ? 0.95 : 0.65) * alpha)),
            lineWidth: isRoot ? 2.0 : 1.3
        )

        // ── SEALED state ──
        if closedA > 0.01 {
            let bgRect = rect.insetBy(dx: 1, dy: 1)
            context.fill(
                RoundedRectangle(cornerRadius: 11).path(in: bgRect),
                with: .linearGradient(
                    Gradient(colors: [
                        nodeColor.opacity(0.22 * closedA),
                        Color.black.opacity(0)
                    ]),
                    startPoint: bgRect.origin,
                    endPoint: CGPoint(x: bgRect.maxX, y: bgRect.maxY)
                )
            )
            // "Wax seal" emblem
            let sealR: CGFloat = 16
            let sealRect = CGRect(
                x: rect.midX - sealR,
                y: rect.midY - sealR + 4,
                width: sealR * 2, height: sealR * 2
            )
            context.fill(Circle().path(in: sealRect), with: .color(nodeColor.opacity(0.85 * closedA)))
            context.stroke(
                Circle().path(in: sealRect.insetBy(dx: 4, dy: 4)),
                with: .color(.black.opacity(0.55 * closedA)),
                lineWidth: 1.2
            )
            context.draw(
                Text("⌬")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundColor(.black.opacity(0.7 * closedA)),
                at: CGPoint(x: sealRect.midX, y: sealRect.midY)
            )
            // Digest prefix at top of sealed card
            context.draw(
                Text("0x\(String(vertex.digestHex.prefix(10)))")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.96 * closedA)),
                at: CGPoint(x: rect.midX, y: rect.minY + 18)
            )
            context.draw(
                Text("SEALED MESSAGE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45 * closedA))
                    .kerning(1.5),
                at: CGPoint(x: rect.midX, y: rect.maxY - 14)
            )

            // Crack lines during the cross-fade window
            if crack > 0.05 && crack < 0.95 {
                let intensity = sin(crack * .pi)
                var crackPath = Path()
                let y1 = rect.minY + h * 0.42
                crackPath.move(to: CGPoint(x: rect.minX + 10, y: y1 + 2))
                crackPath.addLine(to: CGPoint(x: rect.midX - 10, y: y1 - 4))
                crackPath.addLine(to: CGPoint(x: rect.midX + 8, y: y1 + 5))
                crackPath.addLine(to: CGPoint(x: rect.maxX - 10, y: y1 - 1))
                context.stroke(
                    crackPath,
                    with: .color(.white.opacity(0.85 * intensity)),
                    lineWidth: 1.4
                )
            }
        }

        // ── OPEN state ──
        if openA > 0.01 {
            let inner = rect.insetBy(dx: 12, dy: 10)
            var y = inner.minY + 10

            // Header row: digest prefix + round badge
            context.draw(
                Text("0x\(String(vertex.digestHex.prefix(10)))")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.96 * openA)),
                at: CGPoint(x: inner.minX + 50, y: y)
            )
            // Round badge
            let badgeW: CGFloat = 38
            let badgeH: CGFloat = 16
            let badge = CGRect(
                x: inner.maxX - badgeW,
                y: y - badgeH / 2,
                width: badgeW, height: badgeH
            )
            context.fill(
                RoundedRectangle(cornerRadius: 4).path(in: badge),
                with: .color(nodeColor.opacity(0.55 * openA))
            )
            context.draw(
                Text("R\(vertex.round)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95 * openA)),
                at: CGPoint(x: badge.midX, y: badge.midY)
            )
            y += 14

            // Origin row
            let nodeName = dm.sim?.nodes.first(where: { $0.processIdHex == vertex.processIdHex })?.name ?? "?"
            context.draw(
                Text("origin \(nodeName)  ·  weight \(vertex.weight)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(nodeColor.opacity(0.85 * openA)),
                at: CGPoint(x: inner.midX, y: y + 4)
            )
            y += 16

            // PAYLOAD section
            let payloadH: CGFloat = 32
            let payloadRect = CGRect(x: inner.minX, y: y, width: inner.width, height: payloadH)
            context.fill(
                RoundedRectangle(cornerRadius: 5).path(in: payloadRect),
                with: .color(.cyan.opacity(0.14 * openA))
            )
            context.stroke(
                RoundedRectangle(cornerRadius: 5).path(in: payloadRect),
                with: .color(.cyan.opacity(0.45 * openA)),
                lineWidth: 0.8
            )
            context.draw(
                Text("PAYLOAD")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.75 * openA))
                    .kerning(1.2),
                at: CGPoint(x: payloadRect.minX + 26, y: payloadRect.minY + 7)
            )
            context.draw(
                Text(syntheticTx(for: vertex))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.96 * openA)),
                at: CGPoint(x: payloadRect.midX, y: payloadRect.midY + 5)
            )
            y += payloadH + 6

            // PARENTS section
            if isGenesis {
                let gen = CGRect(x: inner.minX, y: y, width: inner.width, height: 22)
                context.fill(
                    RoundedRectangle(cornerRadius: 5).path(in: gen),
                    with: .color(.yellow.opacity(0.18 * openA))
                )
                context.draw(
                    Text("★ GENESIS · NO PRE-IMAGE ★")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.95 * openA))
                        .kerning(1.0),
                    at: CGPoint(x: gen.midX, y: gen.midY)
                )
            } else {
                context.draw(
                    Text("PARENT HASHES")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.7 * openA))
                        .kerning(1.2),
                    at: CGPoint(x: inner.minX + 40, y: y + 4)
                )
                y += 12
                let parentDisplay = parents.prefix(maxParentsPerCard)
                for ph in parentDisplay {
                    let chip = CGRect(x: inner.minX, y: y, width: inner.width, height: 13)
                    context.fill(
                        RoundedRectangle(cornerRadius: 3).path(in: chip),
                        with: .color(.yellow.opacity(0.10 * openA))
                    )
                    context.stroke(
                        RoundedRectangle(cornerRadius: 3).path(in: chip),
                        with: .color(.yellow.opacity(0.40 * openA)),
                        lineWidth: 0.5
                    )
                    context.draw(
                        Text("→ 0x\(String(ph.prefix(12)))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.88 * openA)),
                        at: CGPoint(x: chip.midX, y: chip.midY)
                    )
                    y += 15
                }
            }
        }
    }

    // MARK: - Helpers

    private func syntheticTx(for v: VertexData) -> String {
        // Deterministic synthetic transaction synthesised from the digest, so the
        // user sees concrete "real data" rather than abstract placeholders.
        let s = v.digestHex
        let send = String(s.prefix(4))
        let rec = String(s.dropFirst(4).prefix(4))
        var hash: UInt64 = 5381
        for ch in s.utf8 { hash = hash &* 33 &+ UInt64(ch) }
        let amt = (hash % 99) + 1
        return "Tx: 0x\(send) ⇒ 0x\(rec) · \(amt) coins"
    }

    private func nodeColor(for processIdHex: String) -> Color {
        let idx = dm.sim?.nodes.firstIndex(where: { $0.processIdHex == processIdHex }) ?? 0
        return DataManager.palette[min(idx, DataManager.palette.count - 1)]
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, v))
    }
}
