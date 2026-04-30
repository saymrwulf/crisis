import SwiftUI

/// Computes 2D positions for DAG vertices and provides drawing helpers.
/// Layout: X axis = causal wave zones (by round), Y axis = node lanes with hash-derived jitter.
struct DAGLayout {
    let positions: [String: CGPoint]  // digestHex -> position
    let bounds: CGRect
    let roundBoundaries: [CGFloat]    // x positions of round separators

    // MARK: - Consistent type scale (all monospaced)

    /// Tiny labels inside/beside vertices
    static let fontVertex: Font = .system(size: 10, weight: .medium, design: .monospaced)
    /// Small annotation text (round labels, lane names, counts)
    static let fontCaption: Font = .system(size: 11, weight: .bold, design: .monospaced)
    /// Medium overlay text (annotations, inspection data)
    static let fontBody: Font = .system(size: 12, weight: .medium, design: .monospaced)
    /// Large annotation (section headers, key callouts)
    static let fontHeading: Font = .system(size: 14, weight: .heavy, design: .monospaced)
    /// Banner/title text
    static let fontTitle: Font = .system(size: 16, weight: .heavy, design: .monospaced)

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

            // Y: lane center + small jitter
            let laneHeight = usableHeight / CGFloat(nodeCount)
            let laneCenterY = margin + (CGFloat(laneIdx) + 0.5) * laneHeight
            let hashJitterY = hashDerived(vertex.digestHex, salt: 2) * laneHeight * 0.3

            // Clamp to canvas bounds so nothing is cut off
            let x = max(margin + 10, min(canvasSize.width - margin - 10, zoneCenterX + hashJitterX))
            let y = max(margin + 10, min(canvasSize.height - margin - 10, laneCenterY + hashJitterY))
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
        visibleCount: Int? = nil            // if set, only show first N vertices (sorted by round)
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

            let colorIdx = dm.colorIndex(for: vertex.processIdHex)
            let baseColor = DataManager.palette[min(colorIdx, DataManager.palette.count - 1)]

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
                        .font(Self.fontVertex)
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
        alpha: Double = 0.25
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
                    .font(Self.fontCaption)
                    .foregroundColor(.white.opacity(alpha)),
                at: CGPoint(x: x + 20, y: 16)
            )
        }
    }

    /// Draw "NO GLOBAL CLOCK" banner
    func drawNoClockBanner(in context: inout GraphicsContext, canvasSize: CGSize, alpha: Double = 0.3) {
        context.draw(
            Text("NO GLOBAL CLOCK — ASYNC GOSSIP")
                .font(Self.fontHeading)
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
        dm: DataManager
    ) {
        let usableHeight = canvasSize.height - margin * 2
        let laneHeight = usableHeight / CGFloat(max(nodes.count, 1))

        for (i, node) in nodes.enumerated() {
            let y = margin + (CGFloat(i) + 0.5) * laneHeight
            let colorIdx = dm.colorIndex(for: node.processIdHex)
            let color = DataManager.palette[min(colorIdx, DataManager.palette.count - 1)]

            // Color indicator dot
            let dotRect = CGRect(x: 8, y: y - 4, width: 8, height: 8)
            context.fill(Circle().path(in: dotRect), with: .color(color.opacity(0.7)))

            // Name
            let label = node.isByzantine ? "BYZ" : String(node.name.suffix(1))
            context.draw(
                Text(label)
                    .font(Self.fontCaption)
                    .foregroundColor(color.opacity(0.5)),
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
