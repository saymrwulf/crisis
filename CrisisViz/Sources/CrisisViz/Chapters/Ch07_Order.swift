import SwiftUI

/// Ch06 (file Ch07_Order, user-facing chapter index 6): "Spokespersons line
/// up. Everyone else falls in behind."
///
/// This is the masterclass scene — the visible *emergence* of total order
/// from the DAG. Three pedagogical beats:
///
///   - Scene 0 ("Sorting the DAG into a line."): the empty timeline appears
///     across the bottom, a leader-position cursor sweeps left to right, and
///     the FIRST few ordered vertices peel off the DAG into the line so the
///     mechanism is unambiguous. Aaron's, Ben's and Carl's earliest contributions
///     are named on landing.
///
///   - Scene 1 ("Vertices slide into their place."): wave-pull. Each round's
///     ordered vertices fly to their slots in succession, with cast-colored
///     tracer lines so the viewer SEES who went where. Round zones appear on
///     the strip as vertices land in them.
///
///   - Scene 2 ("Everyone produces the same line."): the whole ordered prefix
///     is on the strip; a verification badge confirms Aaron's line equals
///     Ben's line equals Carl's line — this is convergence, made visible.
struct Ch07_Order: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    // Post-convergence step. The 80-step simulation first produces ordered
    // vertices at step 38 and reaches a stable converged prefix from step 40
    // onwards; we pick step 60 so a substantial ordered prefix is available
    // to slide into the "snake" line.
    private let dataStep = 60

    /// Cap the visible-on-strip count so the line stays readable. Beyond
    /// ~40 vertices the strip gets too dense for a teaching frame.
    private let maxStripCount = 40

    var body: some View {
        Canvas { context, size in
            render(context: &context, size: size, time: localTime)
        }
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard dm.sim != nil,
              let snap = dm.honestData(step: dataStep) else { return }

        let lanes = dm.castOrderedNodes()
        let allVertices = snap.vertices
        let allEdges = snap.edges

        // First N ordered vertices, sorted by totalPosition.
        let orderedAll = allVertices.filter { $0.totalPosition != nil }
            .sorted { ($0.totalPosition ?? 0) < ($1.totalPosition ?? 0) }
        let ordered = Array(orderedAll.prefix(maxStripCount))
        let orderedSet = Set(ordered.map(\.digestHex))
        let unordered = allVertices.filter { !orderedSet.contains($0.digestHex) }

        // DAG layout is the *source* (vertex pre-slide positions on their lanes).
        let layout = DAGLayout.compute(
            vertices: allVertices, edges: allEdges, nodes: lanes,
            canvasSize: size, margin: 60
        )

        // Strip geometry — single row of slots above the bottom narration band.
        let stripY: CGFloat = size.height - 220
        let stripMargin: CGFloat = 40
        let stripWidth = size.width - stripMargin * 2
        let slotSpacing = stripWidth / CGFloat(max(ordered.count, 1))

        // Per-vertex slide progress. Wave animation: vertex i begins sliding
        // at staggerStart_i, taking `pullDuration` to land. Scene 0 reveals
        // only the first few; Scene 1 floods; Scene 2 holds the final state.
        let pullDuration: Double = 0.9
        let stagger: Double = sceneIndex == 0 ? 0.4 : 0.18
        let revealLimit: Int
        switch sceneIndex {
        case 0: revealLimit = min(ordered.count, max(3, Int(time / 1.6) + 3))
        case 1: revealLimit = ordered.count
        default: revealLimit = ordered.count
        }
        let timeOffsetForLandingAll: Double = sceneIndex == 2 ? 0.0 : Double(ordered.count) * stagger + pullDuration

        // Background DAG (dimmed as the snake assembles).
        let bgFade = sceneIndex == 0
            ? 0.55
            : max(0.10, 0.55 - 0.45 * min(1.0, time / 4.0))
        layout.drawNodeLanes(in: &context, nodes: lanes, canvasSize: size, dm: dm,
                             textScale: settings.textScale)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: 0,
                                    alpha: 0.18 * bgFade, textScale: settings.textScale)
        layout.drawEdges(in: &context, edges: allEdges,
                         alpha: max(0.04, 0.22 * bgFade))

        // Unordered vertices stay in their lanes, dimmed.
        for v in unordered {
            guard let pos = layout.positions[v.digestHex] else { continue }
            let r: CGFloat = 5 + CGFloat(min(v.weight, 8)) * 0.6
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            let baseColor = dm.castColor(for: v.processIdHex)
            context.fill(Circle().path(in: rect), with: .color(baseColor.opacity(0.30 * bgFade)))
        }

        // The strip itself — empty slot row that holds positions even before
        // anything has landed. Visible from t=0 in every scene so the viewer
        // sees the "destination" before the first vertex flies.
        drawStripBackdrop(in: &context, size: size, stripY: stripY,
                          stripMargin: stripMargin, slotSpacing: slotSpacing,
                          slotCount: ordered.count, time: time)

        // Per-round zones on the strip. We compute them on the fly from the
        // ordered list itself — no parallel array needed.
        drawRoundZonesOnStrip(in: &context, ordered: ordered,
                              stripY: stripY, stripMargin: stripMargin,
                              slotSpacing: slotSpacing,
                              revealLimit: revealLimit, sceneIndex: sceneIndex,
                              time: time, settings: settings)

        // ─── Slide each ordered vertex from its lane to its slot ────────
        for (i, vertex) in ordered.enumerated() {
            guard let dagPos = layout.positions[vertex.digestHex] else { continue }
            let targetX = stripMargin + (CGFloat(i) + 0.5) * slotSpacing
            let targetY = stripY

            // Per-vertex animation phase
            let startAt = Double(i) * stagger
            let progress: Double
            if sceneIndex == 2 {
                // In scene 2 the snake is fully formed.
                progress = 1.0
            } else if i >= revealLimit {
                progress = 0.0
            } else {
                progress = max(0, min(1, (time - startAt) / pullDuration))
            }

            // Cubic ease-out for a bit of motion personality without overdoing.
            let eased = 1 - pow(1 - progress, 3)

            let x = dagPos.x + (targetX - dagPos.x) * CGFloat(eased)
            let y = dagPos.y + (targetY - dagPos.y) * CGFloat(eased)
            let pos = CGPoint(x: x, y: y)
            let castColor = dm.castColor(for: vertex.processIdHex)
            let role = dm.castRole(for: vertex.processIdHex)

            // Tracer line during slide — fades as the vertex settles.
            if eased > 0.05 && eased < 0.97 {
                var path = Path()
                path.move(to: dagPos)
                path.addLine(to: pos)
                let traceAlpha = (1 - eased) * 0.5 + 0.1
                context.stroke(path,
                              with: .color(castColor.opacity(traceAlpha)),
                              style: StrokeStyle(lineWidth: 1.6,
                                                 dash: [3, 4]))
            }

            // Vertex itself.
            let radius: CGFloat = 7 + CGFloat(min(vertex.weight, 8)) * 0.6
            let rect = CGRect(x: pos.x - radius, y: pos.y - radius,
                              width: radius * 2, height: radius * 2)
            // A small landing flash for one beat after settling.
            let timeSinceLand = time - (startAt + pullDuration)
            let flashAmt: Double = (timeSinceLand > 0 && timeSinceLand < 0.35)
                ? max(0, 1 - timeSinceLand / 0.35) : 0
            if flashAmt > 0.05 {
                let flashR = radius * (1 + 1.4 * CGFloat(flashAmt))
                let flashRect = CGRect(x: pos.x - flashR, y: pos.y - flashR,
                                        width: flashR * 2, height: flashR * 2)
                context.fill(Circle().path(in: flashRect),
                            with: .color(castColor.opacity(0.25 * flashAmt)))
            }
            context.fill(Circle().path(in: rect),
                        with: .color(castColor.opacity(0.55 + 0.4 * eased)))
            // Yellow ring for round-boundary (`isLast`) vertices —
            // the same convention used in Ch03_Rounds, kept consistent here
            // so the viewer sees that round-marking carries over to ordering.
            if vertex.isLast && eased > 0.6 {
                context.stroke(Circle().path(in: rect.insetBy(dx: -2, dy: -2)),
                              with: .color(.yellow.opacity(0.5 * eased)),
                              lineWidth: 1.5)
            }

            // Position number after landing.
            if eased > 0.85 {
                context.draw(
                    Text("\(i + 1)")
                        .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85)),
                    at: CGPoint(x: pos.x, y: pos.y + radius + 11)
                )
            }

            // Cast-name callout for the FIRST vertex of each named lead.
            // Only label the first appearance to keep the strip readable.
            if eased > 0.85 && role.isNamedCast,
               isFirstAppearance(of: role, in: ordered, atIndex: i) {
                context.draw(
                    Text(role.displayName.uppercased())
                        .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                        .foregroundColor(castColor.opacity(0.9)),
                    at: CGPoint(x: pos.x, y: pos.y - radius - 12)
                )
            }
        }

        // ─── Subtitle ────────────────────────────────────────────────────
        let subtitle: String = switch sceneIndex {
        case 0: "AARON, BEN, CARL — THEIR VERTICES WALK ONTO THE LINE"
        case 1: "EACH ROUND'S VERTICES FLY INTO POSITION"
        default: "EVERY HONEST NODE PRODUCES THIS EXACT LINE — CONVERGENCE"
        }
        context.draw(
            Text(subtitle)
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.55)),
            at: CGPoint(x: size.width / 2, y: stripY + 80)
        )

        // ─── Final-scene convergence badge ───────────────────────────────
        if sceneIndex == 2 {
            drawConvergenceBadge(in: &context, size: size, ordered: ordered, time: time)
        }

        // Top-right: ordered count.
        context.draw(
            Text("\(min(ordered.count, revealLimit))/\(orderedAll.count) ORDERED · \(allVertices.count) TOTAL DAG")
                .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35)),
            at: CGPoint(x: size.width / 2, y: 16)
        )

        _ = timeOffsetForLandingAll  // referenced for clarity in pacing comments
    }

    // MARK: - Pieces

    /// Empty strip slots, drawn as a thin rounded rect with tick marks at
    /// each slot. Visible from t=0 so the viewer knows where vertices are
    /// going before they fly.
    private func drawStripBackdrop(
        in context: inout GraphicsContext, size: CGSize,
        stripY: CGFloat, stripMargin: CGFloat,
        slotSpacing: CGFloat, slotCount: Int, time: Double
    ) {
        let stripHeight: CGFloat = 4
        let stripRect = CGRect(
            x: stripMargin, y: stripY + stripHeight * 4,
            width: size.width - stripMargin * 2, height: stripHeight
        )
        context.fill(RoundedRectangle(cornerRadius: 2).path(in: stripRect),
                    with: .color(.white.opacity(0.12)))
        // Tick at each slot.
        for i in 0..<slotCount {
            let x = stripMargin + (CGFloat(i) + 0.5) * slotSpacing
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: stripRect.minY - 3))
            tick.addLine(to: CGPoint(x: x, y: stripRect.maxY + 3))
            context.stroke(tick, with: .color(.white.opacity(0.10)), lineWidth: 0.6)
        }
        // Direction arrow under the strip.
        let arrowY = stripRect.maxY + 28
        var arrow = Path()
        arrow.move(to: CGPoint(x: stripMargin, y: arrowY))
        arrow.addLine(to: CGPoint(x: size.width - stripMargin, y: arrowY))
        context.stroke(arrow, with: .color(.white.opacity(0.15)), lineWidth: 1)
        context.draw(
            Text("→ TOTAL ORDER (POSITION 1, 2, 3, …)")
                .font(.system(size: settings.scaled(9), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.30 + 0.05 * sin(time))),
            at: CGPoint(x: size.width / 2, y: arrowY + 14)
        )
    }

    /// Per-round shaded zones above the strip. Each round is a translucent
    /// band sized to the contiguous run of vertices with that round number.
    private func drawRoundZonesOnStrip(
        in context: inout GraphicsContext, ordered: [VertexData],
        stripY: CGFloat, stripMargin: CGFloat, slotSpacing: CGFloat,
        revealLimit: Int, sceneIndex: Int, time: Double,
        settings: AppSettings
    ) {
        guard !ordered.isEmpty else { return }
        // Group consecutive same-round runs.
        var runStart = 0
        var i = 1
        let zoneTop = stripY - 16
        let zoneHeight: CGFloat = 28
        while i <= ordered.count {
            let endThisRun = (i == ordered.count) || (ordered[i].round != ordered[runStart].round)
            if endThisRun {
                // Only draw zones whose first vertex has been revealed.
                if runStart < revealLimit {
                    let endIdx = min(i, revealLimit) - 1
                    let runRound = ordered[runStart].round
                    let xStart = stripMargin + CGFloat(runStart) * slotSpacing
                    let xEnd = stripMargin + CGFloat(endIdx + 1) * slotSpacing
                    let rect = CGRect(x: xStart, y: zoneTop,
                                      width: xEnd - xStart, height: zoneHeight)
                    let alpha: Double = sceneIndex == 2 ? 0.18 : 0.12
                    context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                                with: .color(.cyan.opacity(alpha)))
                    context.draw(
                        Text("R\(runRound)")
                            .font(.system(size: settings.scaled(9), weight: .heavy, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.7)),
                        at: CGPoint(x: rect.midX, y: rect.midY)
                    )
                }
                runStart = i
            }
            i += 1
        }
        _ = time
    }

    /// Final-scene "convergence" badge confirming Aaron's line equals Ben's
    /// equals Carl's. The Crisis paper's central guarantee, rendered as a
    /// stamp.
    private func drawConvergenceBadge(
        in context: inout GraphicsContext, size: CGSize,
        ordered: [VertexData], time: Double
    ) {
        // Emerge after a beat; pulse subtly.
        let appear = max(0, min(1, (time - 1.5) / 1.0))
        if appear < 0.05 { return }

        let pulse = 0.5 + 0.5 * sin(time * 1.6)
        let badgeW: CGFloat = 460
        let badgeH: CGFloat = 64
        let badgeRect = CGRect(
            x: size.width / 2 - badgeW / 2,
            y: 70,
            width: badgeW, height: badgeH
        )

        context.fill(RoundedRectangle(cornerRadius: 14).path(in: badgeRect),
                    with: .color(.black.opacity(0.7 * appear)))
        context.stroke(RoundedRectangle(cornerRadius: 14).path(in: badgeRect),
                      with: .color(.green.opacity(0.6 * appear * (0.7 + 0.3 * pulse))),
                      lineWidth: 2)
        context.draw(
            Text("AARON'S LINE  =  BEN'S LINE  =  CARL'S LINE")
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.95 * appear)),
            at: CGPoint(x: badgeRect.midX, y: badgeRect.midY - 8)
        )
        context.draw(
            Text("\(ordered.count) POSITIONS · IDENTICAL · DETERMINISTIC")
                .font(.system(size: settings.scaled(10), weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.65 * appear)),
            at: CGPoint(x: badgeRect.midX, y: badgeRect.midY + 14)
        )
    }

    /// True iff `ordered[index]` is the FIRST occurrence of `role`'s
    /// process id in the ordered list. Used so the cast name labels only
    /// land on the lead's earliest entry, not every entry.
    private func isFirstAppearance(of role: CastRole, in ordered: [VertexData], atIndex index: Int) -> Bool {
        guard let pid = dm.castByPid.first(where: { $0.value.id == role.id })?.key else { return false }
        guard ordered[index].processIdHex == pid else { return false }
        for j in 0..<index where ordered[j].processIdHex == pid {
            return false
        }
        return true
    }
}
