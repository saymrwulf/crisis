import SwiftUI

/// Ch05 — "One vertex per round becomes the spokesperson." (Leader election.)
///
/// In each round, every validator's heaviest in-round vertex competes
/// for round leadership. The protocol picks the heaviest; ties are
/// broken by lexicographic hash. The result is a deterministic leader
/// per round: every honest player who has the same DAG picks the same
/// leader without exchanging any messages.

// MARK: - Types

enum Ch05BeatKind {
    case settle(label: String)
    case carryForward
    /// Highlight the candidates in round `r` (yellow rings on each).
    case showCandidates(round: Int, candidates: [String])
    /// "Weight = 1" tally appears next to each candidate.
    case showWeights(round: Int)
    /// Animate a tiebreaker arrow comparing two candidates by hash.
    case tiebreakerCompare(round: Int)
    /// Crown the winner — gold ring + "LEADER" label.
    case crownLeader(round: Int, messageId: String)
    /// "Determinism" emphasis: same DAG, same leaders, no comms.
    case determinismBadge
}

struct Ch05Beat: Identifiable {
    let id: String
    let kind: Ch05BeatKind
    let durationSeconds: Double
    let narration: String
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

struct Ch05WorldState {
    /// Round-N candidates highlighted with yellow rings.
    var candidates: [Int: [String]] = [:]
    var weightsVisible: [Int: Bool] = [:]
    /// Tiebreaker comparison flash.
    var tiebreakerActive: Int? = nil
    var tiebreakerProgress: Double = 0
    /// Leader per round. Crown is permanent once set.
    var leaders: [Int: String] = [:]
    var determinismAlpha: Double = 0
    var activeBeat: Ch05Beat? = nil
    var activeProgress: Double = 0
}

// MARK: - Timeline

enum Ch05Timeline {
    /// Round assignments come from Ch03's derivation: α/β/γ/δ are
    /// round 0; ε is round 1.
    static let roundOf: [String: Int] = [
        "α": 0, "β": 0, "γ": 0, "δ": 0, "ε": 1
    ]

    static let beats: [Ch05Beat] = {
        let raw: [Ch05Beat] = [
            .init(id: "carry-forward", kind: .carryForward, durationSeconds: 4.0,
                  narration: "Picking up after Ch04's strongly-seeing observation: every honest player has the same five messages and the same round assignments. Now we ask: who SPEAKS for each round? Crisis calls this the round leader."),

            .init(id: "intro-leader", kind: .settle(label: "Round leader = round spokesperson"),
                  durationSeconds: 4.5,
                  narration: "In each round, every validator's heaviest in-round vertex competes for round leadership. Heaviest wins. Ties break by lexicographic hash. There is no ballot. There is no announcement. The leader is whichever vertex the arithmetic picks."),

            .init(id: "candidates-round-0", kind: .showCandidates(round: 0, candidates: ["α", "β", "γ", "δ"]),
                  durationSeconds: 4.5,
                  narration: "Round 0 candidates: α, β, γ, δ. Yellow rings highlight each on every cast lane. They are the four messages assigned to round 0 by the weight thermometer in Ch03."),

            .init(id: "weights-round-0", kind: .showWeights(round: 0),
                  durationSeconds: 5.0,
                  narration: "Weight tally: w=1 for every candidate. All four tied. We need a tiebreaker — Crisis uses lexicographic comparison of the hashes."),

            .init(id: "tiebreak-0", kind: .tiebreakerCompare(round: 0),
                  durationSeconds: 6.0,
                  narration: "Compare hashes pairwise: 43f3 < 5ce9 < 7638 < be1c — α has the smallest hash. The tiebreaker resolves cleanly. Same comparison, same answer, on every honest player."),

            .init(id: "crown-alpha", kind: .crownLeader(round: 0, messageId: "α"),
                  durationSeconds: 5.0,
                  narration: "α wins round 0. A gold crown ring + 'LEADER · r0' label appears on α on every lane. α is now the round-0 spokesperson — the message that represents that round in the chapters that follow."),

            // Round 1
            .init(id: "candidates-round-1", kind: .showCandidates(round: 1, candidates: ["ε"]),
                  durationSeconds: 4.0,
                  narration: "Round 1 candidates: just ε. With only one candidate, no tiebreaker is needed."),

            .init(id: "crown-eps", kind: .crownLeader(round: 1, messageId: "ε"),
                  durationSeconds: 4.5,
                  narration: "ε wins round 1 unopposed. Gold crown + 'LEADER · r1' label. ε is now the round-1 spokesperson."),

            .init(id: "determinism", kind: .determinismBadge,
                  durationSeconds: 6.0,
                  narration: "Determinism: every honest validator who holds the same five messages computes the same weight, runs the same tiebreaker, and crowns the same leaders. No vote was sent. No coordination occurred. Yet they all agree."),

            .init(id: "outro", kind: .settle(label: "Leaders chosen"),
                  durationSeconds: 4.0,
                  narration: "Round 0 leader: α. Round 1 leader: ε. Next chapter — Ch06 — chains these round leaders into the total order that everyone needs."),
        ]
        var t: Double = 0
        var assigned: [Ch05Beat] = []
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

    static func activeBeat(at t: Double) -> Ch05Beat? {
        let clamped = max(0, min(t, totalDuration))
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    static func state(at t: Double) -> Ch05WorldState {
        var w = Ch05WorldState()
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
        _ beat: Ch05Beat, progress: Double, isActive: Bool,
        into w: inout Ch05WorldState
    ) {
        switch beat.kind {
        case .settle, .carryForward:
            break
        case .showCandidates(let r, let cands):
            w.candidates[r] = cands
        case .showWeights(let r):
            w.weightsVisible[r] = true
        case .tiebreakerCompare(let r):
            if isActive {
                w.tiebreakerActive = r
                w.tiebreakerProgress = progress
            }
        case .crownLeader(let r, let mid):
            w.leaders[r] = mid
        case .determinismBadge:
            w.determinismAlpha = isActive ? progress : 1.0
        }
    }
}

// MARK: - Scene mapping

enum Ch05Scenes {
    /// 2 scenes mapping to ~47.5s of timeline at 1×.
    static let sceneStarts: [Double] = [0, 29]
    static let sceneDurations: [Double] = [29, 18.5]

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
        return Ch05Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
