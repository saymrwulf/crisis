import SwiftUI

/// Ch01 — "Aaron speaks. Ben listens. The graph begins."
///
/// Every scene in this chapter renders from a single continuous serial
/// timeline (`Ch01Timeline`). The 7 scenes are just navigation labels:
/// each scene corresponds to a window of the timeline. The renderer is a
/// pure function of timeline position `t`.
///
/// Pedagogical principles (see also `Ch01Timeline.swift`):
///   - Strictly serial: never two events on screen simultaneously
///   - Extreme slow motion: every micro-event (think / select payload /
///     select parents / PoW / seal / decide / fly / arrive / open /
///     read body / read parents / resolve each parent / verify / accept)
///     is its own beat
///   - Cast members appear only when the story brings them on stage
///   - Narration text in `GlassNarration` is bound to the *currently
///     active beat*, not the scene
struct Ch02_Graph: View {
    let sceneIndex: Int
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    let inspection: InspectionState
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let t = Ch01Scenes.timelineT(sceneIndex: sceneIndex,
                                          localTime: localTime)
            render(in: &context, size: size, t: t)
        }
    }

    // MARK: - Top-level render

    private func render(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let world = Ch01Timeline.state(at: t)

        // 1. Lanes only for cast members already on stage. The grid is
        //    drawn very faintly so it doesn't compete with the focused
        //    beat — the chapter is about ONE thing happening at a time.
        drawStagedLanes(in: &context, size: size, world: world)

        // 2. Cast circles on their lane Y values. If a cast is the
        //    spotlight of the active beat, pulse them.
        for cast in Ch01Cast.allCases where world.introduced.contains(cast) {
            let pos = castPosition(cast: cast, size: size)
            drawCastVertex(in: &context, at: pos, cast: cast, world: world, t: t)
        }

        // 3. Vertices already accepted into each cast's lifeline.
        drawAcceptedVertices(in: &context, size: size, world: world)

        // 4. Parent edges drawn between accepted vertices in each cast's view.
        drawAcceptedEdges(in: &context, size: size, world: world)

        // 5. Thought bubble above the focal cast, if one is thinking.
        if let thought = world.thought {
            drawThoughtBubble(in: &context, size: size, thought: thought)
        }

        // 6. Composing slot at top-center, with colored connector to author.
        if let composing = world.composing {
            drawComposingSlot(in: &context, size: size, composing: composing)
        }

        // 7. Decide arrow (sender → recipient) when active.
        if let decide = world.decideArrow {
            drawDecideArrow(in: &context, size: size, decide: decide)
        }

        // 8. In-flight envelope.
        if let flight = world.inFlight {
            drawInFlight(in: &context, size: size, flight: flight)
        }

        // 9. Open envelope card next to recipient when they're reading.
        if let env = world.openEnvelope {
            drawOpenEnvelope(in: &context, size: size, env: env)
        }

        // 10. Footer: timeline position + active beat label, faint.
        drawFooter(in: &context, size: size, t: t, world: world)
    }

    // MARK: - Lane geometry

    /// Lane center Y for cast index 0..3 (Aaron/Ben/Carl/Dave) using the
    /// same math `DAGLayoutEngine` uses for the rest of the curriculum.
    private func castLaneY(_ laneIdx: Int, size: CGSize) -> CGFloat {
        let margin: CGFloat = 60
        let nodeCount: CGFloat = 7  // Aaron/Ben/Carl/Dave + 3 peers
        let laneHeight = (size.height - 2 * margin) / nodeCount
        return margin + (CGFloat(laneIdx) + 0.5) * laneHeight
    }

    /// Cast position (X staircased so flight diagonals are clean).
    private func castPosition(cast: Ch01Cast, size: CGSize) -> CGPoint {
        let laneIdx: Int
        let xFrac: CGFloat
        switch cast {
        case .aaron: (laneIdx, xFrac) = (0, 0.20)
        case .ben:   (laneIdx, xFrac) = (1, 0.50)
        case .carl:  (laneIdx, xFrac) = (2, 0.80)
        case .dave:  (laneIdx, xFrac) = (3, 0.50)
        }
        return CGPoint(x: size.width * xFrac, y: castLaneY(laneIdx, size: size))
    }

    private func castColor(_ cast: Ch01Cast) -> Color {
        switch cast {
        case .aaron: return Cast.coral
        case .ben:   return Cast.teal
        case .carl:  return Cast.amber
        case .dave:  return Cast.violet
        }
    }

    // MARK: - Lanes

    private func drawStagedLanes(
        in context: inout GraphicsContext, size: CGSize,
        world: Ch01WorldState
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2), (.dave, 3)]
        for (cast, idx) in casts where world.introduced.contains(cast) {
            let y = castLaneY(idx, size: size)
            // Thin axis line across the canvas for the cast's lifeline.
            var path = Path()
            path.move(to: CGPoint(x: 36, y: y))
            path.addLine(to: CGPoint(x: size.width - 24, y: y))
            context.stroke(path, with: .color(castColor(cast).opacity(0.18)),
                          style: StrokeStyle(lineWidth: 0.8, dash: [4, 6]))
            // Lane name at the left.
            context.draw(
                Text(cast.role.displayName.capitalized)
                    .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                    .foregroundColor(castColor(cast).opacity(0.75)),
                at: CGPoint(x: 24, y: y),
                anchor: .leading
            )
        }
    }

    // MARK: - Cast vertex (the cast member's "self")

    private func drawCastVertex(
        in context: inout GraphicsContext, at pos: CGPoint,
        cast: Ch01Cast, world: Ch01WorldState, t: Double
    ) {
        let isActive: Bool = {
            switch world.activeBeat?.kind {
            case .introduce(let c), .think(let c, _):
                return c == cast
            case .selectPayload(let mid), .selectParents(let mid),
                 .computePoW(let mid), .seal(let mid):
                return Ch01Timeline.messages[mid]?.author == cast
            case .decideSend(let from, _, _):
                return from == cast
            case .arrive(let at, _), .open(let at, _),
                 .readBody(let at, _), .readParents(let at, _),
                 .resolveParent(let at, _, _),
                 .verifyHash(let at, _), .acceptIntoView(let at, _):
                return at == cast
            default:
                return false
            }
        }()
        let pulse: CGFloat = isActive ? 1.0 + 0.06 * CGFloat(sin(t * 4)) : 1.0
        let r: CGFloat = 28 * pulse
        let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        let color = castColor(cast)

        // Halo
        let haloR = r * 1.6
        context.fill(
            Circle().path(in: CGRect(x: pos.x - haloR, y: pos.y - haloR,
                                      width: haloR * 2, height: haloR * 2)),
            with: .color(color.opacity(isActive ? 0.22 : 0.10))
        )
        context.fill(Circle().path(in: rect), with: .color(color.opacity(0.95)))
        context.stroke(Circle().path(in: rect),
                      with: .color(.white.opacity(0.5)), lineWidth: 1.5)
        context.draw(
            Text(String(cast.role.displayName.prefix(1)))
                .font(.system(size: settings.scaled(20), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
        // Name caption below
        context.draw(
            Text(cast.role.displayName.uppercased())
                .font(.system(size: settings.scaled(11), weight: .heavy, design: .monospaced))
                .foregroundColor(color.opacity(0.95)),
            at: CGPoint(x: pos.x, y: pos.y + r + 12)
        )
    }

    // MARK: - Accepted vertices on cast lanes

    /// Each cast's accepted messages get small vertices on their lifeline,
    /// to the right of their cast circle, in chronological order. These
    /// represent "things this player has, in their own local DAG."
    private func drawAcceptedVertices(
        in context: inout GraphicsContext, size: CGSize, world: Ch01WorldState
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2)]
        let messageOrder: [String] = ["α", "β", "γ"]

        for (cast, laneIdx) in casts where world.introduced.contains(cast) {
            let view = world.views[cast] ?? []
            let lane = castLaneY(laneIdx, size: size)
            let castX = castPosition(cast: cast, size: size).x
            // Lay vertices out to the RIGHT of the cast circle. Spacing
            // adapts to the available canvas width.
            let firstX = castX + 80
            let gap: CGFloat = 64
            for (i, mid) in messageOrder.enumerated() where view.contains(mid) {
                let x = firstX + CGFloat(i) * gap
                if x > size.width - 60 { break }
                drawAcceptedVertex(in: &context, at: CGPoint(x: x, y: lane),
                                    messageId: mid)
            }
        }
    }

    private func drawAcceptedVertex(
        in context: inout GraphicsContext, at pos: CGPoint, messageId: String
    ) {
        guard let msg = Ch01Timeline.messages[messageId] else { return }
        let r: CGFloat = 16
        let color = castColor(msg.author)
        let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        context.fill(Circle().path(in: rect),
                    with: .color(color.opacity(0.85)))
        context.stroke(Circle().path(in: rect),
                      with: .color(.white.opacity(0.55)), lineWidth: 1.2)
        context.draw(
            Text(messageId)
                .font(.system(size: settings.scaled(13), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
        // Hash digest below
        context.draw(
            Text(msg.hashShort)
                .font(.system(size: settings.scaled(8), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.55)),
            at: CGPoint(x: pos.x, y: pos.y + r + 8)
        )
    }

    /// Parent edges between accepted vertices in each cast's lifeline:
    /// β → α, γ → α. Each edge sits in the receiver's lane.
    private func drawAcceptedEdges(
        in context: inout GraphicsContext, size: CGSize, world: Ch01WorldState
    ) {
        let casts: [(Ch01Cast, Int)] = [(.aaron, 0), (.ben, 1), (.carl, 2)]
        let messageOrder: [String] = ["α", "β", "γ"]

        for (cast, laneIdx) in casts where world.introduced.contains(cast) {
            let view = world.views[cast] ?? []
            let lane = castLaneY(laneIdx, size: size)
            let castX = castPosition(cast: cast, size: size).x
            let firstX = castX + 80
            let gap: CGFloat = 64
            // Indexed positions for each message slot.
            var positions: [String: CGPoint] = [:]
            for (i, mid) in messageOrder.enumerated() where view.contains(mid) {
                positions[mid] = CGPoint(x: firstX + CGFloat(i) * gap, y: lane)
            }
            for (mid, childPos) in positions {
                guard let msg = Ch01Timeline.messages[mid] else { continue }
                for parentId in msg.parents {
                    guard let parentPos = positions[parentId] else { continue }
                    var path = Path()
                    let from = CGPoint(x: childPos.x - 16, y: childPos.y)
                    let to = CGPoint(x: parentPos.x + 16, y: parentPos.y)
                    path.move(to: from)
                    path.addLine(to: to)
                    context.stroke(path,
                                  with: .color(castColor(msg.author).opacity(0.70)),
                                  lineWidth: 1.5)
                    // Arrowhead at parent
                    var head = Path()
                    head.move(to: to)
                    head.addLine(to: CGPoint(x: to.x + 6, y: to.y - 4))
                    head.move(to: to)
                    head.addLine(to: CGPoint(x: to.x + 6, y: to.y + 4))
                    context.stroke(head,
                                  with: .color(castColor(msg.author).opacity(0.70)),
                                  lineWidth: 1.5)
                }
            }
        }
    }

    // MARK: - Thought bubble

    private func drawThoughtBubble(
        in context: inout GraphicsContext, size: CGSize,
        thought: Ch01WorldState.ThoughtState
    ) {
        let pos = castPosition(cast: thought.cast, size: size)
        let bubbleW: CGFloat = max(140, CGFloat(thought.label.count) * 7.0 + 24)
        let bubbleH: CGFloat = 36
        let bubbleRect = CGRect(
            x: pos.x - bubbleW / 2,
            y: pos.y - 80 - bubbleH,
            width: bubbleW, height: bubbleH
        )
        let color = castColor(thought.cast)
        context.fill(RoundedRectangle(cornerRadius: 18).path(in: bubbleRect),
                    with: .color(.black.opacity(0.78)))
        context.stroke(RoundedRectangle(cornerRadius: 18).path(in: bubbleRect),
                      with: .color(color.opacity(0.85)), lineWidth: 1.4)
        context.draw(
            Text(thought.label)
                .font(.system(size: settings.scaled(11), weight: .medium, design: .default))
                .foregroundColor(.white.opacity(0.92))
                .italic(),
            at: CGPoint(x: bubbleRect.midX, y: bubbleRect.midY)
        )
        // Two little circles like a comic "thought" tail
        for (offset, scale) in [(50.0, 6.0), (28.0, 4.0)] {
            let cx = pos.x
            let cy = pos.y - offset
            let s = CGFloat(scale)
            context.fill(Circle().path(in: CGRect(x: cx - s, y: cy - s,
                                                   width: s * 2, height: s * 2)),
                        with: .color(.black.opacity(0.78)))
            context.stroke(Circle().path(in: CGRect(x: cx - s, y: cy - s,
                                                     width: s * 2, height: s * 2)),
                          with: .color(color.opacity(0.85)), lineWidth: 1.0)
        }
    }

    // MARK: - Composing slot

    private func drawComposingSlot(
        in context: inout GraphicsContext, size: CGSize,
        composing: Ch01WorldState.ComposingState
    ) {
        guard let msg = Ch01Timeline.messages[composing.messageId] else { return }
        let boxW: CGFloat = 320
        let boxH: CGFloat = 110
        let authorPos = castPosition(cast: composing.author, size: size)
        // Position the slot to the side of the author's lane, on the
        // half of the canvas that has more room. Always vertically
        // centered on the author's lane Y so the box and cast circle
        // read as part of the same gesture.
        let placeRight = authorPos.x < size.width / 2
        let boxX: CGFloat = placeRight
            ? authorPos.x + 56
            : authorPos.x - 56 - boxW
        let boxY: CGFloat = authorPos.y - boxH / 2
        let boxRect = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)

        let color = castColor(composing.author)
        context.fill(RoundedRectangle(cornerRadius: 10).path(in: boxRect),
                    with: .color(.black.opacity(0.85)))
        context.stroke(RoundedRectangle(cornerRadius: 10).path(in: boxRect),
                      with: .color(color.opacity(0.95)), lineWidth: 1.5)

        context.draw(
            Text("✎ \(composing.author.role.displayName.uppercased()) WRITING")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(color),
            at: CGPoint(x: boxRect.minX + 12, y: boxRect.minY + 12),
            anchor: .leading
        )

        var rowY = boxRect.minY + 30
        // payload line
        if composing.payloadFilled {
            context.draw(
                Text("payload: \(msg.payload)")
                    .font(.system(size: settings.scaled(10), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85)),
                at: CGPoint(x: boxRect.minX + 12, y: rowY),
                anchor: .leading
            )
            rowY += 16
        }
        // parents line
        if composing.parentsFilled {
            let parentsText = msg.parents.isEmpty ? "(genesis)" : msg.parents.joined(separator: ", ")
            context.draw(
                Text("parents: \(parentsText)")
                    .font(.system(size: settings.scaled(10), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85)),
                at: CGPoint(x: boxRect.minX + 12, y: rowY),
                anchor: .leading
            )
            rowY += 16
        }
        // PoW progress / hash line
        if composing.sealed {
            context.draw(
                Text("hash:    \(msg.hashShort)…  ✓")
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(color.opacity(0.95)),
                at: CGPoint(x: boxRect.minX + 12, y: rowY),
                anchor: .leading
            )
        } else if composing.powProgress > 0 {
            let bars = Int(composing.powProgress * 20)
            let bar = String(repeating: "█", count: bars)
                + String(repeating: "·", count: 20 - bars)
            context.draw(
                Text("PoW:     [\(bar)]")
                    .font(.system(size: settings.scaled(10), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75)),
                at: CGPoint(x: boxRect.minX + 12, y: rowY),
                anchor: .leading
            )
        }
    }

    // MARK: - Decide arrow

    private func drawDecideArrow(
        in context: inout GraphicsContext, size: CGSize,
        decide: Ch01WorldState.DecideArrowState
    ) {
        let from = castPosition(cast: decide.from, size: size)
        let to = castPosition(cast: decide.to, size: size)
        // Curved line from sender to recipient
        var path = Path()
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        path.move(to: from)
        path.addQuadCurve(to: to,
                          control: CGPoint(x: mid.x, y: mid.y - 30))
        context.stroke(path,
                      with: .color(castColor(decide.from).opacity(0.5)),
                      style: StrokeStyle(lineWidth: 1.6, dash: [5, 5]))
        // Label at midpoint
        context.draw(
            Text("→ send \(decide.messageId) to \(decide.to.role.displayName.uppercased())")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.8)),
            at: CGPoint(x: mid.x, y: mid.y - 36)
        )
    }

    // MARK: - In-flight envelope

    private func drawInFlight(
        in context: inout GraphicsContext, size: CGSize,
        flight: Ch01WorldState.InFlightState
    ) {
        let from = castPosition(cast: flight.from, size: size)
        let to = castPosition(cast: flight.to, size: size)
        // Path
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path,
                      with: .color(castColor(flight.from).opacity(0.30)),
                      style: StrokeStyle(lineWidth: 1.0, dash: [3, 5]))
        // Envelope at progress
        let p = CGFloat(flight.progress)
        let pos = CGPoint(x: from.x + (to.x - from.x) * p,
                          y: from.y + (to.y - from.y) * p)
        guard let msg = Ch01Timeline.messages[flight.messageId] else { return }
        let envW: CGFloat = 76
        let envH: CGFloat = 32
        let rect = CGRect(x: pos.x - envW / 2, y: pos.y - envH / 2,
                          width: envW, height: envH)
        context.fill(RoundedRectangle(cornerRadius: 5).path(in: rect),
                    with: .color(castColor(flight.from).opacity(0.92)))
        context.stroke(RoundedRectangle(cornerRadius: 5).path(in: rect),
                      with: .color(.white.opacity(0.7)), lineWidth: 1.0)
        context.draw(
            Text("\(flight.messageId) · \(msg.hashShort)")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(.white),
            at: pos
        )
    }

    // MARK: - Open envelope card

    private func drawOpenEnvelope(
        in context: inout GraphicsContext, size: CGSize,
        env: Ch01WorldState.OpenEnvelopeState
    ) {
        guard let msg = Ch01Timeline.messages[env.messageId] else { return }
        let recipientPos = castPosition(cast: env.recipient, size: size)
        let cardW: CGFloat = 320
        let cardH: CGFloat = 140
        // Place to the side of the recipient that has space; if recipient
        // is on the right, put card to the left, and vice versa.
        let placeRight = recipientPos.x < size.width / 2
        let cardX: CGFloat = placeRight
            ? recipientPos.x + 56
            : recipientPos.x - 56 - cardW
        let cardY: CGFloat = recipientPos.y - cardH / 2
        let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
        let color = castColor(msg.author)

        context.fill(RoundedRectangle(cornerRadius: 10).path(in: cardRect),
                    with: .color(.black.opacity(0.88)))
        context.stroke(RoundedRectangle(cornerRadius: 10).path(in: cardRect),
                      with: .color(color.opacity(0.95)), lineWidth: 1.5)
        context.draw(
            Text("\(env.recipient.role.displayName.uppercased()) READS \(env.messageId)")
                .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                .foregroundColor(color),
            at: CGPoint(x: cardRect.minX + 12, y: cardRect.minY + 14),
            anchor: .leading
        )
        var rowY = cardRect.minY + 32
        if env.bodyRevealed {
            context.draw(
                Text("body:    \(msg.payload)")
                    .font(.system(size: settings.scaled(10), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85)),
                at: CGPoint(x: cardRect.minX + 12, y: rowY),
                anchor: .leading
            )
            rowY += 16
        }
        if env.parentsRevealed {
            let parentsText = msg.parents.isEmpty ? "(genesis)" : msg.parents.joined(separator: ", ")
            context.draw(
                Text("parents: \(parentsText)")
                    .font(.system(size: settings.scaled(10), weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85)),
                at: CGPoint(x: cardRect.minX + 12, y: rowY),
                anchor: .leading
            )
            rowY += 16
        }
        if !env.resolvedParents.isEmpty {
            let resolved = env.resolvedParents.sorted().joined(separator: ", ")
            context.draw(
                Text("resolved: \(resolved) ✓ (found in local view)")
                    .font(.system(size: settings.scaled(10), weight: .regular, design: .monospaced))
                    .foregroundColor(.green.opacity(0.85)),
                at: CGPoint(x: cardRect.minX + 12, y: rowY),
                anchor: .leading
            )
            rowY += 16
        }
        if env.verified {
            context.draw(
                Text("hash:    \(msg.hashShort)… ✓ (verified)")
                    .font(.system(size: settings.scaled(10), weight: .heavy, design: .monospaced))
                    .foregroundColor(.green.opacity(0.95)),
                at: CGPoint(x: cardRect.minX + 12, y: rowY),
                anchor: .leading
            )
        }
    }

    // MARK: - Footer

    private func drawFooter(
        in context: inout GraphicsContext, size: CGSize,
        t: Double, world: Ch01WorldState
    ) {
        let total = Ch01Timeline.totalDuration
        context.draw(
            Text(String(format: "t=%.1fs / %.0fs   ·   beat: %@",
                         t, total, world.activeBeat?.id ?? "—"))
                .font(.system(size: settings.scaled(9), weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.30)),
            at: CGPoint(x: 24, y: size.height - 14),
            anchor: .leading
        )
    }
}

