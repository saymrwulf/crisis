import SwiftUI

/// Ch06 — "Spokespersons line up. Everyone else falls in behind." (Total order.)
///
/// With round leaders chosen in Ch05, the chapter walks the chain of
/// leaders and adds each leader's round-N ancestor closure to a single
/// linear sequence — the total order. Visualized as an "ordering snake"
/// at the bottom of the canvas: blocks slide into positions 1, 2, 3, …
/// in topological order.

enum Ch06BeatKind {
    case settle(label: String)
    case carryForward
    /// Slide a single message into the next position of the ordering snake.
    case appendToOrder(messageId: String)
    /// "ROUND N ORDERED" badge on the snake.
    case roundOrderedBadge(round: Int)
    /// Final convergence emphasis.
    case finalConvergence
}

struct Ch06Beat: Identifiable {
    let id: String
    let kind: Ch06BeatKind
    let durationSeconds: Double
    let narration: String
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

struct Ch06WorldState {
    /// Total-order snake: messages in the order they've been ordered.
    var order: [String] = []
    /// "Round N ordered" badge alpha (0..1) per round.
    var roundOrderedAlpha: [Int: Double] = [:]
    var finalConvergenceAlpha: Double = 0
    var activeBeat: Ch06Beat? = nil
    var activeProgress: Double = 0
}

enum Ch06Timeline {
    static let beats: [Ch06Beat] = {
        let raw: [Ch06Beat] = [
            .init(id: "carry-forward", kind: .carryForward, durationSeconds: 4.0,
                  narration: "From Ch05: we have round-0 leader α and round-1 leader ε. Now we use those leaders to build a single canonical sequence — the total order — that every honest validator agrees on."),

            .init(id: "intro-totalorder", kind: .settle(label: "Total order via leaders"),
                  durationSeconds: 5.0,
                  narration: "Algorithm: walk the chain of round leaders. For each leader, add the leader's round-N ancestor closure to the order in topological sequence. Look at the bottom of the canvas — the ordering snake will fill in left to right."),

            // Round 0: α, β, γ, δ — topological order based on parent edges
            .init(id: "append-alpha", kind: .appendToOrder(messageId: "α"),
                  durationSeconds: 4.5,
                  narration: "α has no parents — it goes into position 1 of the snake."),
            .init(id: "append-beta", kind: .appendToOrder(messageId: "β"),
                  durationSeconds: 4.5,
                  narration: "β references α as parent. α is already in the snake, so β goes into position 2."),
            .init(id: "append-gamma", kind: .appendToOrder(messageId: "γ"),
                  durationSeconds: 4.5,
                  narration: "γ also references α. β and γ are siblings — they go in lexicographic order, so γ takes position 3."),
            .init(id: "append-delta", kind: .appendToOrder(messageId: "δ"),
                  durationSeconds: 4.5,
                  narration: "δ references γ. γ is already in the snake at position 3, so δ goes into position 4."),

            .init(id: "round-0-ordered", kind: .roundOrderedBadge(round: 0),
                  durationSeconds: 5.0,
                  narration: "Round 0 ordered. The snake holds α, β, γ, δ in positions 1 through 4. Crucially, every honest validator who has the same DAG runs the same sort and produces the same four-element prefix."),

            // Round 1: ε
            .init(id: "append-eps", kind: .appendToOrder(messageId: "ε"),
                  durationSeconds: 4.5,
                  narration: "Round 1 leader ε — no other round-1 messages. ε goes into position 5."),

            .init(id: "round-1-ordered", kind: .roundOrderedBadge(round: 1),
                  durationSeconds: 4.5,
                  narration: "Round 1 ordered. The snake now holds the full total order: α → β → γ → δ → ε."),

            .init(id: "final-convergence", kind: .finalConvergence,
                  durationSeconds: 6.5,
                  narration: "Every honest validator's snake is byte-for-byte identical. Aaron's line, Ben's line, Carl's line, Dave's line — same sequence. This is total order: convergence on the SHAPE and the SEQUENCE of history."),

            .init(id: "outro", kind: .settle(label: "Ordered"),
                  durationSeconds: 4.0,
                  narration: "Crisis has converged on a single canonical sequence. Next chapters: data availability — what happens when a leader knows something but doesn't share it."),
        ]
        var t: Double = 0
        var assigned: [Ch06Beat] = []
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

    static func activeBeat(at t: Double) -> Ch06Beat? {
        let clamped = max(0, min(t, totalDuration))
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    static func state(at t: Double) -> Ch06WorldState {
        var w = Ch06WorldState()
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
        return w
    }

    private static func apply(
        _ beat: Ch06Beat, progress: Double, isActive: Bool,
        into w: inout Ch06WorldState
    ) {
        switch beat.kind {
        case .settle, .carryForward:
            break
        case .appendToOrder(let mid):
            // Permanent once the beat starts: the message is added.
            // The renderer animates the slide-in based on activeProgress.
            if !w.order.contains(mid) {
                w.order.append(mid)
            }
        case .roundOrderedBadge(let r):
            w.roundOrderedAlpha[r] = isActive ? progress : 1.0
        case .finalConvergence:
            w.finalConvergenceAlpha = isActive ? progress : 1.0
        }
    }
}

enum Ch06Scenes {
    /// 3 scenes mapping to ~51.5s of timeline at 1×.
    static let sceneStarts: [Double] = [0, 22.5, 36.5]
    static let sceneDurations: [Double] = [22.5, 14, 15]

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
        return Ch06Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
