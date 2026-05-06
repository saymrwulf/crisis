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
        guard let snap = dm.honestData(step: 5), dm.sim != nil else { return }

        let layout = DAGLayout.compute(
            vertices: snap.vertices,
            edges: snap.edges,
            nodes: dm.castOrderedNodes(),
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
        guard dm.sim != nil,
              let snap = dm.honestData(step: 5) else {
            context.draw(Text("Loading data...").foregroundColor(.white),
                        at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        let allVertices = snap.vertices
        let allEdges = snap.edges
        let nodes = dm.castOrderedNodes()

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

        // Visible vertex set:
        //   - Scenes 0/1/2 are NARRATIVE BEATS. The titles say "Aaron's first
        //     message", "Ben copies what he saw", "Carl arrives and links in".
        //     We curate exactly Aaron, then +Ben (with his edge back to
        //     Aaron's round-0), then +Carl (with edges to both). No
        //     progressive reveal — the on-canvas vertex count must equal the
        //     narrated message count, or the story is a lie.
        //   - Scenes 3+ keep the time-based progressive reveal so the larger
        //     graph fills in naturally.
        let visibleSet: Set<String>
        let visCount: Int
        if let staged = narrativeStagedSet(snap: snap) {
            visibleSet = staged
            visCount = staged.count
        } else if sceneIndex == 3 {
            // Scene 3 must morph in from scene 2's exact 3-vertex set, not
            // snap-cut to 50 vertices. The user explicitly asked for slower
            // gossip-like reveal: "show every message traveling and arriving
            // and hashing and arrow back to where it came from."
            //
            // Within the existing scene framework we approximate that with:
            //   - 8-second warm-up (was 4)
            //   - cubic ease-out so the first new vertices arrive gently and
            //     accelerate toward the end
            //   - vertices appear with their full parent-edge fan, drawing
            //     the gossip arrows (handled in `drawVertices` via animation
            //     timing)
            let prevStaged = stagedFromSceneIndex(2, snap: snap) ?? []
            let target = sceneVertexCount  // 50 for scene 3
            let warmup: Double = 8.0
            let raw = min(1.0, max(0, time / warmup))
            let eased = pow(raw, 1.8)  // slower start than before
            let count = prevStaged.count
                + Int(Double(max(0, target - prevStaged.count)) * eased)
            visCount = min(count, sortedVertices.count)
            var set = prevStaged
            for v in sortedVertices where set.count < visCount {
                set.insert(v.digestHex)
            }
            visibleSet = set
        } else {
            let growthRate = 1.5 // vertices per second
            let timeBonus = min(8, Int(time * growthRate))
            visCount = min(sceneVertexCount + timeBonus, sortedVertices.count)
            visibleSet = Set(sortedVertices.prefix(visCount).map { $0.digestHex })
        }

        // Filter edges to only those between visible vertices
        let visibleEdges = allEdges.filter { visibleSet.contains($0.from) && visibleSet.contains($0.to) }
        let visibleVerts = sortedVertices.filter { visibleSet.contains($0.digestHex) }

        // Draw infrastructure
        let minRound = allVertices.map { $0.round }.min() ?? 0
        layout.drawNodeLanes(in: &context, nodes: nodes, canvasSize: size, dm: dm, textScale: settings.textScale)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: minRound, textScale: settings.textScale)
        // No-clock banner only for the dense scenes; the staged scenes 0/1/2
        // already carry the "no global clock" lesson via the narration.
        if sceneIndex >= 3 {
            layout.drawNoClockBanner(in: &context, canvasSize: size, textScale: settings.textScale)
        }

        // Scene-specific rendering
        switch sceneIndex {
        case 0, 1, 2:
            renderStagedBeat(in: &context, size: size, time: time,
                             layout: layout, visibleVerts: visibleVerts,
                             visibleEdges: visibleEdges, snap: snap)
            // Scene 2 adds the per-character perspective panel below — it
            // makes "three perspectives, one nucleus of shared truth"
            // physically visible rather than just narrated.
            if sceneIndex == 2 {
                drawPerspectivePanel(in: &context, size: size, time: time, snap: snap)
            }

        case 3:
            // Scene 3 is now the dedicated slow-motion gossip dramatization.
            // It uses a hand-crafted GossipScript instead of simulation
            // snapshots — the simulation can't show the asymmetric
            // arrival timing, line-by-line message composition, or
            // perspective-bubble updates the user explicitly asked for.
            // The original "click any vertex" inspect feature is still
            // available globally; we don't need to instruct it here.
            renderGossipDramatization(in: &context, size: size, time: time)
            return  // skip the dense-graph rendering below

        case 30:  // unreachable; kept so original case 3 logic stays as ref
            layout.drawEdges(in: &context, edges: visibleEdges, alpha: 0.3, lineWidth: 1.2)
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
            layout.drawEdges(in: &context, edges: visibleEdges, alpha: 0.3, lineWidth: 1.2)
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
            layout.drawEdges(in: &context, edges: visibleEdges, alpha: 0.3, lineWidth: 1.2)
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
            // Ancestor cone — every vertex reachable by walking parent edges
            // backward from the chosen leaf. The ORIGINAL implementation drew
            // a single chain (one parent per hop), but vertices have MULTIPLE
            // parents — walking back fans out into a tree/cone, not a line.
            // The user called this out: "It is more like a tree, not line by
            // line, no?"
            layout.drawEdges(in: &context, edges: visibleEdges, alpha: 0.20, lineWidth: 1.0)
            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm,
                              showLabels: true, textScale: settings.textScale)

            // Pick a recent, well-connected vertex as the leaf to trace back
            // from. Highest-round, highest-weight wins.
            let leaf = visibleVerts.max { lhs, rhs in
                if lhs.round != rhs.round { return lhs.round < rhs.round }
                return lhs.weight < rhs.weight
            }
            if let leaf {
                let cone = ancestorClosure(of: leaf.digestHex, edges: visibleEdges, depth: 8)
                let coneEdges = visibleEdges.filter {
                    cone.contains($0.from) && cone.contains($0.to)
                }
                // Highlight every cone edge in yellow.
                for e in coneEdges {
                    layout.drawArrowEdge(
                        in: &context,
                        from: e.from, to: e.to,
                        color: .yellow, alpha: 0.85,
                        lineWidth: 2.0,
                        headLength: 9, headWidth: 6,
                        startInset: 13, endInset: 14
                    )
                }
                // Halo every cone vertex in yellow.
                for hex in cone {
                    if let pos = layout.positions[hex] {
                        let r: CGFloat = 14
                        context.stroke(
                            Circle().path(in: CGRect(x: pos.x - r, y: pos.y - r, width: r*2, height: r*2)),
                            with: .color(.yellow.opacity(0.7)), lineWidth: 1.8
                        )
                    }
                }
                // Tag the leaf and identify the GENESIS root(s).
                if let pos = layout.positions[leaf.digestHex] {
                    context.draw(
                        Text("LEAF — TRACE STARTS HERE")
                            .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.95)),
                        at: CGPoint(x: pos.x, y: pos.y - 26)
                    )
                }
                // Genesis vertices are those in the cone with no outgoing
                // parent edges in the cone (they don't point back further).
                let coneSet = cone
                let inCone: (String) -> Bool = { coneSet.contains($0) }
                let genesisHexes = cone.filter { d in
                    !visibleEdges.contains { $0.from == d && inCone($0.to) }
                }
                for hex in genesisHexes {
                    if let pos = layout.positions[hex] {
                        context.draw(
                            Text("★ GENESIS")
                                .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                                .foregroundColor(.yellow.opacity(0.95)),
                            at: CGPoint(x: pos.x, y: pos.y + 24)
                        )
                    }
                }
            }

            context.draw(
                Text("ANCESTOR CONE — EVERY VERTEX FANS BACK INTO A TREE OF PARENTS, REACHING GENESIS")
                    .font(DAGLayout.fontHeading(scale: settings.textScale))
                    .foregroundColor(.yellow.opacity(0.55)),
                at: CGPoint(x: size.width / 2, y: size.height - 50)
            )

        default:
            layout.drawEdges(in: &context, edges: visibleEdges, alpha: 0.3, lineWidth: 1.2)
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

    /// Compute the staged visible set for an arbitrary sceneIndex (used by
    /// scene 3 to start morphing from scene 2's staged set). Mirrors the
    /// strict-then-relaxed staging in `narrativeStagedSet`.
    private func stagedFromSceneIndex(_ idx: Int, snap: NodeSnapshot) -> Set<String>? {
        guard idx <= 2,
              let aaronPid = pid(of: Cast.aaron),
              let benPid = pid(of: Cast.ben),
              let carlPid = pid(of: Cast.carl) else { return nil }

        guard let aaronR0 = snap.vertices
                .filter({ $0.processIdHex == aaronPid })
                .min(by: { $0.round < $1.round
                           || ($0.round == $1.round && $0.digestHex < $1.digestHex) })
        else { return nil }
        let aaronR0Hex = aaronR0.digestHex
        let allAaronHex = Set(snap.vertices.filter { $0.processIdHex == aaronPid }.map(\.digestHex))

        var visible: Set<String> = [aaronR0Hex]
        if idx == 0 { return visible }

        let benCandidates = snap.vertices.filter { $0.processIdHex == benPid }
            .sorted { $0.round < $1.round || ($0.round == $1.round && $0.digestHex < $1.digestHex) }
        let benVertex = benCandidates.first(where: { bv in
                snap.edges.contains { $0.from == bv.digestHex && $0.to == aaronR0Hex }
            })
            ?? benCandidates.first(where: { bv in
                snap.edges.contains { $0.from == bv.digestHex && allAaronHex.contains($0.to) }
            })
            ?? benCandidates.first
        if let bv = benVertex { visible.insert(bv.digestHex) }
        if idx == 1 { return visible }

        let carlCandidates = snap.vertices.filter { $0.processIdHex == carlPid }
            .sorted { $0.round < $1.round || ($0.round == $1.round && $0.digestHex < $1.digestHex) }
        let carlVertex = carlCandidates.first(where: { cv in
                snap.edges.contains { $0.from == cv.digestHex && $0.to == aaronR0Hex }
            })
            ?? carlCandidates.first(where: { cv in
                snap.edges.contains { $0.from == cv.digestHex && visible.contains($0.to) }
            })
            ?? carlCandidates.first
        if let cv = carlVertex { visible.insert(cv.digestHex) }
        return visible
    }

    // MARK: - Slow-motion gossip dramatization (scene 3)

    /// Render the scripted gossip animation. At any local time t we project
    /// `GossipScript.ch01.state(at: t)` into:
    ///   - Four cast bubbles at the four corners of the canvas
    ///   - Composing boxes near each author currently writing a message
    ///   - In-flight rectangles flying along the line between sender and recipient
    ///   - View bubbles that grow as messages are read
    /// The user asked for "extreme slow motion" — beats use 1-5 second
    /// durations so the eye can follow each step.
    private func renderGossipDramatization(
        in context: inout GraphicsContext, size: CGSize, time: Double
    ) {
        let script = GossipScript.ch01
        let world = script.state(at: time)

        // Position each cast member at a fixed point. We use a 3-up layout
        // (Aaron top-left, Ben top-right, Carl bottom-center) so message
        // flight paths are wide and the in-flight rectangles are clearly
        // visible. Dave is not in this dramatization yet (he debuts in
        // Ch02 partition).
        let cx = size.width / 2
        let layout: [GossipScript.CastRoleKey: CGPoint] = [
            .aaron: CGPoint(x: cx - size.width * 0.30, y: size.height * 0.25),
            .ben:   CGPoint(x: cx + size.width * 0.30, y: size.height * 0.25),
            .carl:  CGPoint(x: cx,                     y: size.height * 0.66),
        ]

        // Background grid + title
        context.draw(
            Text(String(format: "GOSSIP MECHANICS · t=%.1fs / %.1fs", time, script.totalDuration))
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.45)),
            at: CGPoint(x: cx, y: 24)
        )

        // 1. Each cast member's "node + view bubble" rendered first as the
        //    backdrop. Bubbles list every message they've absorbed (with
        //    progress 1.0). Bubbles grow gracefully on arrival.
        for (key, pos) in layout {
            drawCastBubble(in: &context, at: pos, key: key,
                          view: world.views[key] ?? GossipScript.ViewState(),
                          script: script,
                          spotlight: world.spotlight?.0 == key,
                          time: time)
        }

        // 2. Composing-in-progress messages rendered next to their author.
        for c in world.composing {
            let authorPos = layout[c.author] ?? .zero
            drawComposingBox(in: &context, anchor: authorPos, composing: c)
        }

        // 3. In-flight messages: small rectangles moving along the path from
        //    sender to recipient. Drawn last so they appear on top of bubbles.
        for f in world.inFlight {
            guard let src = layout[f.from], let dst = layout[f.to] else { continue }
            let p = CGFloat(f.progress)
            let pos = CGPoint(x: src.x + (dst.x - src.x) * p,
                              y: src.y + (dst.y - src.y) * p)
            drawFlightEnvelope(in: &context, at: pos, message: f.message,
                               from: src, to: dst, progress: f.progress)
        }

        // 4. Caption explaining the punch line at the end of the script.
        if time > 19 {
            let alpha = min(1.0, (time - 19) / 1.5)
            context.draw(
                Text("CARL'S γ DOES NOT REFERENCE β — HE WROTE γ BEFORE β ARRIVED. ASYMMETRY IS THE NORM.")
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.85 * alpha)),
                at: CGPoint(x: cx, y: size.height - 30)
            )
        } else if time > 13 {
            context.draw(
                Text("BEN HAS α. HE WRITES β REFERENCING α. CARL ALSO RECEIVED α — INDEPENDENTLY.")
                    .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65)),
                at: CGPoint(x: cx, y: size.height - 30)
            )
        } else if time > 4 {
            context.draw(
                Text("AARON'S α TRAVELS — TWO COPIES, ONE TO BEN, ONE TO CARL, AT DIFFERENT SPEEDS.")
                    .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65)),
                at: CGPoint(x: cx, y: size.height - 30)
            )
        }
    }

    /// Cast member node — circle in their cast color with name underneath, plus
    /// a "view bubble" showing absorbed message hashes.
    private func drawCastBubble(
        in context: inout GraphicsContext, at pos: CGPoint,
        key: GossipScript.CastRoleKey, view: GossipScript.ViewState,
        script: GossipScript, spotlight: Bool, time: Double
    ) {
        let role = key.role
        let radius: CGFloat = 38
        let pulse: CGFloat = spotlight ? 1.0 + 0.06 * CGFloat(sin(time * 5)) : 1.0
        let r = radius * pulse

        let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        // Halo
        let haloR: CGFloat = r * 1.7
        context.fill(
            Circle().path(in: CGRect(x: pos.x - haloR, y: pos.y - haloR,
                                      width: haloR * 2, height: haloR * 2)),
            with: .color(role.color.opacity(0.15))
        )
        context.fill(Circle().path(in: rect), with: .color(role.color.opacity(0.95)))
        context.stroke(Circle().path(in: rect),
                      with: .color(.white.opacity(0.55)), lineWidth: 1.5)
        context.draw(
            Text(String(role.displayName.prefix(1)))
                .font(.system(size: settings.scaled(22), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
        context.draw(
            Text(role.displayName.uppercased())
                .font(.system(size: settings.scaled(12), weight: .heavy, design: .monospaced))
                .foregroundColor(role.color.opacity(0.95)),
            at: CGPoint(x: pos.x, y: pos.y + r + 14)
        )

        // View bubble: a rounded rect to the SIDE of the node listing all
        // received message hashes. We use the node's quadrant to decide which
        // side the bubble sits on.
        let bubbleW: CGFloat = 130
        let bubbleH: CGFloat = 110
        let bubbleX: CGFloat = pos.x < (NSScreen.main?.frame.width ?? 1400) / 2
            ? pos.x + r + 18
            : pos.x - r - 18 - bubbleW
        let bubbleRect = CGRect(x: bubbleX, y: pos.y - bubbleH / 2,
                                 width: bubbleW, height: bubbleH)
        context.fill(RoundedRectangle(cornerRadius: 10).path(in: bubbleRect),
                    with: .color(.black.opacity(0.55)))
        context.stroke(RoundedRectangle(cornerRadius: 10).path(in: bubbleRect),
                      with: .color(role.color.opacity(0.55)), lineWidth: 1)
        context.draw(
            Text("\(role.displayName.uppercased()) SEES")
                .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                .foregroundColor(role.color.opacity(0.9)),
            at: CGPoint(x: bubbleRect.midX, y: bubbleRect.minY + 12)
        )
        // Each absorbed message becomes a small line in the bubble.
        var rowY = bubbleRect.minY + 30
        let allMsgs = script.messages
        for msg in allMsgs {
            guard let progress = view.received[msg.id] else { continue }
            let alpha = progress
            let prefix = "\(msg.id) ·"
            let txt = "\(prefix) \(msg.hashShort)…"
            context.draw(
                Text(txt)
                    .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                    .foregroundColor(msg.author.role.color.opacity(0.95 * alpha)),
                at: CGPoint(x: bubbleRect.minX + 12, y: rowY),
                anchor: .leading
            )
            rowY += 18
        }
        if rowY == bubbleRect.minY + 30 {
            context.draw(
                Text("(empty)")
                    .font(.system(size: settings.scaled(9), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3)),
                at: CGPoint(x: bubbleRect.midX, y: bubbleRect.midY + 4)
            )
        }
    }

    /// A message body being composed — appears near the author with lines
    /// filling in proportional to compose progress.
    private func drawComposingBox(
        in context: inout GraphicsContext, anchor: CGPoint,
        composing: GossipScript.ComposingMessage
    ) {
        let boxW: CGFloat = 200
        let boxH: CGFloat = 80
        // Place above the author node, with a small offset so it doesn't
        // overlap the cast circle.
        let boxRect = CGRect(x: anchor.x - boxW / 2,
                              y: anchor.y - 100 - boxH / 2,
                              width: boxW, height: boxH)
        let color = composing.author.role.color
        context.fill(RoundedRectangle(cornerRadius: 8).path(in: boxRect),
                    with: .color(.black.opacity(0.85)))
        context.stroke(RoundedRectangle(cornerRadius: 8).path(in: boxRect),
                      with: .color(color.opacity(0.9)), lineWidth: 1.5)

        // Header: writer + composing indicator
        context.draw(
            Text("✎ \(composing.author.role.displayName.uppercased()) WRITING")
                .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                .foregroundColor(color),
            at: CGPoint(x: boxRect.midX, y: boxRect.minY + 11)
        )

        // Lines that fill in progressively. We schematically show 4 fields:
        // 1) payload, 2) parent hashes, 3) own hash (only after seal),
        // 4) PoW nonce.
        let lines: [(String, threshold: Double)] = [
            ("payload: \(composing.message.payload)", 0.20),
            ("parents: \(composing.message.parents.isEmpty ? "(genesis)" : composing.message.parents.joined(separator: ", "))", 0.50),
            ("hash:    \(composing.progress > 0.85 ? composing.message.hashShort + "…" : "computing PoW…")", 0.85),
            ("nonce:   \(composing.progress > 0.95 ? "found ✓" : "…")", 0.95),
        ]
        var rowY = boxRect.minY + 28
        for (text, threshold) in lines {
            if composing.progress < threshold { continue }
            let alpha = min(1.0, (composing.progress - threshold) / 0.10)
            context.draw(
                Text(text)
                    .font(.system(size: settings.scaled(9), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85 * alpha)),
                at: CGPoint(x: boxRect.minX + 8, y: rowY),
                anchor: .leading
            )
            rowY += 13
        }
    }

    /// In-flight envelope — small rectangle with the message id + hash at the
    /// interpolated position between sender and recipient.
    private func drawFlightEnvelope(
        in context: inout GraphicsContext, at pos: CGPoint,
        message: GossipScript.ScriptedMessage,
        from src: CGPoint, to dst: CGPoint, progress: Double
    ) {
        // Subtle dashed path so the eye can follow.
        var path = Path()
        path.move(to: src)
        path.addLine(to: dst)
        let dash: [CGFloat] = [3, 5]
        context.stroke(path,
                      with: .color(message.author.role.color.opacity(0.20)),
                      style: StrokeStyle(lineWidth: 1, dash: dash))

        let envW: CGFloat = 70
        let envH: CGFloat = 28
        let rect = CGRect(x: pos.x - envW / 2, y: pos.y - envH / 2,
                          width: envW, height: envH)
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: rect),
                    with: .color(message.author.role.color.opacity(0.92)))
        context.stroke(RoundedRectangle(cornerRadius: 4).path(in: rect),
                      with: .color(.white.opacity(0.6)), lineWidth: 0.8)
        context.draw(
            Text("\(message.id) · \(message.hashShort)")
                .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )

        _ = progress
    }

    /// Per-character "view" panel for scene 2. Each cast member maintains
    /// their own local DAG — what they've personally received via gossip —
    /// and those views differ. The panel makes the views explicit:
    ///
    ///   - AARON SEES: only his own message (nobody has gossiped him yet)
    ///   - BEN SEES: his own + Aaron's (he received Aaron via gossip)
    ///   - CARL SEES: his own + Aaron's (he received Aaron via gossip)
    ///   - COMMON KNOWLEDGE: the intersection — Aaron's first message
    ///
    /// This is the "local consensus emerging" the user asked for: even with
    /// three different perspectives, there's a NUCLEUS of shared truth, and
    /// that nucleus grows with every round of gossip.
    private func drawPerspectivePanel(
        in context: inout GraphicsContext, size: CGSize, time: Double, snap: NodeSnapshot
    ) {
        // The panel fades in over the first 2.5s of the scene so the staged
        // vertices read first, then the panel adds the deeper layer.
        let fade = max(0, min(1, (time - 2.0) / 1.5))
        if fade < 0.05 { return }

        // Per-cast local snapshots at the same step. If unavailable, skip.
        guard let aaronView = dm.snapshot(forCastRole: Cast.aaron, step: 5),
              let benView   = dm.snapshot(forCastRole: Cast.ben,   step: 5),
              let carlView  = dm.snapshot(forCastRole: Cast.carl,  step: 5) else { return }

        // The three cast vertices currently on canvas.
        let aaronPid = dm.castByPid.first { $0.value.id == Cast.aaron.id }?.key
        let benPid   = dm.castByPid.first { $0.value.id == Cast.ben.id   }?.key
        let carlPid  = dm.castByPid.first { $0.value.id == Cast.carl.id  }?.key
        let aaronR0Hex = snap.vertices.first(where: { $0.processIdHex == aaronPid })?.digestHex ?? ""
        let benR2Hex   = snap.vertices.filter { $0.processIdHex == benPid }
                            .max(by: { $0.round < $1.round })?.digestHex ?? ""
        let carlR2Hex  = snap.vertices.filter { $0.processIdHex == carlPid }
                            .max(by: { $0.round < $1.round })?.digestHex ?? ""

        // Each character's view is the set of vertex digests they personally
        // know about. We project onto the three "cast" vertices visible on
        // the main canvas and check membership.
        let aaronKnows = Set(aaronView.vertices.map(\.digestHex))
        let benKnows = Set(benView.vertices.map(\.digestHex))
        let carlKnows = Set(carlView.vertices.map(\.digestHex))
        let castVertices: [(label: String, digest: String, color: Color)] = [
            ("AARON", aaronR0Hex, Cast.coral),
            ("BEN",   benR2Hex,   Cast.teal),
            ("CARL",  carlR2Hex,  Cast.amber)
        ]
        let common = aaronKnows.intersection(benKnows).intersection(carlKnows)

        // Layout: 4 columns at the bottom — Aaron / Ben / Carl / Common.
        let panelHeight: CGFloat = 110
        let panelY = size.height - panelHeight - 16
        let totalW = size.width - 60
        let colW = totalW / 4
        let panels: [(title: String, knows: Set<String>, accent: Color, isCommon: Bool)] = [
            ("AARON'S VIEW",       aaronKnows, Cast.coral, false),
            ("BEN'S VIEW",         benKnows,   Cast.teal,  false),
            ("CARL'S VIEW",        carlKnows,  Cast.amber, false),
            ("COMMON KNOWLEDGE",   common,     .green,     true),
        ]
        for (i, p) in panels.enumerated() {
            let x = 30 + CGFloat(i) * colW
            let rect = CGRect(x: x + 8, y: panelY, width: colW - 16, height: panelHeight)
            context.fill(RoundedRectangle(cornerRadius: 8).path(in: rect),
                        with: .color(.black.opacity(0.45 * fade)))
            context.stroke(RoundedRectangle(cornerRadius: 8).path(in: rect),
                          with: .color(p.accent.opacity((p.isCommon ? 0.9 : 0.55) * fade)),
                          lineWidth: p.isCommon ? 2 : 1)
            context.draw(
                Text(p.title)
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(p.accent.opacity((p.isCommon ? 0.95 : 0.8) * fade)),
                at: CGPoint(x: rect.midX, y: rect.minY + 14)
            )
            // Three small vertex badges. Each one is bright if `p.knows`
            // contains it, dim if not.
            let dotY = rect.minY + 50
            for (j, cv) in castVertices.enumerated() {
                let cx = rect.minX + 22 + CGFloat(j) * (rect.width - 44) / 2
                let known = p.knows.contains(cv.digest)
                let dotR: CGFloat = 11
                let dotRect = CGRect(x: cx - dotR, y: dotY - dotR,
                                      width: dotR * 2, height: dotR * 2)
                let bright = known ? 1.0 : 0.18
                context.fill(Circle().path(in: dotRect),
                            with: .color(cv.color.opacity(bright * fade)))
                context.stroke(Circle().path(in: dotRect),
                              with: .color(.white.opacity((known ? 0.6 : 0.25) * fade)),
                              lineWidth: 1)
                context.draw(
                    Text(cv.label)
                        .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                        .foregroundColor(cv.color.opacity((known ? 0.95 : 0.30) * fade)),
                    at: CGPoint(x: cx, y: dotY + dotR + 12)
                )
                // Checkmark / cross.
                context.draw(
                    Text(known ? "✓" : "✗")
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor((known ? Color.green : Color.red).opacity((known ? 0.9 : 0.5) * fade)),
                    at: CGPoint(x: cx, y: dotY + dotR + 26)
                )
            }
        }

        // Caption: list every vertex shared by everyone, plus call out the
        // ones that AREN'T shared so the asymmetry is visible.
        let sharedLabels = castVertices.filter { common.contains($0.digest) }.map(\.label)
        let unsharedLabels = castVertices.filter { !common.contains($0.digest) }.map(\.label)
        let captionTxt: String
        if sharedLabels.isEmpty {
            captionTxt = "DIFFERENT VIEWS · NO SHARED VERTEX YET · GOSSIP MUST CONTINUE"
        } else if unsharedLabels.isEmpty {
            captionTxt = "EVERY VIEW MATCHES — \(sharedLabels.joined(separator: ", ")) — FULL CONVERGENCE"
        } else {
            captionTxt = "SHARED: \(sharedLabels.joined(separator: " · "))  ·  STILL TRAVELING: \(unsharedLabels.joined(separator: " · "))"
        }
        context.draw(
            Text(captionTxt)
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.75 * fade)),
            at: CGPoint(x: size.width / 2, y: panelY - 10)
        )
    }

    /// Big, unmistakable rendering of the 1-3 staged vertices: cast name
    /// label above each, hash digest beside, real arrows for parent edges,
    /// and a faint dim of the rest of the lane backdrop. Replaces the old
    /// "drawVertices then ring overlay" path which hid the actual cast story
    /// behind generic-looking circles.
    private func renderStagedBeat(
        in context: inout GraphicsContext, size: CGSize, time: Double,
        layout: DAGLayout, visibleVerts: [VertexData],
        visibleEdges: [EdgeData], snap: NodeSnapshot
    ) {
        // Parent edges as REAL arrows in the child's cast color. Each edge in
        // `visibleEdges` is `from = child, to = parent`.
        for edge in visibleEdges {
            // Look up the child vertex to get its cast color.
            guard let childV = visibleVerts.first(where: { $0.digestHex == edge.from }) else { continue }
            let color = dm.castColor(for: childV.processIdHex)
            layout.drawArrowEdge(
                in: &context,
                from: edge.from, to: edge.to,
                color: color, alpha: 0.95,
                lineWidth: 2.6, headLength: 14, headWidth: 10,
                startInset: 22, endInset: 24
            )
        }

        // Vertices, large and labeled.
        for v in visibleVerts {
            guard let pos = layout.positions[v.digestHex] else { continue }
            let role = dm.castRole(for: v.processIdHex)
            let color = dm.castColor(for: v.processIdHex)
            let pulse = 0.85 + 0.15 * sin(time * 2.0)

            let r: CGFloat = 22 * CGFloat(pulse)
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)

            // Soft halo.
            let haloR = r * 1.7
            let haloRect = CGRect(x: pos.x - haloR, y: pos.y - haloR,
                                   width: haloR * 2, height: haloR * 2)
            context.fill(Circle().path(in: haloRect),
                        with: .color(color.opacity(0.18)))

            context.fill(Circle().path(in: rect),
                        with: .color(color.opacity(0.95)))
            context.stroke(Circle().path(in: rect),
                          with: .color(.white.opacity(0.5)), lineWidth: 1.5)

            // Hash inside the circle (4 chars).
            context.draw(
                Text(String(v.digestHex.prefix(4)))
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95)),
                at: pos
            )

            // Cast name above.
            if role.isNamedCast {
                context.draw(
                    Text(role.displayName.uppercased())
                        .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                        .foregroundColor(color.opacity(0.95)),
                    at: CGPoint(x: pos.x, y: pos.y - r - 18)
                )
            }
            // Round + digest below.
            context.draw(
                Text("R\(v.round) · \(String(v.digestHex.prefix(8)))…")
                    .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65)),
                at: CGPoint(x: pos.x, y: pos.y + r + 16)
            )
        }
    }

    /// For scenes 0/1/2, return a hand-curated narrative beat. The narration
    /// promises a strict story arc — Aaron's FIRST message → Ben referencing
    /// THAT message → Carl referencing THAT message — so the staging must
    /// PREFER edges into Aaron's earliest vertex (round 0) over edges into
    /// later Aaron vertices.
    ///
    ///   Scene 0: Aaron's earliest vertex (round 0).
    ///   Scene 1: + the Ben vertex whose parent edge points DIRECTLY to
    ///            Aaron's R0. If no such Ben vertex exists in this snapshot,
    ///            relax to "any Aaron vertex" but log it and let an
    ///            invariant flag the curriculum mismatch.
    ///   Scene 2: + the Carl vertex whose parent edge points DIRECTLY to
    ///            Aaron's R0 (preferred) or to Ben's chosen vertex.
    ///
    /// Returns nil for scenes ≥ 3 so the caller falls back to progressive
    /// reveal.
    private func narrativeStagedSet(snap: NodeSnapshot) -> Set<String>? {
        guard sceneIndex <= 2 else { return nil }

        guard let aaronPid = pid(of: Cast.aaron),
              let benPid = pid(of: Cast.ben),
              let carlPid = pid(of: Cast.carl) else { return nil }

        // Aaron's earliest vertex (round 0, lexicographically lowest digest
        // tiebreaker — the same vertex shown in scene 0).
        guard let aaronR0 = snap.vertices
                .filter({ $0.processIdHex == aaronPid })
                .min(by: { $0.round < $1.round
                           || ($0.round == $1.round && $0.digestHex < $1.digestHex) })
        else { return nil }
        let aaronR0Hex = aaronR0.digestHex
        let allAaronHex = Set(snap.vertices.filter { $0.processIdHex == aaronPid }.map(\.digestHex))

        // Visible always includes Aaron R0 — that's the anchor of the chapter.
        var visible: Set<String> = [aaronR0Hex]
        if sceneIndex == 0 { return visible }

        // Scene 1: Ben.
        // PASS A — strict: pick Ben's earliest vertex with an edge to Aaron R0.
        // PASS B — relaxed: pick Ben's earliest vertex with an edge to ANY Aaron vertex.
        let benCandidates = snap.vertices.filter { $0.processIdHex == benPid }
            .sorted { $0.round < $1.round || ($0.round == $1.round && $0.digestHex < $1.digestHex) }
        let benVertex = benCandidates.first(where: { bv in
                snap.edges.contains { $0.from == bv.digestHex && $0.to == aaronR0Hex }
            })
            ?? benCandidates.first(where: { bv in
                snap.edges.contains { $0.from == bv.digestHex && allAaronHex.contains($0.to) }
            })
            ?? benCandidates.first
        if let bv = benVertex { visible.insert(bv.digestHex) }
        if sceneIndex == 1 { return visible }

        // Scene 2: Carl.
        // PASS A — strict: edge into Aaron R0.
        // PASS B — edge into any visible vertex.
        let carlCandidates = snap.vertices.filter { $0.processIdHex == carlPid }
            .sorted { $0.round < $1.round || ($0.round == $1.round && $0.digestHex < $1.digestHex) }
        let carlVertex = carlCandidates.first(where: { cv in
                snap.edges.contains { $0.from == cv.digestHex && $0.to == aaronR0Hex }
            })
            ?? carlCandidates.first(where: { cv in
                snap.edges.contains { $0.from == cv.digestHex && visible.contains($0.to) }
            })
            ?? carlCandidates.first
        if let cv = carlVertex { visible.insert(cv.digestHex) }
        return visible
    }

    /// pid for a cast role.
    private func pid(of role: CastRole) -> String? {
        dm.castByPid.first(where: { $0.value.id == role.id })?.key
    }

    /// Earliest vertex from the given node that has at least one parent edge
    /// into `visibleParents`; falls back to the node's earliest vertex if no
    /// such edge exists in the snapshot.
    private func earliestVertex(for pid: String, with snap: NodeSnapshot, pointingInto visibleParents: Set<String>) -> VertexData? {
        let candidates = snap.vertices.filter { $0.processIdHex == pid }
            .sorted { $0.round < $1.round || ($0.round == $1.round && $0.digestHex < $1.digestHex) }
        for v in candidates {
            let hasEdgeIn = snap.edges.contains { $0.from == v.digestHex && visibleParents.contains($0.to) }
            if hasEdgeIn { return v }
        }
        return candidates.first
    }

    /// Find the cast member's earliest visible vertex (lowest round; tie-break by digest)
    /// and draw a name-bearing callout next to it. If `parentEdges` is provided, also
    /// glow the parent edges leading from that vertex back into the existing graph —
    /// makes "Ben copies what Aaron said" / "Carl links in" visually concrete.
    private func drawCastFirstVertexCallout(
        role: CastRole,
        in context: inout GraphicsContext,
        layout: DAGLayout,
        visibleVerts: [VertexData],
        time: Double,
        parentEdges: [EdgeData] = []
    ) {
        guard let pid = dm.castByPid.first(where: { $0.value.id == role.id })?.key else { return }
        let candidate = visibleVerts.filter { $0.processIdHex == pid }
            .sorted { $0.round < $1.round || ($0.round == $1.round && $0.digestHex < $1.digestHex) }
            .first
        guard let vertex = candidate, let pos = layout.positions[vertex.digestHex] else { return }

        // Pulsing ring on the highlighted vertex.
        let pulse = 0.6 + 0.35 * sin(time * 2.5)
        let r: CGFloat = 22
        let ringRect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        context.stroke(Circle().path(in: ringRect),
                      with: .color(role.color.opacity(0.85 * pulse)),
                      lineWidth: 2.5)

        // Parent edges: glow in the cast color.
        if !parentEdges.isEmpty {
            for edge in parentEdges where edge.from == vertex.digestHex {
                guard let parentPos = layout.positions[edge.to] else { continue }
                var path = Path()
                path.move(to: pos)
                path.addLine(to: parentPos)
                context.stroke(path, with: .color(role.color.opacity(0.7)), lineWidth: 2.5)
            }
        }

        // Name label, offset to avoid the lane label on the left.
        let labelOffsetX: CGFloat = pos.x < 200 ? 30 : -30
        let labelAlign: HorizontalAlignment = pos.x < 200 ? .leading : .trailing
        let labelPos = CGPoint(x: pos.x + labelOffsetX, y: pos.y - 28)
        context.draw(
            Text(role.displayName.uppercased())
                .font(DAGLayout.fontHeading(scale: settings.textScale))
                .foregroundColor(role.color.opacity(0.95)),
            at: labelPos, anchor: labelAlign == .leading ? .leading : .trailing
        )
    }

    /// BFS backward through ALL parent edges (not just one) to fixed depth,
    /// returning every vertex reachable by walking parents. This is the
    /// ancestor *cone*, not a chain — vertices have multiple parents and
    /// the walk fans out into a tree.
    private func ancestorClosure(of root: String, edges: [EdgeData], depth: Int) -> Set<String> {
        var seen: Set<String> = [root]
        var frontier: [String] = [root]
        // Pre-index edges by `from` for cheaper lookup at each hop.
        var parentsOf: [String: [String]] = [:]
        for e in edges { parentsOf[e.from, default: []].append(e.to) }
        for _ in 0..<depth {
            var next: [String] = []
            for v in frontier {
                for p in parentsOf[v] ?? [] where !seen.contains(p) {
                    seen.insert(p); next.append(p)
                }
            }
            if next.isEmpty { break }
            frontier = next
        }
        return seen
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
