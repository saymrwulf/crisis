import SwiftUI

/// Ch04 — "Did you see what I saw?" (virtual voting via strongly-seeing paths).
///
/// The chapter's claim: Crisis sends no ballots and no vote messages.
/// "Voting" is just walking each player's local DAG from a recent
/// vertex back through parent edges, and checking overlap with the
/// other player's walk. If their two ancestor cones share enough
/// vertices, the two have implicitly voted the same way.

// MARK: - Types

enum Ch04BeatKind {
    case settle(label: String)
    case carryForward
    case pickLeaf(cast: Ch01Cast, messageId: String)
    /// Walk one edge from `from` to `parent` on `cast`'s lane. Animates a
    /// yellow tracer along the edge over the beat's duration.
    case walkEdge(cast: Ch01Cast, from: String, to: String)
    /// Highlight the cumulative cone for `cast` — every vertex in their
    /// walk so far gets a steady yellow ring.
    case settleCone(cast: Ch01Cast, label: String)
    /// Reveal the overlap between Aaron's and Carl's cones — shared
    /// vertices pulse white.
    case revealOverlap
    /// "Implicit vote complete — no message ever named vote was sent."
    case voteComplete
}

struct Ch04Beat: Identifiable {
    let id: String
    let kind: Ch04BeatKind
    let durationSeconds: Double
    let narration: String
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

struct Ch04WorldState {
    /// Each cast's "leaf" vertex (chosen recent vertex). Stays once picked.
    var leaves: [Ch01Cast: String] = [:]
    /// Each cast's accumulating ancestor cone (vertex ids).
    var cones: [Ch01Cast: Set<String>] = [:]
    /// Edges currently being traced — `from` is the child, `to` is the
    /// parent (matches the rest of the curriculum). Multiple edges
    /// across different casts can be active simultaneously only as the
    /// active beat dictates.
    var tracingEdge: TracingEdge? = nil
    /// Overlap (intersection) of Aaron's and Carl's cones — once
    /// `revealOverlap` fires, this is non-empty.
    var overlap: Set<String> = []
    var overlapAlpha: Double = 0
    var voteCompleteAlpha: Double = 0
    var activeBeat: Ch04Beat? = nil
    var activeProgress: Double = 0

    struct TracingEdge {
        let cast: Ch01Cast
        let from: String  // child id (the vertex we're walking from)
        let to: String    // parent id
        let progress: Double
    }
}

// MARK: - Timeline

enum Ch04Timeline {
    static let beats: [Ch04Beat] = {
        let raw: [Ch04Beat] = [
            .init(id: "carry-forward", kind: .carryForward, durationSeconds: 4.0,
                  narration: "Coming out of Ch03: every honest player has the same five messages — α, β, γ, δ, ε — with the same round assignments. Now we ask: how do they 'vote' on what they've seen, when no vote message exists?"),

            .init(id: "no-ballots", kind: .settle(label: "No ballots"),
                  durationSeconds: 5.0,
                  narration: "Crisis sends NO ballots. NO vote messages. Voting is just: 'can I trace a path through my own local graph from your recent vertex back to a shared ancestor?' If yes, we've implicitly seen the same things."),

            // Pick leaves
            .init(id: "pick-aaron-leaf", kind: .pickLeaf(cast: .aaron, messageId: "ε"),
                  durationSeconds: 3.5,
                  narration: "We pick a recent vertex from Aaron's local view. ε is the most recent message Aaron holds. Halo it on Aaron's lane."),
            .init(id: "pick-carl-leaf", kind: .pickLeaf(cast: .carl, messageId: "ε"),
                  durationSeconds: 3.5,
                  narration: "We pick a recent vertex from Carl's local view too. He also has ε at the same position on his lifeline."),

            .init(id: "explain-walk", kind: .settle(label: "Walk parent edges back"),
                  durationSeconds: 4.0,
                  narration: "Now we walk the ancestor cone of each one. The walk uses ONLY parent edges that already exist on each player's local DAG — no extra messaging."),

            // Aaron's walk: ε → γ → α
            .init(id: "aaron-walk-eps-gamma", kind: .walkEdge(cast: .aaron, from: "ε", to: "γ"),
                  durationSeconds: 4.0,
                  narration: "Aaron walks one edge back: ε's parent is γ. The yellow tracer highlights the edge as the walk happens."),
            .init(id: "aaron-walk-gamma-alpha", kind: .walkEdge(cast: .aaron, from: "γ", to: "α"),
                  durationSeconds: 4.0,
                  narration: "Aaron walks another edge back: γ's parent is α. Aaron's depth-2 cone is now {ε, γ, α}."),
            .init(id: "aaron-cone-settle", kind: .settleCone(cast: .aaron, label: "Aaron's cone"),
                  durationSeconds: 3.5,
                  narration: "Aaron's ancestor cone — three yellow rings on his lane: ε, γ, α. Anything Aaron asserts about ε implicitly carries γ and α with it."),

            // Carl's walk: ε → γ → α
            .init(id: "carl-walk-eps-gamma", kind: .walkEdge(cast: .carl, from: "ε", to: "γ"),
                  durationSeconds: 4.0,
                  narration: "Carl walks one edge back from his ε. Same parent: γ. Carl traverses the SAME edges using HIS OWN local copy of the graph."),
            .init(id: "carl-walk-gamma-alpha", kind: .walkEdge(cast: .carl, from: "γ", to: "α"),
                  durationSeconds: 4.0,
                  narration: "Carl walks one more edge back. γ's parent: α. Carl's depth-2 cone is now {ε, γ, α}."),
            .init(id: "carl-cone-settle", kind: .settleCone(cast: .carl, label: "Carl's cone"),
                  durationSeconds: 3.5,
                  narration: "Carl's ancestor cone matches: ε, γ, α — three yellow rings on his lane."),

            // Overlap reveal
            .init(id: "reveal-overlap", kind: .revealOverlap,
                  durationSeconds: 5.5,
                  narration: "Now the overlap. Aaron's cone is {ε, γ, α}. Carl's cone is {ε, γ, α}. Intersection: {ε, γ, α} — three shared vertices. They pulse white on both lanes."),

            .init(id: "two-shared-rule", kind: .settle(label: "Two shared ancestors is enough"),
                  durationSeconds: 4.5,
                  narration: "The rule: two or more shared ancestors is enough. The protocol counts overlap and concludes that Aaron and Carl have implicitly agreed on the relevant history."),

            .init(id: "vote-complete", kind: .voteComplete,
                  durationSeconds: 5.5,
                  narration: "Implicit vote complete. Aaron and Carl agree about ε's lineage. Crucially: no message named 'vote' was ever sent. The agreement is a property of arithmetic on graphs each player already has."),

            .init(id: "outro", kind: .settle(label: "Strongly-seeing"),
                  durationSeconds: 4.0,
                  narration: "This is what 'strongly-seeing path' means in the paper. Two players strongly-see a vertex when their ancestor cones reach it via paths of bounded depth. That property is the votecast — derived, not declared."),
        ]
        var t: Double = 0
        var assigned: [Ch04Beat] = []
        for var b in raw {
            b.startTime = t
            assigned.append(b)
            t += b.durationSeconds
        }
        return assigned
    }()

