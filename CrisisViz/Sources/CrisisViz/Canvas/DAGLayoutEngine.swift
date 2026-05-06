import SwiftUI

/// Computes 2D positions for DAG vertices and provides drawing helpers.
/// Layout: X axis = causal wave zones (by round), Y axis = node lanes with hash-derived jitter.
struct DAGLayout {
    let positions: [String: CGPoint]  // digestHex -> position
    let bounds: CGRect
    let roundBoundaries: [CGFloat]    // x positions of round separators

    // MARK: - Consistent type scale (all monospaced)
    //
    // These are functions, not static lets, so the global text-scale slider
    // (AppSettings.textScale) flows into every Canvas-drawn label. Callers
    // pass `scale: settings.textScale` from the chapter view; drawing methods
    // accept and forward a `textScale` parameter.

    static func fontVertex(scale: Double = 1.0) -> Font  { .system(size: 10 * scale, weight: .medium, design: .monospaced) }
    static func fontCaption(scale: Double = 1.0) -> Font { .system(size: 11 * scale, weight: .bold,   design: .monospaced) }
    static func fontBody(scale: Double = 1.0) -> Font    { .system(size: 12 * scale, weight: .medium, design: .monospaced) }
    static func fontHeading(scale: Double = 1.0) -> Font { .system(size: 14 * scale, weight: .heavy,  design: .monospaced) }
    static func fontTitle(scale: Double = 1.0) -> Font   { .system(size: 16 * scale, weight: .heavy,  design: .monospaced) }

    /// Compute layout for a set of vertices within a given canvas size.
    static func compute(
        vertices: [VertexData],
        edges: [EdgeData],
        nodes: [NodeMeta],
        canvasSize: CGSize,
        margin: CGFloat = 60,
        animationProgress: Double = 1.0,
        subset: Set<String>? = nil
    ) -> DAGLayout {
        let filteredVertices: [VertexData]
        if let subset {
            filteredVertices = vertices.filter { subset.contains($0.digestHex) }
        } else {
            filteredVertices = vertices
        }

        guard !filteredVertices.isEmpty else {
            return DAGLayout(positions: [:], bounds: .zero, roundBoundaries: [])
        }

        // Determine round range
        let rounds = filteredVertices.map { $0.round }
        let minRound = rounds.min() ?? 0
        let maxRound = max(rounds.max() ?? 0, minRound + 1)
        let roundRange = Double(maxRound - minRound)

        // Build node lane index
        var nodeLaneIndex: [String: Int] = [:]
        for (i, node) in nodes.enumerated() {
            nodeLaneIndex[node.processIdHex] = i
        }

        // Extra right margin to prevent clipping (lane labels take space on the left)
        let leftMargin = margin
        let rightMargin = margin + 20
        let usableWidth = canvasSize.width - leftMargin - rightMargin
        let usableHeight = canvasSize.height - margin * 2
        let nodeCount = max(nodes.count, 1)

        // Zone width per round
        let zoneWidth = usableWidth / max(1, CGFloat(roundRange))

        var positions: [String: CGPoint] = [:]
        var roundBounds: [CGFloat] = []

        // Compute round boundaries
        for r in minRound...maxRound {
            let x = leftMargin + CGFloat(Double(r - minRound) / roundRange) * usableWidth
            roundBounds.append(x)
        }

        for vertex in filteredVertices {
            let round = vertex.round
            let laneIdx = nodeLaneIndex[vertex.processIdHex] ?? 0

            // X: zone center + hash-derived jitter
            let zoneCenterX = leftMargin + (CGFloat(Double(round - minRound) + 0.5) / CGFloat(roundRange)) * usableWidth
            let hashJitterX = hashDerived(vertex.digestHex, salt: 1) * zoneWidth * 0.35

            // Y: lane center exactly — each lane is a player's "lifeline" axis,
            // so every one of their vertices sits on that horizontal line. No
            // Y-jitter, ever. (X-jitter within a round zone is fine because the
            // round zone is a band, not an axis.)
            let laneHeight = usableHeight / CGFloat(nodeCount)
            let laneCenterY = margin + (CGFloat(laneIdx) + 0.5) * laneHeight

            // Clamp to canvas bounds so nothing is cut off
            let x = max(margin + 10, min(canvasSize.width - margin - 10, zoneCenterX + hashJitterX))
            let y = laneCenterY
            positions[vertex.digestHex] = CGPoint(x: x, y: y)
        }

        return DAGLayout(
            positions: positions,
            bounds: CGRect(origin: .zero, size: canvasSize),
            roundBoundaries: roundBounds
        )
    }

