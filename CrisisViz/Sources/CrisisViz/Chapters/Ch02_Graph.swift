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
            // Per-character perspective panel — at the TOP of the canvas
            // (the BOTTOM is reserved for `GlassNarration`, which would
            // otherwise hide the panel in the live app even though the MP4
            // testbed renders it). The "knows" set for each cast member is
            // derived from the parent edges of the currently visible
            // staged vertices, NOT from the full step-5 snapshot — so the
            // panel never names a vertex that isn't on screen.
            drawStagedPerspectivePanel(
                in: &context, size: size, time: time,
                visibleVerts: visibleVerts, visibleEdges: visibleEdges
            )

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
            // "Hashes are one-way" — slo-mo cast vignette. No dense graph;
            // we morph from the gossip script's α envelope into a SHA-256
            // demonstration. Lanes still draw underneath as the chapter's
            // visual through-line.
            renderHashOneWayVignette(in: &context, size: size, time: time)
            return

        case 5:
            // "Each player keeps a LOCAL DAG; same messages → same graph"
            // — slo-mo dual-pane comparison of Aaron's and Ben's local
            // views, populated from the same scripted messages used in
            // scene 3 so the chapter narrative carries forward.
            renderLocalDAGDeterminismVignette(in: &context, size: size, time: time)
            return

        case 6:
            // Ancestor cone — but walked back ONE LEVEL AT A TIME. The
            // earlier implementation revealed the entire cone instantly
            // (the user's "totally static" complaint); now depth grows
            // with `time` so the cone fans out in front of the viewer.
            renderAncestorConeWalk(
                in: &context, size: size, time: time,
                layout: layout, visibleVerts: visibleVerts,
                visibleEdges: visibleEdges
            )
            return

        default:
            layout.drawEdges(in: &context, edges: visibleEdges, alpha: 0.3, lineWidth: 1.2)
            layout.drawVertices(in: &context, vertices: visibleVerts, nodes: nodes, dm: dm, showLabels: true, textScale: settings.textScale)
        }

        // Vertex count — top right (the perspective panel now occupies the
        // top-center band on staged scenes, so the count is parked in the
        // corner where it doesn't fight for space).
        context.draw(
            Text("\(visCount)/\(allVertices.count) VERTICES · \(visibleEdges.count) EDGES")
                .font(DAGLayout.fontCaption(scale: settings.textScale))
                .foregroundColor(.white.opacity(0.25)),
            at: CGPoint(x: size.width - 130, y: 16)
        )
    }

    // MARK: - Scene 4: hash one-way vignette

    /// Slow-motion demonstration of the "hash is a one-way function"
    /// pedagogy. Carries Aaron's α envelope from the gossip script forward
    /// (visual continuity with scene 3) and stages four beats:
    ///
    ///   t=0..1.5    α envelope slides into view from the left
    ///   t=1.5..3.0  payload lines reveal one by one, then SHA arrow appears
    ///   t=3.0..5.0  reverse arrow attempt — red ✗, "PREIMAGE IMPOSSIBLE"
    ///   t=5.0..7.0  forward arrow restored — green ✓, "VERIFY DETERMINISTIC"
    ///   t=7.0..8.0  bridge-line to chapter 8 (data availability)
    private func renderHashOneWayVignette(
        in context: inout GraphicsContext, size: CGSize, time: Double
    ) {
        // The same α from GossipScript so the cast continuity is intact.
        let alpha = GossipScript.ch01.messages.first { $0.id == "α" }!
        let cardW: CGFloat = min(360, size.width * 0.30)
        let cardH: CGFloat = 200
        let cy: CGFloat = size.height * 0.52
        let cardX: CGFloat = size.width * 0.18
        let cardRect = CGRect(x: cardX, y: cy - cardH / 2,
                              width: cardW, height: cardH)

        // Slide-in interpolation (eased)
        let slideRaw = max(0, min(1, time / 1.5))
        let slideEased = 1 - pow(1 - slideRaw, 3)
        let cardOpacity = slideEased
        let actualX = cardX - 80 * (1 - slideEased)
        let drawnRect = cardRect.offsetBy(dx: actualX - cardX, dy: 0)

        // Card background
        context.fill(RoundedRectangle(cornerRadius: 14).path(in: drawnRect),
                    with: .color(.black.opacity(0.7 * cardOpacity)))
        context.stroke(RoundedRectangle(cornerRadius: 14).path(in: drawnRect),
                      with: .color(Cast.coral.opacity(0.85 * cardOpacity)),
                      lineWidth: 1.5)

        // Card title
        context.draw(
            Text("MESSAGE α — AARON")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(Cast.coral.opacity(0.95 * cardOpacity)),
            at: CGPoint(x: drawnRect.midX, y: drawnRect.minY + 18)
        )

        // Payload lines fade in serially between t=1.5 and 3.0
        let lines = [
            "from: aaron",
            "round: 0",
            "parents: []",
            "payload: \(alpha.payload)",
        ]
        for (i, line) in lines.enumerated() {
            let lineFade = max(0, min(1, (time - 1.5 - Double(i) * 0.25) / 0.4))
            context.draw(
                Text(line)
                    .font(.system(size: settings.scaled(10), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85 * lineFade)),
                at: CGPoint(x: drawnRect.minX + 16 + 70,
                            y: drawnRect.minY + 50 + CGFloat(i) * 22)
            )
        }

        // Hash bubble to the right of the card
        let hashFade = max(0, min(1, (time - 2.6) / 0.6))
        let hashBubbleW: CGFloat = 200
        let hashBubbleH: CGFloat = 80
        let hashCenter = CGPoint(x: drawnRect.maxX + 220, y: drawnRect.midY)
        let hashRect = CGRect(x: hashCenter.x - hashBubbleW / 2,
                              y: hashCenter.y - hashBubbleH / 2,
                              width: hashBubbleW, height: hashBubbleH)
        context.fill(RoundedRectangle(cornerRadius: 10).path(in: hashRect),
                    with: .color(.black.opacity(0.7 * hashFade)))
        context.stroke(RoundedRectangle(cornerRadius: 10).path(in: hashRect),
                      with: .color(.white.opacity(0.5 * hashFade)),
                      lineWidth: 1.2)
        context.draw(
            Text("hash(α)")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.7 * hashFade)),
            at: CGPoint(x: hashRect.midX, y: hashRect.minY + 16)
        )
        context.draw(
            Text("\(alpha.hashShort)…")
                .font(.system(size: settings.scaled(18), weight: .heavy, design: .monospaced))
                .foregroundColor(Cast.coral.opacity(0.95 * hashFade)),
            at: CGPoint(x: hashRect.midX, y: hashRect.midY + 6)
        )
        context.draw(
            Text("(SHA-256)")
                .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.4 * hashFade)),
            at: CGPoint(x: hashRect.midX, y: hashRect.maxY - 12)
        )

        // Forward arrow body → hash
        let arrowFade = hashFade
        var fwd = Path()
        let fwdStart = CGPoint(x: drawnRect.maxX + 8, y: drawnRect.midY)
        let fwdEnd   = CGPoint(x: hashRect.minX - 8, y: hashRect.midY)
        fwd.move(to: fwdStart)
        fwd.addLine(to: fwdEnd)
        let goodPhase = time > 5.0
        let fwdColor: Color = goodPhase ? .green : .white
        context.stroke(fwd, with: .color(fwdColor.opacity(0.8 * arrowFade)), lineWidth: 2.0)
        // Arrowhead
        let head1 = CGPoint(x: fwdEnd.x - 10, y: fwdEnd.y - 6)
        let head2 = CGPoint(x: fwdEnd.x - 10, y: fwdEnd.y + 6)
        var headPath = Path()
        headPath.move(to: fwdEnd); headPath.addLine(to: head1)
        headPath.move(to: fwdEnd); headPath.addLine(to: head2)
        context.stroke(headPath, with: .color(fwdColor.opacity(0.8 * arrowFade)), lineWidth: 2.0)

        // Reverse arrow during 3.0..5.0
        if time > 3.0 {
            let revFade = max(0, min(1, (time - 3.0) / 0.6))
            // Hide the reverse during forward-verify phase (after 5.0)
            let revAlive = max(0, min(1, (5.0 - time) / 0.6))
            let revOpacity = revFade * (time < 5.0 ? 1.0 : revAlive)
            var rev = Path()
            let revStart = CGPoint(x: hashRect.minX - 8, y: hashRect.midY + 22)
            let revEnd   = CGPoint(x: drawnRect.maxX + 8, y: drawnRect.midY + 22)
            rev.move(to: revStart)
            rev.addLine(to: revEnd)
            let dashed = StrokeStyle(lineWidth: 2.0, dash: [6, 4])
            context.stroke(rev, with: .color(.red.opacity(0.85 * revOpacity)),
                          style: dashed)
            // Big red ✗ at midpoint
            let mid = CGPoint(x: (revStart.x + revEnd.x) / 2,
                              y: (revStart.y + revEnd.y) / 2)
            context.draw(
                Text("✗")
                    .font(.system(size: settings.scaled(28), weight: .heavy, design: .monospaced))
                    .foregroundColor(.red.opacity(revOpacity)),
                at: mid
            )
            context.draw(
                Text("PREIMAGE IMPOSSIBLE — HASH ALONE TELLS YOU NOTHING")
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(.red.opacity(0.9 * revOpacity)),
                at: CGPoint(x: size.width / 2, y: drawnRect.maxY + 36)
            )
        }

        // Forward verify ✓ at 5.0..7.0
        if time > 5.0 {
            let verFade = max(0, min(1, (time - 5.0) / 0.6))
            context.draw(
                Text("✓")
                    .font(.system(size: settings.scaled(20), weight: .heavy, design: .monospaced))
                    .foregroundColor(.green.opacity(0.95 * verFade)),
                at: CGPoint(x: (fwdStart.x + fwdEnd.x) / 2, y: drawnRect.midY - 22)
            )
            context.draw(
                Text("VERIFY: BODY → HASH IS DETERMINISTIC. RECEIVERS RECOMPUTE THE HASH AND CHECK IT MATCHES.")
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(.green.opacity(0.9 * verFade)),
                at: CGPoint(x: size.width / 2, y: drawnRect.maxY + 36)
            )
        }

        // Bridge-line to Ch08 at the bottom
        if time > 7.0 {
            let endFade = max(0, min(1, (time - 7.0) / 0.6))
            context.draw(
                Text("→ DATA AVAILABILITY (CHAPTER 8) IS WHY THIS MATTERS:  IF YOU LOSE THE BODY YOU CAN'T VERIFY ANYTHING.")
                    .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.85 * endFade)),
                at: CGPoint(x: size.width / 2, y: size.height - 56)
            )
        }
    }

    // MARK: - Scene 5: local DAG / determinism vignette

    /// Two parallel "local DAG" panes — one for Aaron, one for Ben — that
    /// fill in identically as gossip catches up. The lesson is "same set
    /// of messages received → same graph computed". Uses the SAME α/β/γ
    /// scripted messages from scene 3 so the chapter's gossip story
    /// continues uninterrupted.
    private func renderLocalDAGDeterminismVignette(
        in context: inout GraphicsContext, size: CGSize, time: Double
    ) {
        let paneWidth: CGFloat = (size.width - 100) / 2
        let paneHeight: CGFloat = size.height * 0.55
        let paneY: CGFloat = size.height * 0.20
        let leftPaneX: CGFloat = 30
        let rightPaneX: CGFloat = size.width - 30 - paneWidth

        // Slide-in fade
        let slideRaw = max(0, min(1, time / 1.0))
        let slideOpacity = pow(slideRaw, 1.4)

        // Each pane's "received timeline" — when each message arrives.
        // Aaron's: α at t=2 (his own), β at t=4 (Ben gossips), γ at t=6 (Carl gossips).
        // Ben's:   α at t=2.5 (received), β at t=4 (his own), γ at t=6 (Carl gossips).
        // Identical FINAL state at t=6+; identical visualization confirms determinism.
        struct ReceiveEvent { let id: String; let t: Double; let color: Color }
        let aaronTimeline: [ReceiveEvent] = [
            ReceiveEvent(id: "α", t: 2.0, color: Cast.coral),
            ReceiveEvent(id: "β", t: 4.0, color: Cast.teal),
            ReceiveEvent(id: "γ", t: 6.0, color: Cast.amber),
        ]
        let benTimeline: [ReceiveEvent] = [
            ReceiveEvent(id: "α", t: 2.5, color: Cast.coral),
            ReceiveEvent(id: "β", t: 4.0, color: Cast.teal),
            ReceiveEvent(id: "γ", t: 6.0, color: Cast.amber),
        ]

        func drawPane(label: String, accent: Color, x: CGFloat, timeline: [ReceiveEvent]) {
            let rect = CGRect(x: x, y: paneY, width: paneWidth, height: paneHeight)
            context.fill(RoundedRectangle(cornerRadius: 14).path(in: rect),
                        with: .color(.black.opacity(0.45 * slideOpacity)))
            context.stroke(RoundedRectangle(cornerRadius: 14).path(in: rect),
                          with: .color(accent.opacity(0.7 * slideOpacity)),
                          lineWidth: 1.5)
            context.draw(
                Text(label)
                    .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                    .foregroundColor(accent.opacity(0.95 * slideOpacity)),
                at: CGPoint(x: rect.midX, y: rect.minY + 22)
            )
            // Three vertex slots laid out left → right inside the pane.
            for (i, evt) in timeline.enumerated() {
                let slotX = rect.minX + 60 + CGFloat(i) * (rect.width - 120) / 2
                let slotY = rect.midY + 6
                let arrived = max(0, min(1, (time - evt.t) / 0.6))
                let r: CGFloat = 28
                let circleRect = CGRect(x: slotX - r, y: slotY - r, width: r * 2, height: r * 2)
                // Empty placeholder ring before arrival
                context.stroke(Circle().path(in: circleRect),
                              with: .color(.white.opacity(0.18 * slideOpacity)),
                              lineWidth: 1.0)
                if arrived > 0 {
                    context.fill(Circle().path(in: circleRect),
                                with: .color(evt.color.opacity(0.85 * arrived)))
                    context.stroke(Circle().path(in: circleRect),
                                  with: .color(.white.opacity(0.5 * arrived)),
                                  lineWidth: 1.4)
                    context.draw(
                        Text(evt.id)
                            .font(.system(size: settings.scaled(20), weight: .heavy, design: .monospaced))
                            .foregroundColor(.white.opacity(arrived)),
                        at: CGPoint(x: slotX, y: slotY)
                    )
                }
                // Parent edge α → β, α → γ, drawn in once both endpoints have arrived.
                if i > 0 {
                    let bothArrived = arrived > 0.6 && (time - timeline[0].t) / 0.6 > 0.6
                    if bothArrived {
                        let prevX = rect.minX + 60
                        let edgeFade = max(0, min(1, (time - evt.t - 0.4) / 0.6))
                        var path = Path()
                        path.move(to: CGPoint(x: slotX - r - 1, y: slotY))
                        path.addLine(to: CGPoint(x: prevX + r + 1, y: slotY))
                        context.stroke(path,
                                      with: .color(.white.opacity(0.45 * edgeFade)),
                                      lineWidth: 1.4)
                    }
                }
            }
        }
        drawPane(label: "AARON'S LOCAL DAG", accent: Cast.coral,
                 x: leftPaneX, timeline: aaronTimeline)
        drawPane(label: "BEN'S LOCAL DAG", accent: Cast.teal,
                 x: rightPaneX, timeline: benTimeline)

        // Convergence flash + caption once both panes are fully populated.
        let aaronComplete = aaronTimeline.allSatisfy { time >= $0.t + 0.6 }
        let benComplete = benTimeline.allSatisfy { time >= $0.t + 0.6 }
        if aaronComplete && benComplete {
            let convergeFade = max(0, min(1, (time - max(aaronTimeline.last!.t,
                                                          benTimeline.last!.t) - 0.4) / 0.8))
            let pulse = 0.7 + 0.3 * sin(time * 2)
            context.draw(
                Text("SAME MESSAGES → SAME GRAPH — BYTE-FOR-BYTE")
                    .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                    .foregroundColor(.green.opacity(0.95 * convergeFade * pulse)),
                at: CGPoint(x: size.width / 2, y: paneY + paneHeight + 30)
            )
            // Equality bar between the panes.
            let barY = size.height / 2
            var bar = Path()
            bar.move(to: CGPoint(x: leftPaneX + paneWidth + 4, y: barY - 6))
            bar.addLine(to: CGPoint(x: rightPaneX - 4, y: barY - 6))
            bar.move(to: CGPoint(x: leftPaneX + paneWidth + 4, y: barY + 6))
            bar.addLine(to: CGPoint(x: rightPaneX - 4, y: barY + 6))
            context.stroke(bar,
                          with: .color(.green.opacity(0.85 * convergeFade)),
                          lineWidth: 2.0)
        } else {
            context.draw(
                Text("EACH PLAYER BUILDS THEIR OWN LOCAL DAG. GOSSIP DELIVERS THE SAME MESSAGES TO BOTH.")
                    .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65 * slideOpacity)),
                at: CGPoint(x: size.width / 2, y: paneY + paneHeight + 30)
            )
        }
    }

    // MARK: - Scene 6: ancestor cone walk-back

    /// Slow walk back from a chosen leaf vertex, expanding the ancestor
    /// cone ONE LEVEL per second instead of revealing it all at once. Cast
    /// vertices in the cone get cast-colored highlights so Aaron/Ben/Carl
    /// can be tracked across hops; pure-peer ancestors stay in yellow.
    private func renderAncestorConeWalk(
        in context: inout GraphicsContext, size: CGSize, time: Double,
        layout: DAGLayout, visibleVerts: [VertexData], visibleEdges: [EdgeData]
    ) {
        // Background graph at very low alpha — gives the cone something
        // to stand against without competing for attention.
        layout.drawEdges(in: &context, edges: visibleEdges, alpha: 0.15, lineWidth: 0.9)
        layout.drawVertices(
            in: &context, vertices: visibleVerts,
            nodes: dm.castOrderedNodes(), dm: dm,
            showLabels: false, textScale: settings.textScale
        )

        // Pick the leaf — prefer Aaron's latest visible vertex so the
        // walk-back reads as "Aaron's history".
        let aaronPid = pid(of: Cast.aaron)
        let aaronLeaf = visibleVerts.filter { $0.processIdHex == aaronPid }
            .max { $0.round < $1.round }
        let leaf = aaronLeaf ?? visibleVerts.max { $0.round < $1.round }
        guard let leaf else { return }
        guard let leafPos = layout.positions[leaf.digestHex] else { return }

        // BFS layers from the leaf outward — done UP-FRONT so we can pace
        // the reveal to fit the 8-second scene regardless of cone depth.
        var layersByDepth: [[String]] = [[leaf.digestHex]]
        var seen: Set<String> = [leaf.digestHex]
        var frontier: [String] = [leaf.digestHex]
        let maxDepth = 8
        for _ in 0..<maxDepth {
            var next: [String] = []
            for hex in frontier {
                for e in visibleEdges where e.from == hex {
                    if !seen.contains(e.to) {
                        seen.insert(e.to)
                        next.append(e.to)
                    }
                }
            }
            if next.isEmpty { break }
            layersByDepth.append(next)
            frontier = next
        }

        // Pace the reveal so the full cone finishes within the 8-second
        // scene window: warmup + totalDepth × levelTime ≈ 7 seconds, leaving
        // ~1 second for the genesis-star fade-in to read clearly.
        let totalDepthLayers = max(1, layersByDepth.count - 1)
        let warmup: Double = 1.0
        let levelTime: Double = max(0.6, (7.0 - warmup) / Double(totalDepthLayers))
        let depthRaw = max(0, (time - warmup) / levelTime)
        let depthFloor = Int(depthRaw)
        let levelProgress = max(0, min(1, depthRaw - Double(depthFloor)))

        // Highlight leaf
        let leafHaloPulse = 0.6 + 0.3 * sin(time * 2.4)
        let leafR: CGFloat = 22
        context.stroke(
            Circle().path(in: CGRect(x: leafPos.x - leafR, y: leafPos.y - leafR,
                                      width: leafR * 2, height: leafR * 2)),
            with: .color(.yellow.opacity(0.95 * leafHaloPulse)),
            lineWidth: 2.5
        )
        context.draw(
            Text("LEAF — TRACE STARTS HERE")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.95)),
            at: CGPoint(x: leafPos.x, y: leafPos.y - 32)
        )

        // For each completed depth, draw edges + halo at full strength.
        // For the current depth-in-progress, fade in proportionally.
        for d in 1...max(1, depthFloor + 1) {
            guard d < layersByDepth.count else { break }
            let isCurrent = (d == depthFloor + 1)
            let alpha: Double = isCurrent ? Double(levelProgress) : 1.0
            // Edges from the previous layer's vertices into this layer
            for hex in layersByDepth[d] {
                guard let pos = layout.positions[hex] else { continue }
                let r: CGFloat = 14
                // Cast color ring if hex belongs to a cast member
                let castColor = castColorForVertex(hex: hex)
                let ringColor = castColor ?? .yellow
                context.stroke(
                    Circle().path(in: CGRect(x: pos.x - r, y: pos.y - r,
                                              width: r * 2, height: r * 2)),
                    with: .color(ringColor.opacity(0.8 * alpha)),
                    lineWidth: 1.8
                )
                // Edge from this vertex back to whichever ancestor in layer d-1 sent the
                // gossip — practically: any edge.from this hex to a vertex in layer d-1.
                for e in visibleEdges where e.from == hex && layersByDepth[d - 1].contains(e.to) {
                    layout.drawArrowEdge(
                        in: &context,
                        from: e.from, to: e.to,
                        color: ringColor, alpha: 0.85 * alpha,
                        lineWidth: 1.8,
                        headLength: 8, headWidth: 5,
                        startInset: 13, endInset: 13
                    )
                }
            }
        }

        // Genesis stars when the BFS is fully expanded.
        let totalDepthSteps = totalDepthLayers
        let revealedAll = depthFloor >= totalDepthSteps
        if revealedAll {
            let genesisFade = max(0, min(1, (time - warmup - Double(totalDepthSteps) * levelTime - 0.2) / 0.6))
            // A "genesis" vertex is one in the cone whose outgoing parent edges
            // (within visibleEdges) all leave the cone — it doesn't point
            // back further within the cone we have on screen.
            let coneSet = seen
            let genesisHexes = coneSet.filter { d in
                !visibleEdges.contains { $0.from == d && coneSet.contains($0.to) }
            }
            for hex in genesisHexes {
                if let pos = layout.positions[hex] {
                    context.draw(
                        Text("★ GENESIS")
                            .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.95 * genesisFade)),
                        at: CGPoint(x: pos.x, y: pos.y + 24)
                    )
                }
            }
        }

        // Caption tracks the current depth so the viewer can pace.
        let depthLabel: String
        if depthFloor == 0 {
            depthLabel = "DEPTH 0 — JUST THE LEAF"
        } else if revealedAll {
            depthLabel = "REACHED GENESIS — \(seen.count) ANCESTORS · \(layersByDepth.count - 1) HOPS"
        } else {
            depthLabel = "WALKING BACK · DEPTH \(depthFloor) → \(depthFloor + 1)"
        }
        context.draw(
            Text(depthLabel)
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.85)),
            at: CGPoint(x: size.width / 2, y: size.height - 56)
        )
    }

    private func castColorForVertex(hex: String) -> Color? {
        guard let snap = dm.honestData(step: 5) else { return nil }
        guard let v = snap.vertices.first(where: { $0.digestHex == hex }) else { return nil }
        guard let role = dm.castByPid[v.processIdHex] else { return nil }
        switch role.id {
        case Cast.aaron.id: return Cast.coral
        case Cast.ben.id:   return Cast.teal
        case Cast.carl.id:  return Cast.amber
        case Cast.dave.id:  return Cast.violet
        default:            return nil
        }
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
        // Cast positions sit BELOW the perspective panel band (panel spans
        // y=14..110 + caption at y=120). The lower triangle keeps Aaron/Ben
        // above the dramatization mid-band and Carl in the lower third.
        let layout: [GossipScript.CastRoleKey: CGPoint] = [
            .aaron: CGPoint(x: cx - size.width * 0.30, y: size.height * 0.34),
            .ben:   CGPoint(x: cx + size.width * 0.30, y: size.height * 0.34),
            .carl:  CGPoint(x: cx,                     y: size.height * 0.70),
        ]

        // Tiny clock in the bottom-right so the user can pace the scene
        // without the title fighting the perspective panel for top space.
        context.draw(
            Text(String(format: "t=%.1fs / %.0fs", time, script.totalDuration))
                .font(.system(size: settings.scaled(9), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.30)),
            at: CGPoint(x: size.width - 64, y: size.height - 12)
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

        // Perspective panel at the top — same component used by the staged
        // scenes 0/1/2, just fed from the live `GossipScript` state. A
        // message counts as "known" once the receive beat has finished
        // (progress = 1.0); authors know their own message immediately on
        // sealHash. This makes the asymmetric arrival timing visible at a
        // glance ("Carl writes γ before β arrives" → COMMON KNOWLEDGE
        // contains only α even after Ben writes β).
        let items: [PanelItem] = [
            PanelItem(label: "α", id: "α", color: Cast.coral),
            PanelItem(label: "β", id: "β", color: Cast.teal),
            PanelItem(label: "γ", id: "γ", color: Cast.amber),
        ]
        func gossipKnows(_ key: GossipScript.CastRoleKey) -> Set<String> {
            let view = world.views[key] ?? GossipScript.ViewState()
            return Set(view.received.compactMap { $0.value >= 1.0 ? $0.key : nil })
        }
        drawPerspectivePanel(
            in: &context, size: size, time: time,
            items: items,
            aaronKnows: gossipKnows(.aaron),
            benKnows:   gossipKnows(.ben),
            carlKnows:  gossipKnows(.carl)
        )
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

    // MARK: - Perspective panel (Aaron/Ben/Carl/Common)

    /// Compact display item for a vertex referenced by the panel.
    private struct PanelItem {
        let label: String
        let id: String          // digest hex, or scripted message id ("α"/"β"/"γ")
        let color: Color
    }

    /// Top-of-canvas perspective panel. Shows what each cast member has seen
    /// so far + the common nucleus, regardless of whether the underlying
    /// data is staged DAG vertices (scenes 0-2) or scripted gossip messages
    /// (scene 3). Lives at the TOP of the canvas because the LIVE app
    /// overlays `GlassNarration` at the bottom — anything drawn at the
    /// bottom of the canvas would be hidden in the running app even if the
    /// MP4 testbed (no overlay) renders it just fine.
    private func drawPerspectivePanel(
        in context: inout GraphicsContext, size: CGSize, time: Double,
        items: [PanelItem],
        aaronKnows: Set<String>,
        benKnows: Set<String>,
        carlKnows: Set<String>,
        fadeStart: Double = 0.4,
        fadeDuration: Double = 1.0
    ) {
        let fade = max(0, min(1, (time - fadeStart) / fadeDuration))
        if fade < 0.05 { return }

        let common = aaronKnows.intersection(benKnows).intersection(carlKnows)
        let panels: [(title: String, knows: Set<String>, accent: Color, isCommon: Bool)] = [
            ("AARON'S VIEW",     aaronKnows, Cast.coral, false),
            ("BEN'S VIEW",       benKnows,   Cast.teal,  false),
            ("CARL'S VIEW",      carlKnows,  Cast.amber, false),
            ("COMMON KNOWLEDGE", common,     .green,     true),
        ]
        let panelHeight: CGFloat = 96
        let panelY: CGFloat = 14   // top edge — clears narration overlay below
        let totalW = size.width - 60
        let colW = totalW / 4

        for (i, p) in panels.enumerated() {
            let x = 30 + CGFloat(i) * colW
            let rect = CGRect(x: x + 8, y: panelY, width: colW - 16, height: panelHeight)
            context.fill(RoundedRectangle(cornerRadius: 8).path(in: rect),
                        with: .color(.black.opacity(0.55 * fade)))
            context.stroke(RoundedRectangle(cornerRadius: 8).path(in: rect),
                          with: .color(p.accent.opacity((p.isCommon ? 0.9 : 0.55) * fade)),
                          lineWidth: p.isCommon ? 2 : 1)
            context.draw(
                Text(p.title)
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(p.accent.opacity((p.isCommon ? 0.95 : 0.8) * fade)),
                at: CGPoint(x: rect.midX, y: rect.minY + 14)
            )
            let dotY = rect.minY + 46
            // Distribute up to 3 item dots evenly across the column. We use
            // a fixed slot width so panels with 1 or 2 items stay aligned.
            for (j, cv) in items.enumerated() {
                let slotCount = max(1, items.count - 1)
                let cx = rect.minX + 26 + CGFloat(j) * (rect.width - 52) / CGFloat(slotCount)
                let known = p.knows.contains(cv.id)
                let dotR: CGFloat = 10
                let dotRect = CGRect(x: cx - dotR, y: dotY - dotR,
                                      width: dotR * 2, height: dotR * 2)
                let bright = known ? 1.0 : 0.16
                context.fill(Circle().path(in: dotRect),
                            with: .color(cv.color.opacity(bright * fade)))
                context.stroke(Circle().path(in: dotRect),
                              with: .color(.white.opacity((known ? 0.6 : 0.22) * fade)),
                              lineWidth: 1)
                context.draw(
                    Text(cv.label)
                        .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                        .foregroundColor(cv.color.opacity((known ? 0.95 : 0.28) * fade)),
                    at: CGPoint(x: cx, y: dotY + dotR + 10)
                )
                context.draw(
                    Text(known ? "✓" : "✗")
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor((known ? Color.green : Color.red).opacity((known ? 0.9 : 0.5) * fade)),
                    at: CGPoint(x: cx, y: dotY + dotR + 22)
                )
            }
        }

        // Caption directly under the panel band, summarizing the convergence
        // state in one line.
        let sharedLabels = items.filter { common.contains($0.id) }.map(\.label)
        let unsharedLabels = items.filter { !common.contains($0.id) }.map(\.label)
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
            at: CGPoint(x: size.width / 2, y: panelY + panelHeight + 10)
        )
    }

    /// Staged-scene perspective panel (scenes 0/1/2). Derives each cast
    /// member's "knows" set from the actual visible vertices + parent edges
    /// so the panel never claims someone has seen a vertex that isn't on
    /// screen. Each cast member knows:
    ///   - their own staged vertex (if visible), and
    ///   - every visible vertex their staged vertex points to as a parent.
    ///
    /// Scene 0 (Aaron alone): Aaron knows {α}; Ben/Carl know nothing.
    /// Scene 1 (+Ben): Aaron knows {α}; Ben knows {α, β}; Carl nothing.
    /// Scene 2 (+Carl): Aaron knows {α}; Ben knows {α, β}; Carl knows {α, γ};
    ///                  COMMON = {α} (β and γ are still in flight).
    private func drawStagedPerspectivePanel(
        in context: inout GraphicsContext, size: CGSize, time: Double,
        visibleVerts: [VertexData], visibleEdges: [EdgeData]
    ) {
        guard let aaronPid = pid(of: Cast.aaron),
              let benPid   = pid(of: Cast.ben),
              let carlPid  = pid(of: Cast.carl) else { return }

        // Each cast member's chosen staged vertex (their earliest visible).
        let aaronVerts = visibleVerts.filter { $0.processIdHex == aaronPid }
        let benVerts   = visibleVerts.filter { $0.processIdHex == benPid }
        let carlVerts  = visibleVerts.filter { $0.processIdHex == carlPid }
        let aaronVx = aaronVerts.min(by: { $0.round < $1.round })
        let benVx   = benVerts.min(by:   { $0.round < $1.round })
        let carlVx  = carlVerts.min(by:  { $0.round < $1.round })

        // Build "knows" sets edge-locally: each cast member knows their own
        // vertex plus every visible parent it references.
        func knowsOf(_ vx: VertexData?) -> Set<String> {
            guard let vx else { return [] }
            var set: Set<String> = [vx.digestHex]
            for e in visibleEdges where e.from == vx.digestHex {
                set.insert(e.to)
            }
            return set
        }
        let aaronKnows = knowsOf(aaronVx)
        let benKnows   = knowsOf(benVx)
        let carlKnows  = knowsOf(carlVx)

        // Items always show all three cast slots so the panel layout stays
        // stable across scenes 0/1/2 (only the dot brightness changes).
        let items: [PanelItem] = [
            PanelItem(label: "AARON", id: aaronVx?.digestHex ?? "—", color: Cast.coral),
            PanelItem(label: "BEN",   id: benVx?.digestHex   ?? "—", color: Cast.teal),
            PanelItem(label: "CARL",  id: carlVx?.digestHex  ?? "—", color: Cast.amber),
        ]
        drawPerspectivePanel(
            in: &context, size: size, time: time,
            items: items,
            aaronKnows: aaronKnows, benKnows: benKnows, carlKnows: carlKnows
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
