import SwiftUI

/// Ch03 — "Counting witnesses to mark a round."
///
/// The chapter is about ROUND DERIVATION: round numbers in Crisis are
/// computed from accumulated proof-of-work weight, not declared or
/// negotiated. The chapter walks through the five messages from
/// Ch01/Ch02 (α through ε) and shows weight summing into a thermometer
/// at the top of the canvas. When a threshold is crossed, the message
/// that pushed weight over the line earns the `is_last` flag — that's
/// the round boundary marker.

// MARK: - Types

enum Ch03BeatKind {
    case settle(label: String)
    case carryForward                              // initial state from Ch02
    case introduceWeights                          // each vertex shows its weight
    case highlightVertex(messageId: String)        // thermometer adds weight
    case markIsLast(messageId: String)             // yellow ring + boundary badge
    case openNewRound(roundNumber: Int)            // increment round counter
    case bookkeepingNote(text: String)             // overlay text only
    case reGossipDuplicate(messageId: String, recipient: Ch01Cast)  // duplicate ignored
}

struct Ch03Beat: Identifiable {
    let id: String
    let kind: Ch03BeatKind
    let durationSeconds: Double
    let narration: String
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

struct Ch03WorldState {
    var weightsVisible: Bool = false      // show weight=1 labels next to vertices
    var roundOf: [String: Int] = [:]      // message id → round number once derived
    var isLastSet: Set<String> = []       // messages flagged is_last
    var highlighted: String? = nil        // currently focused vertex (halo)
    var currentRound: Int = 0
    var thermometerWeight: Double = 0     // accumulated weight in current round
    var thermometerThreshold: Double = 4  // round closes when weight ≥ threshold
    var bookkeepingText: String? = nil
    var reGossipFlash: ReGossip? = nil
    var activeBeat: Ch03Beat? = nil
    var activeProgress: Double = 0

    struct ReGossip {
        let messageId: String
        let recipient: Ch01Cast
        let progress: Double
    }
}

// MARK: - Timeline

enum Ch03Timeline {
    /// Each message has weight 1 in this chapter (PoW puzzles all the
    /// same difficulty). Round threshold = 4, so α/β/γ/δ close round 0
    /// (δ is_last) and ε opens round 1.
    static let messageWeights: [String: Double] = [
        "α": 1, "β": 1, "γ": 1, "δ": 1, "ε": 1,
    ]
    static let messageOrder: [String] = ["α", "β", "γ", "δ", "ε"]
    static let threshold: Double = 4