    /// Hash-derived deterministic jitter in range [-1, 1]
    private static func hashDerived(_ hex: String, salt: Int) -> CGFloat {
        var hash: UInt64 = 5381 &+ UInt64(salt) &* 33
        for ch in hex.utf8 {
            hash = hash &* 33 &+ UInt64(ch)
        }
        return CGFloat(Double(hash % 10000) / 5000.0 - 1.0)
    }
}

// MARK: - Drawing into Canvas GraphicsContext

extension DAGLayout {

    /// Draw all edges — visible and clear
    func drawEdges(
        in context: inout GraphicsContext,
        edges: [EdgeData],
        alpha: Double = 0.35,
        lineWidth: CGFloat = 1.2
    ) {
        for edge in edges {
            guard let from = positions[edge.from], let to = positions[edge.to] else { continue }
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: lineWidth)
        }
    }

    /// Draw a single parent edge as an actual ARROW — stem + filled triangular
    /// head — pointing from `child` (e.g., Ben's vertex) to `parent` (Aaron's
    /// vertex). The narration calls these "parent edges" / "Ben → Aaron",
    /// so the visualization needs an arrowhead, not a bare line.
    func drawArrowEdge(
        in context: inout GraphicsContext,
        from childDigest: String,
        to parentDigest: String,
        color: Color = .white,
        alpha: Double = 0.9,
        lineWidth: CGFloat = 2.0,
        headLength: CGFloat = 12,
        headWidth: CGFloat = 8,
        startInset: CGFloat = 12,
        endInset: CGFloat = 14
    ) {
        guard let cPos = positions[childDigest], let pPos = positions[parentDigest] else { return }
        let dx = pPos.x - cPos.x
        let dy = pPos.y - cPos.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 1 else { return }
        let ux = dx / dist
        let uy = dy / dist
        // Move endpoints outside the vertex circles so the arrow doesn't
        // visually disappear inside the head/tail glyph.
        let start = CGPoint(x: cPos.x + ux * startInset, y: cPos.y + uy * startInset)
        let end   = CGPoint(x: pPos.x - ux * endInset,   y: pPos.y - uy * endInset)

        // Stem.
        var stem = Path()
        stem.move(to: start)
        stem.addLine(to: end)
        context.stroke(stem, with: .color(color.opacity(alpha)), lineWidth: lineWidth)

        // Filled triangular head at `end`, perpendicular base.
        let perpX = -uy
        let perpY = ux
        let baseCenter = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let baseLeft = CGPoint(x: baseCenter.x + perpX * headWidth / 2,
                                y: baseCenter.y + perpY * headWidth / 2)
        let baseRight = CGPoint(x: baseCenter.x - perpX * headWidth / 2,
                                 y: baseCenter.y - perpY * headWidth / 2)
        var head = Path()
        head.move(to: end)
        head.addLine(to: baseLeft)
        head.addLine(to: baseRight)
        head.closeSubpath()
        context.fill(head, with: .color(color.opacity(alpha)))
    }

    /// Draw all vertices as colored circles with optional labels
    func drawVertices(
        in context: inout GraphicsContext,
        vertices: [VertexData],
        nodes: [NodeMeta],
        dm: DataManager,
        showLabels: Bool = true,
        showWeight: Bool = true,
        animationTime: Double = 1000,       // large default = all visible
        highlightSet: Set<String>? = nil,
        subset: Set<String>? = nil,
        visibleCount: Int? = nil,           // if set, only show first N vertices (sorted by round)
        textScale: Double = 1.0
    ) {
        let filteredVertices: [VertexData]
        if let subset {
            filteredVertices = vertices.filter { subset.contains($0.digestHex) }
        } else {
            filteredVertices = vertices
        }

        // Sort by round for staggered animation
        let sorted = filteredVertices.sorted { $0.round < $1.round }
        let limit = visibleCount ?? sorted.count

        for (i, vertex) in sorted.enumerated() {
            guard let pos = positions[vertex.digestHex] else { continue }

            // Hard cutoff for progressive reveal
            if i >= limit { continue }

            // Staggered appearance — fade in over ~0.5s per vertex
            let appear: Double
            if let _ = visibleCount {
                // When using progressive reveal, newly appeared vertices fade in
                let distFromEdge = Double(limit - 1 - i)
                appear = distFromEdge < 3 ? min(1.0, 0.4 + distFromEdge * 0.2) : 1.0
            } else {
                appear = min(1.0, max(0, animationTime * 0.8 - Double(i) * 0.03))
            }
            if appear < 0.01 { continue }

            let baseColor = dm.castColor(for: vertex.processIdHex)

            let isHighlighted = highlightSet?.contains(vertex.digestHex) ?? false
            let isByz = vertex.isByzantineSource

            // Radius based on PoW weight — minimum 8pt for visibility
            let baseRadius: CGFloat = showWeight ? (8 + CGFloat(min(vertex.weight, 10)) * 1.0) : 9
            let radius = baseRadius * appear

            // Draw glow for highlighted or byzantine
            if isHighlighted {
                let glowRect = CGRect(x: pos.x - radius * 2, y: pos.y - radius * 2,
                                       width: radius * 4, height: radius * 4)
                context.fill(Circle().path(in: glowRect),
                            with: .color(.white.opacity(0.15 * appear)))
            }

            // Main circle
            let rect = CGRect(x: pos.x - radius, y: pos.y - radius,
                               width: radius * 2, height: radius * 2)
            let fillColor: Color = isByz ? .red : baseColor
            context.fill(Circle().path(in: rect),
                        with: .color(fillColor.opacity(isHighlighted ? 1.0 : 0.85 * appear)))

            // Border for isLast (round boundary markers)
            if vertex.isLast {
                context.stroke(Circle().path(in: rect.insetBy(dx: -2, dy: -2)),
                              with: .color(.white.opacity(0.7 * appear)), lineWidth: 2)
            }

            // Label — always readable
            if showLabels && radius > 5 {
                let label = String(vertex.digestHex.prefix(4))
                context.draw(
                    Text(label)
                        .font(Self.fontVertex(scale: textScale))
                        .foregroundColor(.white.opacity(0.9 * appear)),
                    at: CGPoint(x: pos.x, y: pos.y + radius + 10)
                )
            }
        }
    }

    /// Draw round zone separators and labels
    func drawRoundSeparators(
        in context: inout GraphicsContext,
        canvasSize: CGSize,
        minRound: Int,
        alpha: Double = 0.25,
        textScale: Double = 1.0
    ) {
        for (i, x) in roundBoundaries.enumerated() {
            // Vertical separator
            var line = Path()
            line.move(to: CGPoint(x: x, y: 30))
            line.addLine(to: CGPoint(x: x, y: canvasSize.height - 30))
            let dash: [CGFloat] = [4, 8]
            context.stroke(line, with: .color(.white.opacity(alpha * 0.5)),
                          style: StrokeStyle(lineWidth: 0.5, dash: dash))

            // Round label at top
            let roundNum = minRound + i
            context.draw(
                Text("R\(roundNum)")
                    .font(Self.fontCaption(scale: textScale))
                    .foregroundColor(.white.opacity(alpha)),
                at: CGPoint(x: x + 20, y: 16)
            )
        }
    }

    /// Draw "NO GLOBAL CLOCK" banner
    func drawNoClockBanner(in context: inout GraphicsContext, canvasSize: CGSize, alpha: Double = 0.3, textScale: Double = 1.0) {
        context.draw(
            Text("NO GLOBAL CLOCK — ASYNC GOSSIP")
                .font(Self.fontHeading(scale: textScale))
                .foregroundColor(.white.opacity(alpha)),
            at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height - 20)
        )
    }

    /// Draw node lane labels on the left edge
    func drawNodeLanes(
        in context: inout GraphicsContext,
        nodes: [NodeMeta],
        canvasSize: CGSize,
        margin: CGFloat = 60,
        dm: DataManager,
        textScale: Double = 1.0
    ) {
        let usableHeight = canvasSize.height - margin * 2
        let laneHeight = usableHeight / CGFloat(max(nodes.count, 1))

        for (i, node) in nodes.enumerated() {
            let y = margin + (CGFloat(i) + 0.5) * laneHeight
            let role = dm.castRole(for: node.processIdHex)
            let color = role.color

            // Color indicator dot
            let dotRect = CGRect(x: 8, y: y - 4, width: 8, height: 8)
            context.fill(Circle().path(in: dotRect), with: .color(color.opacity(0.7)))

            // Cast name (or "Peer" for unnamed background validators)
            let label = role.isNamedCast ? role.displayName : "Peer"
            context.draw(
                Text(label)
                    .font(Self.fontCaption(scale: textScale))
                    .foregroundColor(color.opacity(role.isNamedCast ? 0.7 : 0.35)),
                at: CGPoint(x: 30, y: y)
            )

            // Lane line
            var lane = Path()
            lane.move(to: CGPoint(x: margin - 10, y: y))
            lane.addLine(to: CGPoint(x: canvasSize.width - 10, y: y))
            context.stroke(lane, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
        }
    }
}
