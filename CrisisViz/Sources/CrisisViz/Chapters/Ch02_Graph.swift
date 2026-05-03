import SwiftUI

/// Ch02: "Building the Graph" — 7 scenes showing DAG construction with smooth progressive reveal.
/// Uses the FULL step-9 dataset for layout (so positions never jump) but only reveals a subset
/// of vertices per scene. The subset grows across scenes to create a smooth unfolding.
///
/// In scenes 1+ vertices are tappable: a tap hit-tests against the live layout and selects
/// the closest visible vertex via `InspectionState`. The Inspector overlay is rendered by
/// `ImmersiveView`; this chapter only emits the selection.
struct Ch02_Graph: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    let inspection: InspectionState
    @Environment(AppSettings.self) private var settings

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                render(context: &context, size: size, time: localTime)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { event in
                    handleTap(at: event.location, size: geo.size)
                }
            )
            .overlay(alignment: .topTrailing) {
                if sceneIndex >= 1 {
                    Text("CLICK ANY VERTEX TO INSPECT")
                        .scaledFont(size: 10, weight: .heavy, design: .monospaced)
                        .foregroundStyle(.yellow.opacity(0.55))
                        .kerning(1.4)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.black.opacity(0.55))
                        )
                        .padding(.top, 36)
                        .padding(.trailing, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Tap → vertex hit test

    private func handleTap(at point: CGPoint, size: CGSize) {
        guard sceneIndex >= 1 else { return }
        guard let snap = dm.honestData(step: 9), let sim = dm.sim else { return }

        let layout = DAGLayout.compute(
            vertices: snap.vertices,
            edges: snap.edges,
            nodes: sim.nodes,
            canvasSize: size,
            margin: 60
        )

        let visible = visibleDigests(snap: snap, time: localTime)
        var best: (digest: String, dist: CGFloat)? = nil
        for digest in visible {
            guard let pos = layout.positions[digest] else { continue }
            let dx = pos.x - point.x
            let dy = pos.y - point.y
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= 28, best == nil || d < best!.dist {
                best = (digest, d)
            }
        }
        if let hit = best {
            withAnimation(.easeInOut(duration: 0.3)) {
                inspection.select(hit.digest)
            }
        }
    }

    private func visibleDigests(snap: NodeSnapshot, time: Double) -> [String] {
        let sorted = snap.vertices.sorted {
            if $0.round != $1.round { return $0.round < $1.round }
            return $0.processIdHex < $1.processIdHex
        }
        let growthRate = 1.5
        let timeBonus = min(8, Int(time * growthRate))
        let visCount = min(sceneVertexCount + timeBonus, sorted.count)
        return Array(sorted.prefix(visCount)).map { $0.digestHex }
    }

    /// Fixed vertex count per scene — deterministic, no time dependency
    private var sceneVertexCount: Int {
        switch sceneIndex {
        case 0: return 12       // genesis round — just the initial vertices
        case 1: return 24       // early gossip
        case 2: return 36       // tips visible
        case 3: return 50       // inspection
        case 4: return 58       // commit-reveal
        case 5: return 68       // graph identity
        case 6: return 82       // full graph (all vertices)
        default: return 30
        }
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard let sim = dm.sim,
              let snap = dm.honestData(step: 9) else {
            context.draw(Text("Loading data...").foregroundColor(.white),
                        at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        let allVertices = snap.vertices
        let allEdges = snap.edges
        let nodes = sim.nodes

        // Always compute layout from the FULL dataset so positions never jump
        let layout = DAGLayout.compute(
            vertices: allVertices,
            edges: allEdges,
            nodes: nodes,
            canvasSize: size,
            margin: 60
        )

        // Sort vertices by round, then by processIdHex for stable ordering
        let sortedVertices = allVertices.sorted {
            if $0.round != $1.round { return $0.round < $1.round }
            return $0.processIdHex < $1.processIdHex
        }

        // Progressive reveal: time adds a few extra vertices for smooth growth within a scene
        let growthRate = 1.5 // vertices per second
        let timeBonus = min(8, Int(time * growthRate))  // cap at 8 extra, so scenes stay distinct
        let visCount = min(sceneVertexCount + timeBonus, sortedVertices.count)
        let visibleSet = Set(sortedVertices.prefix(visCount).map { $0.digestHex })

        // Filter edges to only those between visible vertices
        let visibleEdges = allEdges.filter { visibleSet.contains($0.from) && visibleSet.contains($0.to) }
        let visibleVerts = sortedVertices.filter { visibleSet.contains($0.digestHex) }

        // Draw infrastructure
        let minRound = allVertices.map { $0.round }.min() ?? 0
        layout.drawNodeLanes(in: &context, nodes: nodes, canvasSize: size, dm: dm, textScale: settings.textScale)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: minRound, textScale: settings.textScale)
        layout.drawNoClockBanner(in: &context, canvasSize: size, textScale: settings.textScale)

        // Draw edges — clearly visible
        layout.drawEdges(in: &context, edges: visibleEdges, alpha: 0.3, lineWidth: 1.2)

        // Scene-specific rendering
        switch sceneIndex {
        case 0:
            // Async gossip begins — vertices appear progressively
            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm,
                              showLabels: true, visibleCount: visCount, textScale: settings.textScale)

        case 1:
            // DAG grows
            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm,
                              showLabels: true, visibleCount: visCount, textScale: settings.textScale)

        case 2:
            // Tip references highlighted
            let referencedSet = Set(visibleEdges.map { $0.to })
            let tips = Set(visibleVerts.map { $0.digestHex }).subtracting(referencedSet)

            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm,
                              showLabels: true, highlightSet: tips, visibleCount: visCount, textScale: settings.textScale)

            for tipHex in tips {
                if let pos = layout.positions[tipHex] {
                    context.draw(
                        Text("TIP")
                            .font(DAGLayout.fontCaption(scale: settings.textScale))
                            .foregroundColor(.yellow.opacity(0.9)),
                        at: CGPoint(x: pos.x, y: pos.y - 20)
                    )
                }
            }

            context.draw(
                Text("NEW MESSAGES REFERENCE ONLY THE TIPS — TRANSITIVE COMMITMENT")
                    .font(DAGLayout.fontHeading(scale: settings.textScale))
                    .foregroundColor(.yellow.opacity(0.5)),
                at: CGPoint(x: size.width / 2, y: size.height - 50)
            )

        case 3:
            // Hash inspection
            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm,
                              showLabels: true, visibleCount: visCount, textScale: settings.textScale)

            // Pick a vertex near the middle of the visible range for inspection
            let midIdx = visibleVerts.count / 2
            if midIdx > 0 {
                let inspected = visibleVerts[midIdx]
                if let pos = layout.positions[inspected.digestHex] {
                    // Highlight circle
                    let r: CGFloat = 20
                    let glowRect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
                    context.stroke(Circle().path(in: glowRect),
                                  with: .color(.yellow.opacity(0.6 + 0.3 * sin(time * 3))),
                                  lineWidth: 2.5)

                    // Position info box: prefer toward center of screen, with margin from edges
                    let boxW: CGFloat = 300
                    let boxH: CGFloat = 84
                    let boxX: CGFloat
                    if pos.x > size.width * 0.6 {
                        boxX = pos.x - boxW - 35
                    } else if pos.x < size.width * 0.4 {
                        boxX = pos.x + 35
                    } else {
                        boxX = pos.x - boxW / 2
                    }
                    let boxY = max(50, min(pos.y - boxH / 2, size.height - boxH - 50))
                    let boxRect = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)

                    context.fill(RoundedRectangle(cornerRadius: 10).path(in: boxRect),
                                with: .color(.black.opacity(0.9)))
                    context.stroke(RoundedRectangle(cornerRadius: 10).path(in: boxRect),
                                  with: .color(.yellow.opacity(0.5)), lineWidth: 1.5)

                    // Connector line
                    let lineAnchorX = pos.x > size.width * 0.6 ? boxRect.maxX : boxRect.minX
                    var connector = Path()
                    connector.move(to: CGPoint(x: lineAnchorX, y: boxRect.midY))
                    connector.addLine(to: pos)
                    context.stroke(connector, with: .color(.yellow.opacity(0.3)), lineWidth: 1)

                    let digestStr = String(inspected.digestFull.prefix(28))
                    context.draw(
                        Text("digest: \(digestStr)...")
                            .font(DAGLayout.fontBody(scale: settings.textScale))
                            .foregroundColor(.yellow.opacity(0.9)),
                        at: CGPoint(x: boxRect.midX, y: boxRect.minY + 20)
                    )
                    context.draw(
                        Text("round: \(inspected.round)  weight: \(inspected.weight)  isLast: \(String(describing: inspected.isLast))")
                            .font(DAGLayout.fontBody(scale: settings.textScale))
                            .foregroundColor(.white.opacity(0.7)),
                        at: CGPoint(x: boxRect.midX, y: boxRect.minY + 42)
                    )
                    context.draw(
                        Text("payload: \(inspected.payloadStr)")
                            .font(DAGLayout.fontBody(scale: settings.textScale))
                            .foregroundColor(.white.opacity(0.7)),
                        at: CGPoint(x: boxRect.midX, y: boxRect.minY + 64)
                    )
                }
            }

        case 4:
            // Commit-reveal
            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm,
                              showLabels: true, visibleCount: visCount, textScale: settings.textScale)

            let parentMap = buildParentMap(edges: visibleEdges)
            // Pick a vertex with parents that's well within the visible area (not at edges)
            if let (child, parents) = findVertexWithParents(vertices: visibleVerts, parentMap: parentMap, layout: layout, canvasSize: size) {
                if let cp = layout.positions[child.digestHex] {
                    let r: CGFloat = 20
                    context.stroke(Circle().path(in: CGRect(x: cp.x - r, y: cp.y - r, width: r*2, height: r*2)),
                                  with: .color(.white), lineWidth: 3)

                    // Position label above or below depending on space
                    let labelY = cp.y > size.height * 0.3 ? cp.y - 34 : cp.y + 34
                    context.draw(
                        Text("hash(C) = \(String(child.digestHex.prefix(8)))...")
                            .font(DAGLayout.fontHeading(scale: settings.textScale))
                            .foregroundColor(.white.opacity(0.9)),
                        at: CGPoint(x: cp.x, y: labelY)
                    )

                    for parent in parents.prefix(3) {
                        if let pp = layout.positions[parent] {
                            let flash = 0.5 + 0.4 * sin(time * 2)
                            let hiddenRect = CGRect(x: pp.x - 35, y: pp.y - 26, width: 70, height: 18)
                            context.fill(RoundedRectangle(cornerRadius: 3).path(in: hiddenRect),
                                        with: .color(.red.opacity(0.2 * flash)))
                            context.draw(
                                Text("HIDDEN")
                                    .font(DAGLayout.fontCaption(scale: settings.textScale))
                                    .foregroundColor(.red.opacity(0.8 * flash)),
                                at: CGPoint(x: pp.x, y: pp.y - 18)
                            )
                        }
                    }
                }
            }

        case 5:
            // Graph identity
            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm,
                              showLabels: true, visibleCount: visCount, textScale: settings.textScale)

            let alpha = 0.5 + 0.2 * sin(time * 1.5)
            context.draw(
                Text("SAME MESSAGES → SAME GRAPH — DETERMINISTIC")
                    .font(DAGLayout.fontTitle(scale: settings.textScale))
                    .foregroundColor(.cyan.opacity(alpha)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )

        case 6:
            // Recursive expansion — full graph
            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm, showLabels: true, textScale: settings.textScale)

            let chain = findChainToGenesis(vertices: visibleVerts, edges: visibleEdges)
            for hex in chain {
                if let pos = layout.positions[hex] {
                    let r: CGFloat = 16
                    context.stroke(
                        Circle().path(in: CGRect(x: pos.x - r, y: pos.y - r, width: r*2, height: r*2)),
                        with: .color(.yellow.opacity(0.8)),
                        lineWidth: 2.5
                    )
                }
            }
            for i in 0..<(chain.count - 1) {
                if let from = layout.positions[chain[i]], let to = layout.positions[chain[i + 1]] {
                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)
                    context.stroke(path, with: .color(.yellow.opacity(0.7)), lineWidth: 2.5)
                }
            }

            context.draw(
                Text("RECURSIVE HASH CHAIN — EVERY VERTEX TRACES BACK TO GENESIS")
                    .font(DAGLayout.fontHeading(scale: settings.textScale))
                    .foregroundColor(.yellow.opacity(0.5)),
                at: CGPoint(x: size.width / 2, y: size.height - 50)
            )

        default:
            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm, showLabels: true, textScale: settings.textScale)
        }

        // Vertex count — top center
        context.draw(
            Text("\(visCount)/\(allVertices.count) VERTICES · \(visibleEdges.count) EDGES")
                .font(DAGLayout.fontCaption(scale: settings.textScale))
                .foregroundColor(.white.opacity(0.25)),
            at: CGPoint(x: size.width / 2, y: 16)
        )
    }

    // MARK: - Helpers

    private func buildParentMap(edges: [EdgeData]) -> [String: [String]] {
        var map: [String: [String]] = [:]
        for e in edges {
            map[e.from, default: []].append(e.to)
        }
        return map
    }

    /// Find a vertex with 2+ parents that's well-positioned (not at screen edges)
    private func findVertexWithParents(
        vertices: [VertexData],
        parentMap: [String: [String]],
        layout: DAGLayout,
        canvasSize: CGSize
    ) -> (VertexData, [String])? {
        let margin: CGFloat = 150
        for v in vertices.reversed() {
            if let parents = parentMap[v.digestHex], parents.count >= 2 {
                // Check that it's not clipped at screen edges
                if let pos = layout.positions[v.digestHex] {
                    if pos.x > margin && pos.x < canvasSize.width - margin &&
                       pos.y > margin && pos.y < canvasSize.height - margin {
                        return (v, parents)
                    }
                }
            }
        }
        // Fallback: any vertex with parents
        for v in vertices.reversed() {
            if let parents = parentMap[v.digestHex], parents.count >= 2 {
                return (v, parents)
            }
        }
        return nil
    }

    private func findChainToGenesis(vertices: [VertexData], edges: [EdgeData]) -> [String] {
        var parentOf: [String: String] = [:]
        for e in edges {
            if parentOf[e.from] == nil {
                parentOf[e.from] = e.to
            }
        }

        guard let start = vertices.sorted(by: { $0.round > $1.round }).first else { return [] }
        var chain: [String] = [start.digestHex]
        var current = start.digestHex

        for _ in 0..<50 {
            if let parent = parentOf[current] {
                chain.append(parent)
                current = parent
            } else {
                break
            }
        }
        return chain
    }
}