    static let beats: [Ch03Beat] = {
        let raw: [Ch03Beat] = [
            .init(id: "carry-forward", kind: .carryForward, durationSeconds: 4.0,
                  narration: "Coming out of the partition: all four cast members hold the same five messages — α, β, γ, δ, ε. Now we ask a different question. What ROUND is each one in? And how do we even know?"),

            .init(id: "introduce-weights", kind: .introduceWeights, durationSeconds: 5.0,
                  narration: "First, every message carries a proof-of-work weight. Harder puzzles → heavier messages. In this demo each message has weight 1. The little 'w=1' label appears next to each vertex on every lane."),

            .init(id: "thermometer-explained", kind: .settle(label: "Thermometer at the top"),
                  durationSeconds: 4.0,
                  narration: "Look at the top of the canvas. The thermometer accumulates weight as we count messages within the current round. The dotted line on it is the round-closing threshold."),

            // Walk through α/β/γ/δ — each contributes weight to round 0
            .init(id: "highlight-alpha", kind: .highlightVertex(messageId: "α"), durationSeconds: 3.5,
                  narration: "α is the first vertex on every lane. Round 0. Weight 1. The thermometer ticks up to 1."),
            .init(id: "highlight-beta", kind: .highlightVertex(messageId: "β"), durationSeconds: 3.5,
                  narration: "β references α — still inside round 0. Weight 1. Thermometer ticks up to 2."),
            .init(id: "highlight-gamma", kind: .highlightVertex(messageId: "γ"), durationSeconds: 3.5,
                  narration: "γ also references α — still inside round 0. Weight 1. Thermometer ticks up to 3."),
            .init(id: "highlight-delta", kind: .highlightVertex(messageId: "δ"), durationSeconds: 4.0,
                  narration: "δ references γ — still inside round 0 because we haven't crossed the threshold yet. Weight 1. Thermometer ticks up to 4 — exactly the threshold."),

            .init(id: "mark-delta-islast", kind: .markIsLast(messageId: "δ"),
                  durationSeconds: 5.5,
                  narration: "The threshold is met. δ — the message that pushed weight over the line — gets the is_last flag. A yellow ring marks it on every lane that holds it. Round 0 has closed."),

            .init(id: "round-0-closed-settle", kind: .settle(label: "Round 0 closed"),
                  durationSeconds: 4.0,
                  narration: "Crucially: NOBODY VOTED. Nobody declared the boundary. Every honest player who has the same five messages computes the same total weight, sees δ push over the same threshold, and flags δ as is_last. Round 0 is DERIVED, not declared."),

            // Open round 1 with ε
            .init(id: "open-round-1", kind: .openNewRound(roundNumber: 1), durationSeconds: 3.0,
                  narration: "The thermometer resets. Round 1 begins."),
            .init(id: "highlight-eps", kind: .highlightVertex(messageId: "ε"), durationSeconds: 4.0,
                  narration: "ε is the first vertex of round 1. It references γ as a parent — old parents are perfectly legitimate. Round 1 has weight 1 so far. The threshold has not been met, so round 1 is still open — no message in round 1 has been flagged is_last yet."),

            .init(id: "round-1-open-settle", kind: .settle(label: "Round 1 still open"),
                  durationSeconds: 3.5,
                  narration: "If more messages get written and accepted, weight will accumulate in round 1, and eventually some message will close it. Same arithmetic, same outcome on every honest validator."),

            // Bookkeeping note
            .init(id: "bookkeeping-1", kind: .bookkeepingNote(text: "Each player keeps their own DAG. Full stop."),
                  durationSeconds: 5.0,
                  narration: "Bookkeeping: every honest player keeps their own DAG of received messages. Nothing else. Nobody tracks who-sent-what-to-whom; the gossip layer fans out and the digest dedupes on the receiver."),
            .init(id: "bookkeeping-2", kind: .bookkeepingNote(text: "Re-gossip is harmless."),
                  durationSeconds: 4.0,
                  narration: "Re-gossip is harmless. If the same message arrives twice, the receiver detects the duplicate by its hash and drops the second copy. Watch."),

            // Demonstrate duplicate dropping
            .init(id: "regossip-alpha-ben", kind: .reGossipDuplicate(messageId: "α", recipient: .ben),
                  durationSeconds: 5.5,
                  narration: "Aaron tries to re-send α to Ben. Ben already has α in his view. The envelope arrives, the hash is matched against his local set, the duplicate is detected, and the message is dropped. No tower update. No round-weight change. The system stays consistent."),

            .init(id: "weight-arithmetic", kind: .bookkeepingNote(text: "Weight is arithmetic. Arithmetic doesn't depend on who you ask."),
                  durationSeconds: 6.0,
                  narration: "Weight is arithmetic. Arithmetic doesn't depend on who you ask. As long as two honest validators have the same set of accepted messages, they compute the same round numbers — without exchanging any vote, any negotiation, any consensus message at all."),

            .init(id: "outro", kind: .settle(label: "Rounds derived"),
                  durationSeconds: 4.0,
                  narration: "Rounds are now defined. Next chapter: how a leader is picked from each round, and how the round leaders chain into a total order."),
        ]
        var t: Double = 0
        var assigned: [Ch03Beat] = []
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

    static func activeBeat(at t: Double) -> Ch03Beat? {
        let clamped = max(0, min(t, totalDuration))
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    static func state(at t: Double) -> Ch03WorldState {
        var w = Ch03WorldState()
        // All five messages start in round 0; markIsLast/openNewRound
        // promotes ε to round 1.
        for mid in messageOrder { w.roundOf[mid] = 0 }

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
        _ beat: Ch03Beat, progress: Double, isActive: Bool,
        into w: inout Ch03WorldState
    ) {
        switch beat.kind {
        case .settle, .carryForward:
            break
        case .introduceWeights:
            // Permanent fade-in: once visible, stays visible.
            w.weightsVisible = true
        case .highlightVertex(let mid):
            if isActive {
                w.highlighted = mid
            }
            // Even if past, the vertex's weight has been added to the
            // thermometer.
            if let weight = messageWeights[mid] {
                if isActive {
                    w.thermometerWeight += weight * progress
                } else {
                    w.thermometerWeight += weight
                }
            }
        case .markIsLast(let mid):
            // Permanent: the message gets the is_last flag once the beat
            // starts (so the yellow ring appears immediately).
            w.isLastSet.insert(mid)
            if isActive {
                w.highlighted = mid
            }
        case .openNewRound(let roundNum):
            // Permanent: thermometer resets, round counter increments.
            w.currentRound = roundNum
            w.thermometerWeight = 0
            // Promote ε's round number once round 1 opens.
            for mid in messageOrder where (w.isLastSet.contains(mid) == false && w.roundOf[mid] == 0) {
                // Messages NOT flagged is_last but in the round-0 batch
                // stay at round 0; messages AFTER δ go into round 1.
                if mid == "ε" {
                    w.roundOf[mid] = 1
                }
            }
        case .bookkeepingNote(let text):
            if isActive {
                w.bookkeepingText = text
            }
        case .reGossipDuplicate(let mid, let recipient):
            if isActive {
                w.reGossipFlash = .init(messageId: mid, recipient: recipient,
                                         progress: progress)
            }
        }
    }
}

// MARK: - Scene mapping

enum Ch03Scenes {
    /// 3 scenes mapping to ~72s of timeline at 1×.
    static let sceneStarts: [Double] = [0, 23.5, 44.0]
    static let sceneDurations: [Double] = [23.5, 20.5, 28.0]

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
        return Ch03Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
