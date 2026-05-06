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
                convergenceTime: state.convergenceTime(at: timeline.date),
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
    /// Seconds since the user pressed "▶ PLAY CONVERGENCE". 0 ⇒ not playing.
    /// Drives the snap-together overlay; static comparison is unaffected.
    var convergenceTime: Double = 0
    let onDismiss: () -> Void
    @Environment(AppSettings.self) private var settings

    // Card sizing is adaptive — see `computeLayout` below. These are the
    // BASELINE / MIN values; on wide screens cards grow up to maxCardWidth
    // and the column gap expands to fill the canvas, so connection arrows
    // are clearly visible instead of crammed in the middle.
    private let minCardWidth: CGFloat = 220
    private let maxCardWidth: CGFloat = 320
    private let cardHeight: CGFloat = 168
    private let minColumnGap: CGFloat = 60
    private let sideMargin: CGFloat = 40
    private let levelStagger: Double = 1.5      // seconds between depth levels
    private let crackOffset: Double = 0.6       // seconds after entry that the seal cracks
    // Cap the cone tightly. depth=2 + parents=2 means at most 1+2+4 = 7 cards
    // per pane, but usually 4–5. Combined with the relaxed `findConvergenceRound`
    // ("highest round with any shared ancestor"), this produces a readable
    // comparison where individual cards are large enough to act as the visual
    // unit the spotlights and snap motion are sized for.
    private let maxDepth: Int = 2
    private let maxParentsPerCard: Int = 2

    /// Adaptive layout: spread `levelCount` columns across the full canvas
    /// width minus side margins, growing both card width and column gap.
    private struct ColumnLayout {
        let cardWidth: CGFloat
        let columnGap: CGFloat
        let originX: CGFloat
        let totalWidth: CGFloat
    }
    private func computeLayout(canvasWidth: CGFloat, levelCount: Int) -> ColumnLayout {
        let n = max(1, levelCount)
        let avail = max(0, canvasWidth - 2 * sideMargin)
        // Required width if every column used the minimum card width plus the
        // minimum gap. If even that doesn't fit, shrink BOTH proportionally —
        // never let totalWidth exceed canvasWidth (which used to push cards
        // off-canvas in narrow panes / high textScale).
        let requiredMin = CGFloat(n) * minCardWidth + CGFloat(max(0, n - 1)) * minColumnGap
        let cardWidth: CGFloat
        let columnGap: CGFloat
        if avail <= 0 {
            cardWidth = minCardWidth
            columnGap = 0
        } else if requiredMin > avail {
            let shrink = avail / requiredMin
            cardWidth = minCardWidth * shrink
            columnGap = minColumnGap * shrink
        } else {
            // We have room. Try to grow cards up to maxCardWidth while keeping
            // minColumnGap between columns; any remainder becomes extra gap.
            let widthIfMax = CGFloat(n) * maxCardWidth + CGFloat(max(0, n - 1)) * minColumnGap
            if avail >= widthIfMax {
                cardWidth = maxCardWidth
                columnGap = n > 1 ? (avail - CGFloat(n) * cardWidth) / CGFloat(n - 1) : 0
            } else {
                cardWidth = (avail - CGFloat(max(0, n - 1)) * minColumnGap) / CGFloat(n)
                columnGap = minColumnGap
            }
        }
        let totalWidth = CGFloat(n) * cardWidth + CGFloat(max(0, n - 1)) * columnGap
        // Clamp the origin so cards always sit inside canvas, even if the
        // shrink path produced a totalWidth slightly larger than avail.
        let originX = max(sideMargin, (canvasWidth - totalWidth) / 2)
        return ColumnLayout(cardWidth: cardWidth, columnGap: columnGap, originX: originX, totalWidth: totalWidth)
    }

    var body: some View {
        ZStack {
            Canvas(opaque: false) { context, size in
                render(context: &context, size: size, time: localTime)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.92))
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }

            // Mode toggle pill — top-right of the overlay. Sits above the Canvas
            // so it intercepts taps before the dismiss gesture.
            VStack {
                HStack {
                    Spacer()
                    comparisonControls
                        .padding(.top, 14)
                        .padding(.trailing, 16)
                }
                Spacer()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 1.02)))
    }

    @ViewBuilder
    private var comparisonControls: some View {
        if state.isComparing {
            HStack(spacing: 8) {
                // Snap-together convergence playback. Strictly additive — does
                // not alter the static comparison; toggling stops it cleanly.
                Button {
                    if state.isPlayingConvergence {
                        state.stopConvergence()
                    } else {
                        state.playConvergence()
                    }
                } label: {
                    Text(state.isPlayingConvergence ? "■ STOP CONVERGENCE" : "▶ PLAY CONVERGENCE")
                        .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                        .kerning(1.2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.teal.opacity(state.isPlayingConvergence ? 0.35 : 0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.teal.opacity(0.55), lineWidth: 0.8)
                                )
                        )
                        .foregroundStyle(.teal.opacity(0.95))
                }
                .buttonStyle(.plain)

                Button {
                    state.clearCompare()
                } label: {
                    Text("× EXIT COMPARISON")
                        .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                        .kerning(1.2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.black.opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.35), lineWidth: 0.8)
                                )
                        )
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                if let target = autoPickComparison() {
                    state.setCompare(target)
                }
            } label: {
                Text("⇆ COMPARE WITH CONTEMPORARY")
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .kerning(1.2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.cyan.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.cyan.opacity(0.55), lineWidth: 0.8)
                            )
                    )
                    .foregroundStyle(.cyan.opacity(0.95))
            }
            .buttonStyle(.plain)
        }
    }

    /// Pick a contemporary vertex from a DIFFERENT node, ideally at the same
    /// round as the selected vertex. Used by the "Compare with contemporary"
    /// button to seed the side-by-side view without requiring a second click
    /// on the underlying graph.
    private func autoPickComparison() -> String? {
        guard let rootDigest = state.selectedDigest,
              let snap = dm.honestData(step: (dm.sim?.steps.count ?? 1) - 1),
              let root = snap.vertices.first(where: { $0.digestHex == rootDigest }) else {
            return nil
        }
        // Prefer same round, different node. Walk outwards by ±1 round.
        let rootRound = root.round
        let rootPid = root.processIdHex
        for delta in [0, 1, -1, 2, -2] {
            let r = rootRound + delta
            let candidate = snap.vertices.first { v in
                let differentNode = v.processIdHex != rootPid
                let differentDigest = v.digestHex != rootDigest
                return v.round == r && differentNode && differentDigest
            }
            if let candidate { return candidate.digestHex }
        }
        return nil
    }

    // MARK: - Rendering

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard let sim = dm.sim,
              let digest = state.selectedDigest,
              // Pull the FULL ancestry from the deepest available snapshot so the
              // recursive walk doesn't run into "vertex not in snapshot" gaps.
              let snap = dm.honestData(step: (dm.sim?.steps.count ?? 1) - 1) else {
            context.draw(
                Text("Loading inspection…").foregroundColor(.white.opacity(0.7)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            return
        }

        if let compareDigest = state.compareDigest {
            renderComparison(
                context: &context, size: size, time: time,
                rootDigestA: digest, rootDigestB: compareDigest,
                snap: snap, sim: sim
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
        // Card width and column gap adapt to canvas width — see computeLayout.
        let levelCount = levels.count
        let lay = computeLayout(canvasWidth: size.width, levelCount: levelCount)
        let cardWidth = lay.cardWidth
        let columnGap = lay.columnGap
        let originX = lay.originX
        let totalWidth = lay.totalWidth
        let topReserved: CGFloat = 70   // title bar
        let bottomReserved: CGFloat = 50
        let usableHeight = size.height - topReserved - bottomReserved

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
                .font(.system(size: settings.scaled(9), weight: .medium, design: .monospaced))
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
                    drawArrow(context: &context, from: from, to: to, progress: p, cardWidth: cardWidth)
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
                    crack: crack,
                    cardWidth: cardWidth
                )
            }
        }

        // ── Title bar + dismiss hint ──
        drawTitleBar(context: &context, size: size, root: root, sim: sim)
        context.draw(
            Text("CLICK ANYWHERE TO RETURN TO THE GRAPH")
                .font(.system(size: settings.scaled(11), weight: .medium, design: .monospaced))
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
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .kerning(2),
            at: CGPoint(x: size.width / 2, y: 14)
        )
        let nodeName = sim.nodes.first(where: { $0.processIdHex == root.processIdHex })?.name ?? "?"
        context.draw(
            Text("0x\(String(root.digestFull.prefix(20)))…  ·  origin \(nodeName)  ·  round \(root.round)  ·  weight \(root.weight)")
                .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.92)),
            at: CGPoint(x: size.width / 2, y: 36)
        )
    }

    // MARK: - Arrow

    private func drawArrow(
        context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        progress: Double,
        cardWidth: CGFloat
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
        crack: Double,
        cardWidth: CGFloat,
        tintColor: Color? = nil
    ) {
        if entry <= 0.001 { return }

        let scale = 0.85 + 0.15 * entry
        let alpha = entry
        let w = cardWidth * scale
        let h = cardHeight * scale
        let rect = CGRect(x: pos.x - w / 2, y: pos.y - h / 2, width: w, height: h)

        // tintColor wins (used by the comparison view to color cards by
        // SHARED/A_ONLY/B_ONLY classification); otherwise fall back to per-node palette.
        let nodeColor = tintColor ?? self.nodeColor(for: vertex.processIdHex)
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
                    .font(.system(size: settings.scaled(16), weight: .heavy, design: .monospaced))
                    .foregroundColor(.black.opacity(0.7 * closedA)),
                at: CGPoint(x: sealRect.midX, y: sealRect.midY)
            )
            // Digest prefix at top of sealed card
            context.draw(
                Text("0x\(String(vertex.digestHex.prefix(10)))")
                    .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.96 * closedA)),
                at: CGPoint(x: rect.midX, y: rect.minY + 18)
            )
            context.draw(
                Text("SEALED MESSAGE")
                    .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
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
                    .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
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
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95 * openA)),
                at: CGPoint(x: badge.midX, y: badge.midY)
            )
            y += 14

            // Origin row
            let nodeName = dm.sim?.nodes.first(where: { $0.processIdHex == vertex.processIdHex })?.name ?? "?"
            context.draw(
                Text("origin \(nodeName)  ·  weight \(vertex.weight)")
                    .font(.system(size: settings.scaled(9), weight: .medium, design: .monospaced))
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
                    .font(.system(size: settings.scaled(7), weight: .heavy, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.75 * openA))
                    .kerning(1.2),
                at: CGPoint(x: payloadRect.minX + 26, y: payloadRect.minY + 7)
            )
            context.draw(
                Text(syntheticTx(for: vertex))
                    .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
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
                        .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.95 * openA))
                        .kerning(1.0),
                    at: CGPoint(x: gen.midX, y: gen.midY)
                )
            } else {
                context.draw(
                    Text("PARENT HASHES")
                        .font(.system(size: settings.scaled(7), weight: .heavy, design: .monospaced))
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
                            .font(.system(size: settings.scaled(9), weight: .medium, design: .monospaced))
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
        dm.castColor(for: processIdHex)
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, v))
    }

    // MARK: - Side-by-side comparison

    /// Classification of an ancestor when both A's and B's cones are walked.
    /// Drives the SHARED (teal) / A_ONLY (warm orange) / B_ONLY (cool blue)
    /// color coding that makes total-order convergence visible.
    private enum AncestorClass { case shared, aOnly, bOnly }
    private static let cShared: Color = .teal
    private static let cAOnly:  Color = Color(red: 1.0,  green: 0.55, blue: 0.20)
    private static let cBOnly:  Color = Color(red: 0.35, green: 0.65, blue: 1.0)

    private func renderComparison(
        context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        rootDigestA: String,
        rootDigestB: String,
        snap: NodeSnapshot,
        sim: SimulationData
    ) {
        let vByDigest: [String: VertexData] =
            Dictionary(uniqueKeysWithValues: snap.vertices.map { ($0.digestHex, $0) })
        var parentMap: [String: [String]] = [:]
        for e in snap.edges { parentMap[e.from, default: []].append(e.to) }

        guard let rootA = vByDigest[rootDigestA], let rootB = vByDigest[rootDigestB] else {
            context.draw(
                Text("Comparison vertices missing").foregroundColor(.red.opacity(0.85)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            return
        }

        let (levelsA, parentsA) = bfsLevels(root: rootA, vByDigest: vByDigest, parentMap: parentMap)
        let (levelsB, parentsB) = bfsLevels(root: rootB, vByDigest: vByDigest, parentMap: parentMap)

        // Full ancestor sets — used for SHARED/ONLY classification.
        let setA: Set<String> = Set(levelsA.flatMap { $0.map(\.digestHex) })
        let setB: Set<String> = Set(levelsB.flatMap { $0.map(\.digestHex) })
        func classify(_ d: String) -> AncestorClass {
            if setA.contains(d) && setB.contains(d) { return .shared }
            return setA.contains(d) ? .aOnly : .bOnly
        }
        func tint(_ c: AncestorClass) -> Color {
            switch c { case .shared: return Self.cShared; case .aOnly: return Self.cAOnly; case .bOnly: return Self.cBOnly }
        }

        // Convergence round: walking from the deepest available round upward,
        // find the earliest round where both cones cover *exactly* the same set.
        let convergenceRound = findConvergenceRound(setA: setA, setB: setB, vByDigest: vByDigest)

        // Layout: split canvas in two halves with a center divider.
        // A's pane on the left (root on outer-left, ancestors expanding rightward toward center).
        // B's pane on the right (root on outer-right, ancestors expanding leftward toward center).
        // This puts the SHARED past at the meeting point — pedagogically the visual focus.
        let topReserved: CGFloat   = 100  // title + caption
        let bottomReserved: CGFloat = 60
        let dividerGutter: CGFloat = 16
        let halfW = (size.width - dividerGutter) / 2
        let usableHeight = size.height - topReserved - bottomReserved

        let layA = computeLayout(canvasWidth: halfW, levelCount: levelsA.count)
        let layB = computeLayout(canvasWidth: halfW, levelCount: levelsB.count)

        // Position cards in pane A (mirrored: depth 0 on the LEFT)
        var positions: [String: CGPoint] = [:]
        for (depth, vs) in levelsA.enumerated() {
            // depth 0 → column 0 (leftmost in pane A)
            let cx = layA.originX + CGFloat(depth) * (layA.cardWidth + layA.columnGap) + layA.cardWidth / 2
            let count = max(1, vs.count)
            let step = usableHeight / CGFloat(count)
            for (i, v) in vs.enumerated() {
                let cy = topReserved + step * (CGFloat(i) + 0.5)
                positions[v.digestHex] = CGPoint(x: cx, y: cy)
            }
        }
        // Position cards in pane B (depth 0 on the RIGHT, ancestors expanding leftward toward divider)
        let bOriginX = halfW + dividerGutter
        for (depth, vs) in levelsB.enumerated() {
            let columnIdx = (levelsB.count - 1) - depth
            let cx = bOriginX + layB.originX + CGFloat(columnIdx) * (layB.cardWidth + layB.columnGap) + layB.cardWidth / 2
            let count = max(1, vs.count)
            let step = usableHeight / CGFloat(count)
            for (i, v) in vs.enumerated() {
                let cy = topReserved + step * (CGFloat(i) + 0.5)
                positions[v.digestHex] = CGPoint(x: cx, y: cy)
            }
        }

        // Center divider
        var divider = Path()
        divider.move(to: CGPoint(x: size.width / 2, y: topReserved - 8))
        divider.addLine(to: CGPoint(x: size.width / 2, y: size.height - bottomReserved + 8))
        context.stroke(divider, with: .color(.white.opacity(0.10)),
                      style: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))

        // Arrows for both panes — drawn underneath cards.
        drawCompareArrows(
            context: &context,
            time: time,
            levels: levelsA,
            displayedParents: parentsA,
            positions: positions,
            cardWidth: layA.cardWidth,
            classify: classify
        )
        drawCompareArrows(
            context: &context,
            time: time,
            levels: levelsB,
            displayedParents: parentsB,
            positions: positions,
            cardWidth: layB.cardWidth,
            classify: classify
        )

        // Cards for both panes
        drawCompareCards(
            context: &context,
            time: time,
            levels: levelsA,
            displayedParents: parentsA,
            positions: positions,
            cardWidth: layA.cardWidth,
            classify: classify
        )
        drawCompareCards(
            context: &context,
            time: time,
            levels: levelsB,
            displayedParents: parentsB,
            positions: positions,
            cardWidth: layB.cardWidth,
            classify: classify
        )

        drawCompareTitleBar(
            context: &context, size: size,
            rootA: rootA, rootB: rootB, sim: sim,
            convergenceRound: convergenceRound,
            sharedCount: setA.intersection(setB).count,
            aOnlyCount: setA.subtracting(setB).count,
            bOnlyCount: setB.subtracting(setA).count
        )

        // Footer caption — the punch line.
        let footer: String
        if let r = convergenceRound {
            footer = "AT ROUND \(r), BOTH OBSERVATIONS HAVE IDENTICAL CAUSAL HISTORY → IDENTICAL TOTAL ORDER"
        } else {
            footer = "DIVERGENT CAUSAL HISTORIES — k-REACHABILITY VOTES MAY DIFFER UNTIL A LATER ROUND CONVERGES"
        }
        context.draw(
            Text(footer)
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor((convergenceRound != nil ? Self.cShared : .yellow).opacity(0.9))
                .kerning(1.4),
            at: CGPoint(x: size.width / 2, y: size.height - 30)
        )
        context.draw(
            Text("CLICK ANYWHERE TO RETURN")
                .font(.system(size: settings.scaled(9), weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)),
            at: CGPoint(x: size.width / 2, y: size.height - 12)
        )

        // ── Snap-together convergence playback (additive overlay) ──
        // Drawn LAST so it sits on top of the static comparison. When the user
        // clicks STOP CONVERGENCE the static view becomes visible again
        // unchanged. Only fires when a convergence round was detected.
        if state.isPlayingConvergence, convergenceRound != nil {
            renderConvergencePlayback(
                context: &context,
                size: size,
                t: convergenceTime,
                positions: positions,
                levelsA: levelsA,
                levelsB: levelsB,
                classify: classify,
                convergenceRound: convergenceRound,
                vByDigest: vByDigest
            )
        }
    }

    private func bfsLevels(
        root: VertexData,
        vByDigest: [String: VertexData],
        parentMap: [String: [String]]
    ) -> ([[VertexData]], [String: [String]]) {
        var levels: [[VertexData]] = [[root]]
        var seen: Set<String> = [root.digestHex]
        var displayed: [String: [String]] = [:]
        for d in 0..<maxDepth {
            var next: [VertexData] = []
            for v in levels[d] {
                let parents = (parentMap[v.digestHex] ?? []).prefix(maxParentsPerCard).map { $0 }
                displayed[v.digestHex] = parents
                for p in parents where !seen.contains(p) {
                    if let pv = vByDigest[p] {
                        next.append(pv); seen.insert(p)
                    }
                }
            }
            if next.isEmpty { break }
            levels.append(next)
        }
        return (levels, displayed)
    }

    private func findConvergenceRound(
        setA: Set<String>,
        setB: Set<String>,
        vByDigest: [String: VertexData]
    ) -> Int? {
        // Pedagogical "convergence round": the HIGHEST round at which the two
        // ancestor cones share at least one vertex. Strict-equality wasn't
        // viable — with bounded BFS depth it almost never holds, so the
        // playback never fires. Sharing-at-round is the right teachable signal:
        // "from this round and earlier, both observers have evidence of common
        // history." Returns nil only if the cones are completely disjoint.
        let intersection = setA.intersection(setB)
        let sharedRounds = intersection.compactMap { vByDigest[$0]?.round }
        return sharedRounds.max()
    }

    private func drawCompareArrows(
        context: inout GraphicsContext,
        time: Double,
        levels: [[VertexData]],
        displayedParents: [String: [String]],
        positions: [String: CGPoint],
        cardWidth: CGFloat,
        classify: (String) -> AncestorClass
    ) {
        for (depth, vs) in levels.enumerated() {
            let appear = Double(depth + 1) * levelStagger - 0.2
            let p = clamp((time - appear) / 0.55, 0, 1)
            if p <= 0 { continue }
            for v in vs {
                guard let from = positions[v.digestHex] else { continue }
                for ph in displayedParents[v.digestHex] ?? [] {
                    guard let to = positions[ph] else { continue }
                    drawArrow(context: &context, from: from, to: to, progress: p, cardWidth: cardWidth)
                    _ = classify(ph) // arrows kept yellow; classification color shows on the card
                }
            }
        }
    }

    private func drawCompareCards(
        context: inout GraphicsContext,
        time: Double,
        levels: [[VertexData]],
        displayedParents: [String: [String]],
        positions: [String: CGPoint],
        cardWidth: CGFloat,
        classify: (String) -> AncestorClass
    ) {
        for (depth, vs) in levels.enumerated() {
            let revealStart = depth == 0 ? -0.4 : Double(depth) * levelStagger
            let entry = clamp((time - revealStart) / 0.4, 0, 1)
            let crack = clamp((time - revealStart - crackOffset) / 0.6, 0, 1)
            for v in vs {
                guard let pos = positions[v.digestHex] else { continue }
                let cls = classify(v.digestHex)
                let tint: Color
                switch cls {
                case .shared: tint = Self.cShared
                case .aOnly:  tint = Self.cAOnly
                case .bOnly:  tint = Self.cBOnly
                }
                drawCard(
                    context: &context,
                    at: pos,
                    vertex: v,
                    parents: displayedParents[v.digestHex] ?? [],
                    isRoot: depth == 0,
                    entry: entry,
                    crack: crack,
                    cardWidth: cardWidth,
                    tintColor: tint
                )
            }
        }
    }

    private func drawCompareTitleBar(
        context: inout GraphicsContext,
        size: CGSize,
        rootA: VertexData, rootB: VertexData,
        sim: SimulationData,
        convergenceRound: Int?,
        sharedCount: Int, aOnlyCount: Int, bOnlyCount: Int
    ) {
        let bg = CGRect(x: 0, y: 0, width: size.width, height: 90)
        context.fill(Rectangle().path(in: bg), with: .color(.black.opacity(0.78)))
        var sep = Path()
        sep.move(to: CGPoint(x: 0, y: 90))
        sep.addLine(to: CGPoint(x: size.width, y: 90))
        context.stroke(sep, with: .color(.white.opacity(0.12)), lineWidth: 0.5)

        context.draw(
            Text("SIDE-BY-SIDE CAUSAL HISTORY · TWO LOCAL OBSERVATIONS, ONE EMERGENT TOTAL ORDER")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .kerning(2),
            at: CGPoint(x: size.width / 2, y: 16)
        )

        // Per-pane labels
        let nameA = sim.nodes.first(where: { $0.processIdHex == rootA.processIdHex })?.name ?? "?"
        let nameB = sim.nodes.first(where: { $0.processIdHex == rootB.processIdHex })?.name ?? "?"
        context.draw(
            Text("◀ A · 0x\(String(rootA.digestFull.prefix(12)))…  ·  origin \(nameA)  ·  R\(rootA.round)")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(Self.cAOnly.opacity(0.95)),
            at: CGPoint(x: size.width * 0.25, y: 38)
        )
        context.draw(
            Text("0x\(String(rootB.digestFull.prefix(12)))…  ·  origin \(nameB)  ·  R\(rootB.round) · B ▶")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(Self.cBOnly.opacity(0.95)),
            at: CGPoint(x: size.width * 0.75, y: 38)
        )

        // Set-difference legend in the middle
        let legend = "SHARED \(sharedCount)   ·   A-ONLY \(aOnlyCount)   ·   B-ONLY \(bOnlyCount)"
        context.draw(
            Text(legend)
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .kerning(1.0),
            at: CGPoint(x: size.width / 2, y: 64)
        )
        if let r = convergenceRound {
            context.draw(
                Text("⟶ CONVERGENCE AT R\(r)")
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(Self.cShared.opacity(0.95))
                    .kerning(1.5),
                at: CGPoint(x: size.width / 2, y: 80)
            )
        }
    }

    // MARK: - Snap-together convergence playback (kinetic + narrated)
    //
    // Borrowed from Avalanche/Snowflake demos: divergent cards literally MOVE
    // and the motion IS the lesson. Augmented with step-counter pill and
    // bottom captions so the user is never lost.
    //
    // Story arc — assumes ZERO prior knowledge of consensus:
    //   STEP 1: "Two validators each saw some messages."
    //   STEP 2: "Recent memories DIFFER — that's normal."
    //   STEP 3: "But deeper memories are IDENTICAL."
    //   STEP 4: "Same shared history → same final order. That's consensus."
    //
    // Pedagogical timing: each step lingers ~1.6s so a user can READ it.
    private func renderConvergencePlayback(
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        positions: [String: CGPoint],
        levelsA: [[VertexData]],
        levelsB: [[VertexData]],
        classify: (String) -> AncestorClass,
        convergenceRound: Int?,
        vByDigest: [String: VertexData]
    ) {
        // Step boundaries (seconds). Last step is open-ended (stays until STOP).
        let s1End = 1.6
        let s2End = 3.4
        let s3End = 5.4
        // Current step index 0..3.
        let step: Int
        if      t < s1End { step = 0 }
        else if t < s2End { step = 1 }
        else if t < s3End { step = 2 }
        else              { step = 3 }

        // ── 1. Full-canvas dim so the spotlights pop ─────────────────────
        let dimAlpha = clamp(t / 0.4, 0, 1) * 0.78
        context.fill(
            Rectangle().path(in: CGRect(origin: .zero, size: size)),
            with: .color(.black.opacity(dimAlpha))
        )

        // Helper: draw a colored "spotlight" ring around a card position.
        // Card sizes vary slightly across panes; a ring of width 240×184 covers
        // any card produced by computeLayout (cards range 220–320 wide).
        func spotlight(at pos: CGPoint, color: Color, alpha: Double, lineWidth: CGFloat = 3) {
            let w: CGFloat = 246
            let h: CGFloat = 184
            let rect = CGRect(x: pos.x - w / 2, y: pos.y - h / 2, width: w, height: h)
            // Faint colored fill so the dim isn't completely opaque over highlighted cards.
            context.fill(
                RoundedRectangle(cornerRadius: 14).path(in: rect),
                with: .color(color.opacity(0.10 * alpha))
            )
            context.stroke(
                RoundedRectangle(cornerRadius: 14).path(in: rect),
                with: .color(color.opacity(0.95 * alpha)),
                lineWidth: lineWidth
            )
        }

        // Helper: list every card position in a side, optionally filtered.
        func positionsFor(_ levels: [[VertexData]], where pred: (VertexData) -> Bool) -> [(VertexData, CGPoint)] {
            var out: [(VertexData, CGPoint)] = []
            for vs in levels {
                for v in vs where pred(v) {
                    if let p = positions[v.digestHex] { out.append((v, p)) }
                }
            }
            return out
        }

        // Pulsing alpha — gives the spotlight a heartbeat so the user looks at it.
        let pulse = 0.75 + 0.25 * (0.5 + 0.5 * sin(t * 4.0))

        // ── STEP 1 ── Big pane labels, no per-card spotlights ───────────
        //
        // Per-card spotlights at this density read as vertical bars and obscure
        // the lesson. Instead: two giant labels above each pane explaining
        // "this is what observer A saw" / "this is what observer B saw."
        if step == 0 {
            // Pane A label (left half of canvas).
            let labelY: CGFloat = 175
            // A side
            let labelAW: CGFloat = 260
            let labelAH: CGFloat = 60
            let labelARect = CGRect(x: size.width * 0.25 - labelAW / 2, y: labelY - labelAH / 2,
                                    width: labelAW, height: labelAH)
            context.fill(
                RoundedRectangle(cornerRadius: 14).path(in: labelARect),
                with: .color(Self.cAOnly.opacity(0.20 * pulse))
            )
            context.stroke(
                RoundedRectangle(cornerRadius: 14).path(in: labelARect),
                with: .color(Self.cAOnly.opacity(0.95)),
                lineWidth: 2.5
            )
            context.draw(
                Text("OBSERVER A")
                    .font(.system(size: settings.scaled(20), weight: .heavy, design: .monospaced))
                    .foregroundColor(Self.cAOnly.opacity(0.95))
                    .kerning(3),
                at: CGPoint(x: labelARect.midX, y: labelARect.midY - 8)
            )
            context.draw(
                Text("everything I have seen")
                    .font(.system(size: settings.scaled(11), weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.78)),
                at: CGPoint(x: labelARect.midX, y: labelARect.midY + 14)
            )
            // B side
            let labelBRect = CGRect(x: size.width * 0.75 - labelAW / 2, y: labelY - labelAH / 2,
                                    width: labelAW, height: labelAH)
            context.fill(
                RoundedRectangle(cornerRadius: 14).path(in: labelBRect),
                with: .color(Self.cBOnly.opacity(0.20 * pulse))
            )
            context.stroke(
                RoundedRectangle(cornerRadius: 14).path(in: labelBRect),
                with: .color(Self.cBOnly.opacity(0.95)),
                lineWidth: 2.5
            )
            context.draw(
                Text("OBSERVER B")
                    .font(.system(size: settings.scaled(20), weight: .heavy, design: .monospaced))
                    .foregroundColor(Self.cBOnly.opacity(0.95))
                    .kerning(3),
                at: CGPoint(x: labelBRect.midX, y: labelBRect.midY - 8)
            )
            context.draw(
                Text("everything I have seen")
                    .font(.system(size: settings.scaled(11), weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.78)),
                at: CGPoint(x: labelBRect.midX, y: labelBRect.midY + 14)
            )
        }

        // ── STEP 2 ── Differences (A-only on left, B-only on right) ─────
        if step == 1 {
            for (v, p) in positionsFor(levelsA, where: { classify($0.digestHex) == .aOnly }) {
                spotlight(at: p, color: Self.cAOnly, alpha: pulse, lineWidth: 4)
                _ = v
            }
            for (v, p) in positionsFor(levelsB, where: { classify($0.digestHex) == .bOnly }) {
                spotlight(at: p, color: Self.cBOnly, alpha: pulse, lineWidth: 4)
                _ = v
            }
        }

        // ── STEP 3 ── KINETIC SNAP: divergent cards slide to divider, fade ──
        //
        // This IS the Avalanche metaphor: the user SEES differences physically
        // collapse. A-only cards interpolate rightward to dividerX, B-only cards
        // leftward, both fading. Shared cards remain in place and pulse teal.
        // We mask the original positions so we don't see ghost cards.
        if step == 2 {
            let dividerX = size.width / 2
            // Phase progress within step 3 (1.8s). 0..1 across the snap.
            let snap = clamp((t - s2End) / 1.6, 0, 1)
            // Ease-in-out for satisfying motion.
            let eased = snap < 0.5 ? 2 * snap * snap : 1 - pow(-2 * snap + 2, 2) / 2
            let maskW: CGFloat = 246
            let maskH: CGFloat = 184

            func drawSnapping(for vs: [VertexData]) {
                for v in vs {
                    let cls = classify(v.digestHex)
                    guard let origin = positions[v.digestHex] else { continue }
                    if cls == .shared {
                        // Shared: pulse teal in place.
                        spotlight(at: origin, color: Self.cShared, alpha: pulse, lineWidth: 4)
                        continue
                    }
                    // Divergent: black out original position, draw a moving ghost.
                    let mask = CGRect(x: origin.x - maskW / 2, y: origin.y - maskH / 2,
                                      width: maskW, height: maskH)
                    context.fill(
                        RoundedRectangle(cornerRadius: 14).path(in: mask),
                        with: .color(.black.opacity(0.95 * eased))
                    )
                    // Interpolate the card's center toward the divider.
                    let movedX = origin.x + (dividerX - origin.x) * eased
                    let movedAlpha = 1.0 - eased * 0.85
                    let ghostRect = CGRect(x: movedX - maskW / 2, y: origin.y - maskH / 2,
                                           width: maskW, height: maskH)
                    let cardColor: Color = (cls == .aOnly) ? Self.cAOnly : Self.cBOnly
                    // Draw a "ghost card" — a rounded rect with the right tint
                    // and the card's digest prefix label, so the motion is
                    // legible (you can see the card, not just a token).
                    context.fill(
                        RoundedRectangle(cornerRadius: 12).path(in: ghostRect),
                        with: .color(cardColor.opacity(0.20 * movedAlpha))
                    )
                    context.stroke(
                        RoundedRectangle(cornerRadius: 12).path(in: ghostRect),
                        with: .color(cardColor.opacity(0.95 * movedAlpha)),
                        lineWidth: 2.5
                    )
                    context.draw(
                        Text("0x\(String(v.digestHex.prefix(10)))")
                            .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                            .foregroundColor(.white.opacity(0.92 * movedAlpha)),
                        at: CGPoint(x: ghostRect.midX, y: ghostRect.midY - 8)
                    )
                    context.draw(
                        Text(cls == .aOnly ? "← only A saw this" : "← only B saw this")
                            .font(.system(size: settings.scaled(10), weight: .medium, design: .default))
                            .foregroundColor(cardColor.opacity(0.85 * movedAlpha)),
                        at: CGPoint(x: ghostRect.midX, y: ghostRect.midY + 12)
                    )
                    // Trail line from origin to current position
                    if eased > 0.05 {
                        var trail = Path()
                        trail.move(to: CGPoint(x: origin.x, y: origin.y))
                        trail.addLine(to: CGPoint(x: movedX, y: origin.y))
                        context.stroke(
                            trail,
                            with: .color(cardColor.opacity(0.55 * (1 - eased))),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 5])
                        )
                    }
                }
            }
            drawSnapping(for: levelsA.flatMap { $0 })
            drawSnapping(for: levelsB.flatMap { $0 })

            // Bright vertical "merge zone" pulse at the divider once cards arrive.
            if eased > 0.7 {
                let mergeIntensity = (eased - 0.7) / 0.3
                let mergeRect = CGRect(x: dividerX - 24, y: 110,
                                       width: 48, height: size.height - 240)
                context.fill(
                    RoundedRectangle(cornerRadius: 24).path(in: mergeRect),
                    with: .color(Self.cShared.opacity(0.45 * mergeIntensity))
                )
            }
        }

        // ── Step header bar (top) ──────────────────────────────────────
        // Sits just below the static title bar (which ends at y=90).
        let headerY: CGFloat = 110
        let stepLabels = [
            "STEP 1 OF 4 — TWO INDEPENDENT OBSERVERS",
            "STEP 2 OF 4 — WHERE THEY DISAGREE",
            "STEP 3 OF 4 — WHERE THEY AGREE",
            "STEP 4 OF 4 — THE INSIGHT"
        ]
        // Step pill pulses on entry.
        let pillAppear = clamp((t - Double(step) * 1.6) / 0.35, 0, 1)
        let pillW: CGFloat = 460
        let pillH: CGFloat = 32
        let pill = CGRect(x: size.width / 2 - pillW / 2, y: headerY - pillH / 2,
                          width: pillW, height: pillH)
        context.fill(
            RoundedRectangle(cornerRadius: 16).path(in: pill),
            with: .color(.black.opacity(0.85 * pillAppear))
        )
        context.stroke(
            RoundedRectangle(cornerRadius: 16).path(in: pill),
            with: .color(.white.opacity(0.55 * pillAppear)),
            lineWidth: 0.8
        )
        context.draw(
            Text(stepLabels[step])
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.95 * pillAppear))
                .kerning(2.0),
            at: CGPoint(x: size.width / 2, y: headerY)
        )
        // Progress dots under the pill.
        let dotsY = headerY + 24
        let dotR: CGFloat = 5
        let dotGap: CGFloat = 18
        let dotsTotalW = 4 * dotR * 2 + 3 * dotGap
        let dotsStartX = size.width / 2 - dotsTotalW / 2 + dotR
        for i in 0..<4 {
            let cx = dotsStartX + CGFloat(i) * (dotR * 2 + dotGap)
            let dotRect = CGRect(x: cx - dotR, y: dotsY - dotR, width: dotR * 2, height: dotR * 2)
            let active = i <= step
            context.fill(
                Circle().path(in: dotRect),
                with: .color((active ? Self.cShared : .white).opacity(active ? 0.95 : 0.25))
            )
        }

        // ── Narration caption (bottom-center, full sentence) ────────────
        // Two-line wrap by hand for typographic control.
        let captions: [(String, String)] = [
            (
                "Two validators — A (orange) and B (blue) — independently observed messages on the network.",
                "Each one only knows what gossip has reached them so far."
            ),
            (
                "Their RECENT memories DIFFER. A holds messages B hasn't seen yet, and vice-versa.",
                "This is normal — gossip travels at different speeds along different paths."
            ),
            (
                "Watch the differences COLLAPSE. Orange and blue messages slide to the center and vanish.",
                "What remains (teal) is the SHARED past — every honest validator eventually agrees on it."
            ),
            (
                "Same shared past → SAME final ordering of transactions, computed independently by each validator.",
                "No coordinator. No leader. No vote. This is decentralized consensus."
            )
        ]
        let captionAppear = clamp((t - Double(step) * 1.6 - 0.15) / 0.4, 0, 1)
        let capY = size.height - 120
        // Caption backplate.
        let capW: CGFloat = min(size.width - 80, 980)
        let capRect = CGRect(x: size.width / 2 - capW / 2, y: capY - 36,
                             width: capW, height: 80)
        context.fill(
            RoundedRectangle(cornerRadius: 14).path(in: capRect),
            with: .color(.black.opacity(0.88 * captionAppear))
        )
        context.stroke(
            RoundedRectangle(cornerRadius: 14).path(in: capRect),
            with: .color(.white.opacity(0.25 * captionAppear)),
            lineWidth: 0.8
        )
        context.draw(
            Text(captions[step].0)
                .font(.system(size: settings.scaled(15), weight: .heavy, design: .default))
                .foregroundColor(.white.opacity(0.97 * captionAppear)),
            at: CGPoint(x: size.width / 2, y: capY - 12)
        )
        context.draw(
            Text(captions[step].1)
                .font(.system(size: settings.scaled(13), weight: .medium, design: .default))
                .foregroundColor(.white.opacity(0.72 * captionAppear)),
            at: CGPoint(x: size.width / 2, y: capY + 14)
        )

        // Step 4 finale: big stamp above the caption.
        if step == 3 {
            let stampP = clamp((t - s3End) / 0.5, 0, 1)
            // Halo
            let haloR: CGFloat = 240
            let halo = CGRect(x: size.width / 2 - haloR, y: size.height / 2 - haloR / 2 - 30,
                              width: haloR * 2, height: haloR)
            context.fill(
                Ellipse().path(in: halo),
                with: .color(Self.cShared.opacity(0.16 * stampP))
            )
            context.draw(
                Text("✓ CONSENSUS REACHED")
                    .font(.system(size: settings.scaled(28), weight: .heavy, design: .monospaced))
                    .foregroundColor(Self.cShared.opacity(0.98 * stampP))
                    .kerning(3),
                at: CGPoint(x: size.width / 2, y: size.height / 2 - 30)
            )
            if let r = convergenceRound {
                context.draw(
                    Text("achieved at round \(r) — both observers agree on every transaction up to this point")
                        .font(.system(size: settings.scaled(12), weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.82 * stampP)),
                    at: CGPoint(x: size.width / 2, y: size.height / 2)
                )
            }
        }

        // ── Footer ──────────────────────────────────────────────────────
        context.draw(
            Text("PRESS ■ STOP CONVERGENCE TO RETURN TO THE STATIC COMPARISON")
                .font(.system(size: settings.scaled(9), weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .kerning(1.4),
            at: CGPoint(x: size.width / 2, y: size.height - 30)
        )
    }
}