// MARK: - Scene → timeline mapping

/// Each Ch01 scene maps to a window of the unified timeline. The 7 scenes
/// stay as navigation labels — arrow keys still let the viewer jump
/// between them — but the visualization is one continuous slo-mo story.
///
/// `SceneEngine` reads `durationFor(scene:)` so its auto-advance and the
/// `localTime → progress` math match. Total Ch01 duration ≈ 326s.
enum Ch01Scenes {
    /// Cumulative start time of each scene in the Ch01 timeline.
    static let sceneStarts: [Double] = [
        0,        // 0: Aaron writes α + sends to Ben     (≈ 69s)
        69,       // 1: α to Carl                         (≈ 38s)
        107,      // 2: Ben writes β + sends to Aaron     (≈ 67.5s)
        174.5,    // 3: Carl writes γ — asymmetry         (≈ 33s)
        207.5,    // 4: γ to Aaron                        (≈ 37s)
        244.5,    // 5: β to Carl                         (≈ 37.5s)
        282.0,    // 6: γ to Ben + convergence            (≈ 44.5s)
    ]

    static let sceneDurations: [Double] = [69, 38, 67.5, 33, 37, 37.5, 44.5]

    static func timelineT(sceneIndex: Int, localTime: Double) -> Double {
        let idx = max(0, min(sceneIndex, sceneStarts.count - 1))
        return sceneStarts[idx] + localTime
    }

    static func durationFor(scene: Int) -> Double {
        let idx = max(0, min(scene, sceneDurations.count - 1))
        return sceneDurations[idx]
    }

    /// Narration of the currently active beat (or scene-fallback if no
    /// beat exists at this t — shouldn't happen for sceneIndex in range).
    static func narrationAt(sceneIndex: Int, localTime: Double) -> String {
        let t = timelineT(sceneIndex: sceneIndex, localTime: localTime)
        return Ch01Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
