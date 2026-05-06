import SwiftUI

/// Ch03 (file Ch03_Partition.swift, user-facing Ch2): "Dave can't hear Aaron. The graph splits."
///
/// Redesign: stays on the persistent lane base from Ch01/Ch02. The partition
/// is shown as a horizontal red dashed cut between Carl's lane (2) and Dave's
/// lane (3). Dave is the only node who goes silent — Aaron/Ben/Carl keep
/// building. This matches the narration in `SceneNarrations.swift` and the
/// cast assignment in `Cast.swift`.
struct Ch03_Partition: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    private let majorityStep = 3
    private let fullStep = 5  // post-reconnection

    var body: some View {
        Canvas { context, size in
            render(context: &context, size: size, time: localTime)
        }
    }

    /// PID of the cast member playing Dave, if assigned. Used to filter the
    /// partition victim's vertices out of the "majority" view.
    private var davePid: String? {
        dm.castByPid.first(where: { $0.value.id == Cast.dave.id })?.key
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard dm.sim != nil,
              let snap = dm.honestData(step: majorityStep) else {
            context.draw(Text("Loading...").foregroundColor(.white),
                        at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        switch sceneIndex {
        case 0: renderDaveGoesSilent(context: &context, size: size, time: time, snap: snap)
        case 1: renderWorldBuildsOn(context: &context, size: size, time: time, snap: snap)
        case 2: renderTwoStories(context: &context, size: size, time: time, snap: snap)
        case 3: renderReconnection(context: &context, size: size, time: time)
        default: break
        }
    }

    // MARK: - Shared lane-base layout

    /// Builds a layout over the full vertex set so positions never jump as
    /// scenes progress. The partition line goes between Carl's lane (2) and
    /// Dave's lane (3) — three lanes above, one below, peers below that.
    private func laneLayout(snap: NodeSnapshot, size: CGSize) -> DAGLayout {
        DAGLayout.compute(
            vertices: snap.vertices,
            edges: snap.edges,
            nodes: dm.castOrderedNodes(),
            canvasSize: size,
            margin: 60
        )
    }

    /// Y coordinate of the dashed partition line ABOVE Dave's lane (between
    /// Carl on lane 2 and Dave on lane 3).
    private func partitionLineY(size: CGSize, margin: CGFloat = 60) -> CGFloat {
        let nodes = dm.castOrderedNodes()
        let usableHeight = size.height - margin * 2
        let laneHeight = usableHeight / CGFloat(max(nodes.count, 1))
        return margin + 3.0 * laneHeight
    }

    /// Y coordinate of the dashed partition line BELOW Dave's lane (between
    /// Dave on lane 3 and the first peer on lane 4). Drawn alongside the top
    /// line to visually fence Dave OFF from both Carl above AND the peers
    /// below — otherwise the muted peers look partitioned with him, which
    /// contradicts the narration ("only Dave is isolated").
    private func partitionLineYBottom(size: CGSize, margin: CGFloat = 60) -> CGFloat {
        let nodes = dm.castOrderedNodes()
        let usableHeight = size.height - margin * 2
        let laneHeight = usableHeight / CGFloat(max(nodes.count, 1))
        return margin + 4.0 * laneHeight
    }

    /// Faint red wash painted over Dave's lane band so the eye reads "this
    /// stripe is the partition" instead of "everything below the line".
    /// Drawn at the same `cut` strength as the dashed lines.
    private func drawDaveIsolationBand(
        in context: inout GraphicsContext, size: CGSize, cut: Double
    ) {
        let yTop = partitionLineY(size: size)
        let yBot = partitionLineYBottom(size: size)
        let band = CGRect(x: 50, y: yTop,
                          width: size.width - 80, height: yBot - yTop)
        context.fill(RoundedRectangle(cornerRadius: 4).path(in: band),
                    with: .color(.red.opacity(0.10 * cut)))
    }

    /// Draw both partition cuts (top + bottom of Dave's lane) plus the
    /// breakage ✕ marks and the "DAVE — PARTITIONED" label.
    private func drawPartitionCuts(
        in context: inout GraphicsContext, size: CGSize, cut: Double
    ) {
        guard cut > 0.05 else { return }
        let yTop = partitionLineY(size: size)
        let yBot = partitionLineYBottom(size: size)
        let dash: [CGFloat] = [10, 8]
        for y in [yTop, yBot] {
            var line = Path()
            line.move(to: CGPoint(x: 50, y: y))
            line.addLine(to: CGPoint(x: size.width - 30, y: y))
            context.stroke(line, with: .color(.red.opacity(0.55 * cut)),
                          style: StrokeStyle(lineWidth: 2, dash: dash))
            for fx in [0.20, 0.45, 0.70] {
                let x = size.width * fx
                context.draw(
                    Text("✕")
                        .font(.system(size: settings.scaled(13), weight: .heavy))
                        .foregroundColor(.red.opacity(0.7 * cut)),
                    at: CGPoint(x: x, y: y)
                )
            }
        }
        context.draw(
            Text("DAVE — PARTITIONED")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.red.opacity(0.65 * cut))
                .kerning(1.5),
            at: CGPoint(x: size.width / 2, y: (yTop + yBot) / 2)
        )
    }

    // MARK: - Scene 0: Dave goes silent

    private func renderDaveGoesSilent(context: inout GraphicsContext, size: CGSize, time: Double, snap: NodeSnapshot) {
        let layout = laneLayout(snap: snap, size: size)
        let minRound = snap.vertices.map { $0.round }.min() ?? 0
        let lanes = dm.castOrderedNodes()

        // Lane chrome — same as previous chapters
        layout.drawNodeLanes(in: &context, nodes: lanes, canvasSize: size, dm: dm, textScale: settings.textScale)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: minRound, alpha: 0.25, textScale: settings.textScale)

        // Partition strength fades in over ~4s
        let cut = min(1.0, time * 0.25)

        // Edges: any edge that crosses Dave's lane fades; same-side edges stay bright.
        let dave = davePid
        let pidByDigest = Dictionary(uniqueKeysWithValues: snap.vertices.map { ($0.digestHex, $0.processIdHex) })
        for edge in snap.edges {
            guard let from = layout.positions[edge.from],
                  let to = layout.positions[edge.to] else { continue }
            let touchesDave = pidByDigest[edge.from] == dave || pidByDigest[edge.to] == dave
            let alpha = touchesDave ? max(0.05, 0.3 * (1 - cut)) : 0.3
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 1.0)
        }

        // Vertices — Dave's dim as the cut tightens, others stay bright.
        for vertex in snap.vertices {
            guard let pos = layout.positions[vertex.digestHex] else { continue }
            let isDave = vertex.processIdHex == dave
            let appear = isDave ? max(0.2, 1.0 - cut * 0.7) : 1.0
            let baseColor = dm.castColor(for: vertex.processIdHex)
            let r: CGFloat = 8 + CGFloat(min(vertex.weight, 10))
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(baseColor.opacity(0.85 * appear)))
            if vertex.isLast {
                context.stroke(Circle().path(in: rect.insetBy(dx: -2, dy: -2)),
                              with: .color(.white.opacity(0.5 * appear)), lineWidth: 1.5)
            }
        }

        // Faint band over Dave's lane + dashed cuts above and below it.
        drawDaveIsolationBand(in: &context, size: size, cut: cut)
        drawPartitionCuts(in: &context, size: size, cut: cut)
    }

    // MARK: - Scene 1: world keeps building without him

    private func renderWorldBuildsOn(context: inout GraphicsContext, size: CGSize, time: Double, snap: NodeSnapshot) {
        let layout = laneLayout(snap: snap, size: size)
        let minRound = snap.vertices.map { $0.round }.min() ?? 0
        let lanes = dm.castOrderedNodes()

        layout.drawNodeLanes(in: &context, nodes: lanes, canvasSize: size, dm: dm, textScale: settings.textScale)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: minRound, alpha: 0.25, textScale: settings.textScale)

        // Aaron/Ben/Carl edges stay bright; Dave's edges (none reach him) faded.
        let dave = davePid
        let pidByDigest = Dictionary(uniqueKeysWithValues: snap.vertices.map { ($0.digestHex, $0.processIdHex) })
        for edge in snap.edges {
            guard let from = layout.positions[edge.from],
                  let to = layout.positions[edge.to] else { continue }
            let inMajority = pidByDigest[edge.from] != dave && pidByDigest[edge.to] != dave
            let alpha = inMajority ? 0.32 : 0.06
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 1.0)
        }

        // Vertices: majority bright; Dave's dim and visibly sparser.
        for vertex in snap.vertices {
            guard let pos = layout.positions[vertex.digestHex] else { continue }
            let isDave = vertex.processIdHex == dave
            let baseColor = dm.castColor(for: vertex.processIdHex)
            let alpha = isDave ? 0.3 : 0.85
            let r: CGFloat = 8 + CGFloat(min(vertex.weight, 10))
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(baseColor.opacity(alpha)))
            if vertex.isLast && !isDave {
                context.stroke(Circle().path(in: rect.insetBy(dx: -2, dy: -2)),
                              with: .color(.white.opacity(0.5)), lineWidth: 1.5)
            }
        }

        // Persistent isolation band + cuts above and below Dave.
        drawDaveIsolationBand(in: &context, size: size, cut: 1.0)
        drawPartitionCuts(in: &context, size: size, cut: 1.0)

        // Counts: rich up top, sparse below.
        let majorityCount = snap.vertices.filter { $0.processIdHex != dave }.count
        let daveCount = snap.vertices.filter { $0.processIdHex == dave }.count
        let pulse = 0.5 + 0.2 * sin(time * 1.2)
        let yTop = partitionLineY(size: size)
        let yBot = partitionLineYBottom(size: size)
        context.draw(
            Text("AARON · BEN · CARL — \(majorityCount) VERTICES, GROWING")
                .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.55)),
            at: CGPoint(x: size.width / 2, y: yTop - 14)
        )
        context.draw(
            Text("DAVE — \(daveCount) VERTICES, NONE REFERENCED  ·  PEERS BELOW UNAFFECTED")
                .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.45 * pulse + 0.2)),
            at: CGPoint(x: size.width / 2, y: yBot + 14)
        )
    }

    // MARK: - Scene 2: two graphs, two stories

    /// Stay on the lane base; show that the two sides compute different round
    /// boundaries by overlaying weight pills above and below the cut.
    private func renderTwoStories(context: inout GraphicsContext, size: CGSize, time: Double, snap: NodeSnapshot) {
        // Render scene 1's lane scene as the backdrop, then add divergence pills.
        renderWorldBuildsOn(context: &context, size: size, time: time, snap: snap)

        let dave = davePid
        let majorityVerts = snap.vertices.filter { $0.processIdHex != dave }
        let daveVerts = snap.vertices.filter { $0.processIdHex == dave }

        let majWeight = majorityVerts.reduce(0) { $0 + $1.weight }
        let daveWeight = daveVerts.reduce(0) { $0 + $1.weight }

        let pulse = 0.5 + 0.5 * sin(time * 2)
        let pillW: CGFloat = 220
        let pillH: CGFloat = 28

        let majPill = CGRect(x: size.width - pillW - 24, y: 60, width: pillW, height: pillH)
        context.fill(RoundedRectangle(cornerRadius: 6).path(in: majPill),
                    with: .color(.black.opacity(0.55)))
        context.stroke(RoundedRectangle(cornerRadius: 6).path(in: majPill),
                      with: .color(Cast.coral.opacity(0.7 * pulse)), lineWidth: 1.2)
        context.draw(
            Text("MAJORITY ROUND-WEIGHT: \(majWeight)")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.85)),
            at: CGPoint(x: majPill.midX, y: majPill.midY)
        )

        let davePillY = size.height - 60 - pillH
        let davePill = CGRect(x: size.width - pillW - 24, y: davePillY, width: pillW, height: pillH)
        context.fill(RoundedRectangle(cornerRadius: 6).path(in: davePill),
                    with: .color(.black.opacity(0.55)))
        context.stroke(RoundedRectangle(cornerRadius: 6).path(in: davePill),
                      with: .color(Cast.violet.opacity(0.7 * pulse)), lineWidth: 1.2)
        context.draw(
            Text("DAVE'S ROUND-WEIGHT: \(daveWeight)")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.85)),
            at: CGPoint(x: davePill.midX, y: davePill.midY)
        )

        context.draw(
            Text("DIFFERENT GRAPHS → DIFFERENT ROUND BOUNDARIES")
                .font(.system(size: settings.scaled(10), weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)),
            at: CGPoint(x: size.width / 2, y: size.height - 30)
        )
    }

    // MARK: - Scene 3: Dave reconnects, stories reconcile

    private func renderReconnection(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard let snap = dm.honestData(step: fullStep) else { return }
        let layout = laneLayout(snap: snap, size: size)
        let minRound = snap.vertices.map { $0.round }.min() ?? 0
        let lanes = dm.castOrderedNodes()

        layout.drawNodeLanes(in: &context, nodes: lanes, canvasSize: size, dm: dm, textScale: settings.textScale)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: minRound, alpha: 0.25, textScale: settings.textScale)
        layout.drawEdges(in: &context, edges: snap.edges, alpha: 0.32)
        layout.drawVertices(in: &context, vertices: snap.vertices, nodes: lanes, dm: dm,
                           showLabels: true, animationTime: time, textScale: settings.textScale)

        // Partition line breaks open: dashes thin and fade.
        let healed = min(1.0, time * 0.3)
        let y = partitionLineY(size: size)
        if healed < 0.95 {
            var line = Path()
            line.move(to: CGPoint(x: 50, y: y))
            line.addLine(to: CGPoint(x: size.width - 30, y: y))
            let dash: [CGFloat] = [max(2, 10 - 8 * healed), 6 + 18 * healed]
            context.stroke(line, with: .color(.red.opacity(0.45 * (1 - healed))),
                          style: StrokeStyle(lineWidth: 2 * (1 - healed * 0.7), dash: dash))
        }

        // Gossip particles: green dots flowing across the cut.
        let particleCount = Int(40 * healed)
        for p in 0..<particleCount {
            let seed = Double(p * 7919)
            let lifecycle = ((time * 0.5 + seed * 0.01).truncatingRemainder(dividingBy: 1.0))
            let direction: CGFloat = (Int(seed) % 2 == 0) ? -1 : 1
            let px = size.width * 0.15 + (size.width * 0.7) * lifecycle
            let py = y + direction * (10 + CGFloat((seed * 11).truncatingRemainder(dividingBy: 60)))
            let alpha = (1 - lifecycle) * 0.7
            let particleRect = CGRect(x: px - 3, y: py - 3, width: 6, height: 6)
            context.fill(Circle().path(in: particleRect),
                        with: .color(.green.opacity(alpha)))
        }

        context.draw(
            Text("RECONNECTED — \(snap.vertices.count) VERTICES MERGED")
                .font(.system(size: settings.scaled(11), weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.5 + 0.2 * healed)),
            at: CGPoint(x: size.width / 2, y: size.height - 30)
        )
    }
}