    static var totalDuration: Double {
        beats.last.map { $0.endTime } ?? 0
    }

    static func activeBeat(at t: Double) -> Ch04Beat? {
        let clamped = max(0, min(t, totalDuration))
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    static func state(at t: Double) -> Ch04WorldState {
        var w = Ch04WorldState()
        let clamped = max(0, min(t, totalDuration))

        for beat in beats {
            if clamped < beat.startTime { break }
            let isActive = clamped < beat.endTime
            let progress = isActive
                ? max(0, min(1, (clamped - beat.startTime) / beat.durationSeconds))
                : 1.0
            apply(beat, progress: progress, isActive: isActive, into: &w)
            if isActive {
                w.activeBeat = beat
                w.activeProgress = progress
            }
        }
        // Compute overlap when both cones exist.
        if let a = w.cones[.aaron], let c = w.cones[.carl] {
            let intersection = a.intersection(c)
            // Only surface the overlap visually after the explicit reveal beat.
            if !w.overlap.isEmpty || w.overlapAlpha > 0 {
                w.overlap = intersection
            }
        }
        return w
    }

    private static func apply(
        _ beat: Ch04Beat, progress: Double, isActive: Bool,
        into w: inout Ch04WorldState
    ) {
        switch beat.kind {
        case .settle, .carryForward:
            break
        case .pickLeaf(let cast, let mid):
            w.leaves[cast] = mid
            // The leaf is the first member of the cone.
            w.cones[cast, default: []].insert(mid)
        case .walkEdge(let cast, let from, let to):
            // Edge is currently animating; once past, the parent joins the cone.
            if isActive {
                w.tracingEdge = .init(cast: cast, from: from, to: to,
                                       progress: progress)
            }
            // Permanent: add `to` (the parent) to the cone.
            w.cones[cast, default: []].insert(to)
        case .settleCone:
            break  // cone already accumulated by walkEdge beats
        case .revealOverlap:
            w.overlapAlpha = isActive ? progress : 1.0
            // Mark non-empty so the state computation surfaces the intersection.
            if w.overlap.isEmpty {
                w.overlap = ["__placeholder__"]  // forces state code to compute
            }
        case .voteComplete:
            w.voteCompleteAlpha = isActive ? progress : 1.0
        }
    }
}

// MARK: - Scene mapping

enum Ch04Scenes {
    /// 3 scenes mapping to ~62.5s of timeline at 1×.
    static let sceneStarts: [Double] = [0, 16, 39.5]
    static let sceneDurations: [Double] = [16, 23.5, 23]

    static func timelineT(sceneIndex: Int, localTime: Double) -> Double {
        let idx = max(0, min(sceneIndex, sceneStarts.count - 1))
        return sceneStarts[idx] + localTime
    }

    static func durationFor(scene: Int) -> Double {
        let idx = max(0, min(scene, sceneDurations.count - 1))
        return sceneDurations[idx]
    }

    static func narrationAt(sceneIndex: Int, localTime: Double) -> String {
        let t = timelineT(sceneIndex: sceneIndex, localTime: localTime)
        return Ch04Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
