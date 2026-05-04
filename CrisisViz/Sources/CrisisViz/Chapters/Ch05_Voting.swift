import SwiftUI

/// Ch05 (chapter index 4): "Did you see what I saw?"
///
/// The redesigned virtual-voting chapter. Where the previous version
/// asserted "votes are inferred from the graph" with a single static
/// SVP highlight, this version walks the viewer through the collapse
/// step by step at ~3 seconds per step.
///
/// **Pacing & step count.** The user explicitly asked for "10 steps (or
/// more) with slower speed (appr. 3 s)". The scene auto-advance interval
/// is 8 s, so we split the lesson across the chapter's 3 scenes:
///
///   - Scene 0 (≈8 s): steps 1-3   (highlight Aaron, highlight Carl, draw Aaron's cone)
///   - Scene 1 (≈8 s): steps 4-6   (draw Carl's cone, pulse the overlap, surface ancestor a)
///   - Scene 2 (≈8 s): steps 7-10  (surface ancestor b, badge both vertices, migrate, snap consensus)
///
/// Each step adds ONE new visual element on top of what was already
/// drawn; nothing is removed. That is what "no hard cuts" means in
/// practice — by the time we reach step 10 the canvas tells the whole
/// story.
struct Ch05_Voting: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    @Environment(AppSettings.self) private var settings

    /// Mid-late simulation: Aaron and Carl have produced enough vertices
    /// that their depth-2 ancestor cones overlap meaningfully.
    private let dataStep = 24

    // Scene → number of steps (must sum to 10).
    private static let stepsPerScene = [3, 3, 4]

    var body: some View {
        Canvas { context, size in
            render(context: &context, size: size, time: localTime)
        }
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard let sim = dm.sim,
              let snap = dm.honestData(step: dataStep) else { return }

        let nodes = dm.castOrderedNodes()  // Aaron, Ben, Carl, Dave at top — peers below
        let vertices = snap.vertices
        let edges = snap.edges

        let layout = DAGLayout.compute(
            vertices: vertices, edges: edges, nodes: nodes,
            canvasSize: size, margin: 60
        )
        let minRound = vertices.map { $0.round }.min() ?? 0

        // Background — present in every step.
        layout.drawNodeLanes(in: &context, nodes: nodes, canvasSize: size, dm: dm,
                             textScale: settings.textScale)
        layout.drawRoundSeparators(in: &context, canvasSize: size, minRound: minRound,
                                   alpha: 0.25, textScale: settings.textScale)
        layout.drawEdges(in: &context, edges: edges, alpha: 0.18)
        layout.drawVertices(in: &context, vertices: vertices, nodes: nodes, dm: dm,
                            showLabels: false, textScale: settings.textScale)

        // ---------- Find the convergence pair ----------
        // v = Aaron's heaviest late-round vertex
        // w = Carl's  heaviest late-round vertex
        let aaronPid = pid(for: Cast.aaron)
        let carlPid  = pid(for: Cast.carl)

        guard
            let v = pickPairVertex(in: vertices, processIdHex: aaronPid),
            let w = pickPairVertex(in: vertices, processIdHex: carlPid),
            v.digestHex != w.digestHex
        else {
            // Fallback: draw a hint and return so the chapter doesn't go blank.
            drawCenteredHint(context: &context, size: size,
                             text: "Need richer data — try advancing the simulation.")
            return
        }

        // Build parent map (e.from = child, e.to = parent).
        var parentMap: [String: [String]] = [:]
        for e in edges { parentMap[e.from, default: []].append(e.to) }

        let coneV = ancestorCone(of: v.digestHex, parentMap: parentMap, depth: 2)
        let coneW = ancestorCone(of: w.digestHex, parentMap: parentMap, depth: 2)
        let shared = coneV.intersection(coneW).subtracting([v.digestHex, w.digestHex])
        let sharedSorted = shared.sorted { (a, b) in
            // Stable surface order: heaviest first, tie-break by hex
            let va = vertices.first { $0.digestHex == a }
            let vb = vertices.first { $0.digestHex == b }
            let wa = va?.weight ?? 0
            let wb = vb?.weight ?? 0
            if wa != wb { return wa > wb }
            return a < b
        }
        let ancestorA = sharedSorted.first
        let ancestorB = sharedSorted.dropFirst().first

        // ---------- Determine current step ----------
        let stepsHere = Self.stepsPerScene[min(sceneIndex, Self.stepsPerScene.count - 1)]
        let stepDuration = engine.sceneDuration / Double(stepsHere)
        let priorSteps = Self.stepsPerScene.prefix(sceneIndex).reduce(0, +)
        let localStep = min(stepsHere - 1, max(0, Int(time / stepDuration)))
        let currentStep = priorSteps + localStep
        let stepLocalTime = time - Double(localStep) * stepDuration

        // ---------- Render cumulative steps ----------
        // Each branch adds a new visual layer; falls through to add prior layers.
        // We use a switch with explicit cases so the reader can see exactly
        // what each step contributes.

        // STEP 0: highlight Aaron's vertex v
        if currentStep >= 0 {
            highlightVertex(context: &context, layout: layout, vertex: v,
                            color: Cast.coral, label: "Aaron — v",
                            fade: appearFade(stepLocalTime, isStep: currentStep == 0))
        }

        // STEP 1: highlight Carl's vertex w
        if currentStep >= 1 {
            highlightVertex(context: &context, layout: layout, vertex: w,
                            color: Cast.amber, label: "Carl — w",
                            fade: appearFade(stepLocalTime, isStep: currentStep == 1))
        }

        // STEP 2: draw Aaron's ancestor cone
        if currentStep >= 2 {
            drawCone(context: &context, layout: layout, cone: coneV,
                     vertices: vertices, color: Cast.coral,
                     alpha: 0.25 * appearFade(stepLocalTime, isStep: currentStep == 2))
        }

        // STEP 3: draw Carl's ancestor cone (overlap visually emerges)
        if currentStep >= 3 {
            drawCone(context: &context, layout: layout, cone: coneW,
                     vertices: vertices, color: Cast.amber,
                     alpha: 0.25 * appearFade(stepLocalTime, isStep: currentStep == 3))
        }

        // STEP 4: pulse the overlap region (shared ancestors) in white
        if currentStep >= 4 {
            let pulse = 0.45 + 0.35 * sin(time * 2.4)
            drawOverlap(context: &context, layout: layout,
                        shared: shared, vertices: vertices,
                        intensity: pulse * appearFade(stepLocalTime, isStep: currentStep == 4))
        }

        // STEP 5: surface shared ancestor `a`
        if currentStep >= 5, let a = ancestorA {
            tagAncestor(context: &context, layout: layout,
                        digest: a, label: "shared ancestor a",
                        vertices: vertices,
                        fade: appearFade(stepLocalTime, isStep: currentStep == 5))
        }

        // STEP 6: surface shared ancestor `b`
        if currentStep >= 6, let b = ancestorB {
            tagAncestor(context: &context, layout: layout,
                        digest: b, label: "shared ancestor b",
                        vertices: vertices,
                        fade: appearFade(stepLocalTime, isStep: currentStep == 6))
        }

        // STEP 7: badge both vertices with checkmarks (≥2 shared → agreement)
        if currentStep >= 7 {
            let fade = appearFade(stepLocalTime, isStep: currentStep == 7)
            drawAgreementBadge(context: &context, layout: layout, vertex: v, fade: fade)
            drawAgreementBadge(context: &context, layout: layout, vertex: w, fade: fade)
        }

        // STEP 8: migrate v and w toward each other along the round axis
        let migrationProgress: Double = {
            guard currentStep >= 8 else { return 0 }
            if currentStep > 8 { return 1.0 }
            return min(1.0, stepLocalTime / stepDuration)
        }()
        if migrationProgress > 0 {
            drawMigration(context: &context, layout: layout, v: v, w: w,
                          progress: migrationProgress, color: Cast.coral)
        }

        // STEP 9: snap consensus rectangle around the pair, with round number
        if currentStep >= 9 {
            drawConsensusFrame(context: &context, layout: layout, v: v, w: w,
                               migration: 1.0, round: max(v.round, w.round),
                               fade: appearFade(stepLocalTime, isStep: currentStep == 9))
        }

        // ---------- Step counter overlay ----------
        let totalSteps = Self.stepsPerScene.reduce(0, +)
        let counterAlpha: Double = 0.55
        let counterText = "STEP \(currentStep + 1) / \(totalSteps)"
        context.draw(
            Text(counterText)
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(counterAlpha)),
            at: CGPoint(x: size.width - 70, y: 18)
        )

        // Step legend along the bottom — one line per step, current step in white,
        // others dimmed. This is what makes the lesson "explicit".
        drawStepLegend(context: &context, size: size, currentStep: currentStep)
    }

    // MARK: - Helpers

    /// Returns the heaviest vertex authored by the given pid in the latest round
    /// where that pid actually has a vertex. We bias toward later rounds so the
    /// ancestor cones have something interesting to walk through.
    private func pickPairVertex(in vertices: [VertexData], processIdHex: String) -> VertexData? {
        let mine = vertices.filter { $0.processIdHex == processIdHex }
        guard !mine.isEmpty else { return nil }
        let maxRound = mine.map(\.round).max() ?? 0
        // Drop a round if maxRound is the absolute frontier (richer cones earlier).
        let target = max(0, maxRound - 1)
        let inRound = mine.filter { $0.round == target }
        return (inRound.isEmpty ? mine : inRound).max { $0.weight < $1.weight }
    }

    private func pid(for role: CastRole) -> String {
        dm.castByPid.first { $0.value.id == role.id }?.key ?? ""
    }

    /// BFS backward through parent edges to fixed depth.
    private func ancestorCone(of root: String, parentMap: [String: [String]], depth: Int) -> Set<String> {
        var seen: Set<String> = [root]
        var frontier: [String] = [root]
        for _ in 0..<depth {
            var next: [String] = []
            for v in frontier {
                for p in parentMap[v] ?? [] where !seen.contains(p) {
                    seen.insert(p)
                    next.append(p)
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }
        return seen
    }

    /// Fade-in over the first 0.6 s of a step. Steps after the active one
    /// stay fully visible (return 1.0).
    private func appearFade(_ t: Double, isStep: Bool) -> Double {
        guard isStep else { return 1.0 }
        return min(1.0, t / 0.6)
    }

    private func highlightVertex(
        context: inout GraphicsContext, layout: DAGLayout,
        vertex: VertexData, color: Color, label: String, fade: Double
    ) {
        guard let pos = layout.positions[vertex.digestHex] else { return }
        // Halo
        let r: CGFloat = 22
        let haloRect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        context.stroke(
            Circle().path(in: haloRect),
            with: .color(color.opacity(0.7 * fade)),
            lineWidth: 3
        )
        // Soft glow
        let g: CGFloat = 36
        let glowRect = CGRect(x: pos.x - g, y: pos.y - g, width: g * 2, height: g * 2)
        context.fill(
            Circle().path(in: glowRect),
            with: .color(color.opacity(0.10 * fade))
        )
        // Label
        context.draw(
            Text(label)
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(color.opacity(0.95 * fade)),
            at: CGPoint(x: pos.x, y: pos.y - r - 12)
        )
    }

    private func drawCone(
        context: inout GraphicsContext, layout: DAGLayout,
        cone: Set<String>, vertices: [VertexData],
        color: Color, alpha: Double
    ) {
        for digest in cone {
            guard let pos = layout.positions[digest] else { continue }
            let r: CGFloat = 14
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(alpha)))
        }
    }

    private func drawOverlap(
        context: inout GraphicsContext, layout: DAGLayout,
        shared: Set<String>, vertices: [VertexData],
        intensity: Double
    ) {
        for digest in shared {
            guard let pos = layout.positions[digest] else { continue }
            let r: CGFloat = 18
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            // Pulsing white outline + soft white fill: emphasizes "BOTH saw this".
            context.stroke(
                Circle().path(in: rect),
                with: .color(.white.opacity(0.85 * intensity)),
                lineWidth: 2.2
            )
            context.fill(
                Circle().path(in: rect.insetBy(dx: 4, dy: 4)),
                with: .color(.white.opacity(0.18 * intensity))
            )
        }
    }

    private func tagAncestor(
        context: inout GraphicsContext, layout: DAGLayout,
        digest: String, label: String,
        vertices: [VertexData], fade: Double
    ) {
        guard let pos = layout.positions[digest] else { return }
        // Draw a chevron-style tag above the vertex pointing down.
        let tagRect = CGRect(x: pos.x - 80, y: pos.y - 42, width: 160, height: 18)
        context.fill(
            RoundedRectangle(cornerRadius: 4).path(in: tagRect),
            with: .color(.white.opacity(0.16 * fade))
        )
        context.stroke(
            RoundedRectangle(cornerRadius: 4).path(in: tagRect),
            with: .color(.white.opacity(0.6 * fade)),
            lineWidth: 1
        )
        context.draw(
            Text(label)
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.95 * fade)),
            at: CGPoint(x: pos.x, y: pos.y - 33)
        )
        // Connector line tag → vertex
        var line = Path()
        line.move(to: CGPoint(x: pos.x, y: pos.y - 24))
        line.addLine(to: CGPoint(x: pos.x, y: pos.y - 14))
        context.stroke(line, with: .color(.white.opacity(0.6 * fade)), lineWidth: 1)
    }

    private func drawAgreementBadge(
        context: inout GraphicsContext, layout: DAGLayout,
        vertex: VertexData, fade: Double
    ) {
        guard let pos = layout.positions[vertex.digestHex] else { return }
        let badgeCenter = CGPoint(x: pos.x + 18, y: pos.y - 18)
        let r: CGFloat = 9
        let rect = CGRect(x: badgeCenter.x - r, y: badgeCenter.y - r, width: r * 2, height: r * 2)
        context.fill(Circle().path(in: rect), with: .color(.green.opacity(0.85 * fade)))
        context.draw(
            Text("✓")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.95 * fade)),
            at: badgeCenter
        )
    }

    /// Render v and w sliding toward each other. We compute their original
    /// positions from `layout.positions` and interpolate.
    private func drawMigration(
        context: inout GraphicsContext, layout: DAGLayout,
        v: VertexData, w: VertexData, progress: Double, color: Color
    ) {
        guard let pV = layout.positions[v.digestHex],
              let pW = layout.positions[w.digestHex] else { return }
        let target = CGPoint(x: (pV.x + pW.x) / 2, y: (pV.y + pW.y) / 2)
        let curV = CGPoint(
            x: pV.x + (target.x - pV.x) * progress * 0.65,
            y: pV.y + (target.y - pV.y) * progress * 0.65
        )
        let curW = CGPoint(
            x: pW.x + (target.x - pW.x) * progress * 0.65,
            y: pW.y + (target.y - pW.y) * progress * 0.65
        )

        // Trail
        var trailV = Path()
        trailV.move(to: pV); trailV.addLine(to: curV)
        context.stroke(trailV, with: .color(Cast.coral.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        var trailW = Path()
        trailW.move(to: pW); trailW.addLine(to: curW)
        context.stroke(trailW, with: .color(Cast.amber.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))

        // Moving copies of the vertices (drawn brighter than the originals
        // so the eye follows the migration).
        let r: CGFloat = 12
        for (pt, c) in [(curV, Cast.coral), (curW, Cast.amber)] {
            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(c))
            context.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        }
    }

    private func drawConsensusFrame(
        context: inout GraphicsContext, layout: DAGLayout,
        v: VertexData, w: VertexData, migration: Double, round: Int, fade: Double
    ) {
        guard let pV = layout.positions[v.digestHex],
              let pW = layout.positions[w.digestHex] else { return }
        let cx = (pV.x + pW.x) / 2
        let cy = (pV.y + pW.y) / 2
        let half: CGFloat = 70
        let rect = CGRect(x: cx - half, y: cy - half * 0.7,
                          width: half * 2, height: half * 1.4)
        context.fill(
            RoundedRectangle(cornerRadius: 12).path(in: rect),
            with: .color(.green.opacity(0.10 * fade))
        )
        context.stroke(
            RoundedRectangle(cornerRadius: 12).path(in: rect),
            with: .color(.green.opacity(0.85 * fade)),
            lineWidth: 2.2
        )
        context.draw(
            Text("CONSENSUS · ROUND \(round)")
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(.green.opacity(0.95 * fade)),
            at: CGPoint(x: cx, y: rect.minY - 12)
        )
    }

    private func drawStepLegend(
        context: inout GraphicsContext, size: CGSize, currentStep: Int
    ) {
        let labels = [
            "1. highlight Aaron's vertex v",
            "2. highlight Carl's vertex w",
            "3. draw v's ancestor cone (coral)",
            "4. draw w's ancestor cone (amber)",
            "5. pulse the overlap (shared ancestors)",
            "6. surface shared ancestor a",
            "7. surface shared ancestor b",
            "8. ≥2 shared → agreement badges",
            "9. migrate v and w together",
            "10. snap consensus around them",
        ]
        let lineHeight: CGFloat = 14
        let totalHeight = CGFloat(labels.count) * lineHeight
        let startY = size.height - totalHeight - 18
        for (i, label) in labels.enumerated() {
            let isCurrent = (i == currentStep)
            let isPast = (i < currentStep)
            let alpha: Double = isCurrent ? 1.0 : (isPast ? 0.6 : 0.3)
            let weight: Font.Weight = isCurrent ? .heavy : .medium
            context.draw(
                Text(label)
                    .font(.system(size: settings.scaled(10), weight: weight, design: .monospaced))
                    .foregroundColor(.white.opacity(alpha)),
                at: CGPoint(x: 16 + 130, y: startY + CGFloat(i) * lineHeight)
            )
        }
    }

    private func drawCenteredHint(
        context: inout GraphicsContext, size: CGSize, text: String
    ) {
        context.draw(
            Text(text)
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.7)),
            at: CGPoint(x: size.width / 2, y: size.height / 2)
        )
    }
}
