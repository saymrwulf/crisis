import SwiftUI

/// Ch08 — "Erasure shards make the data un-loseable." (DA fix.)
///
/// Aaron splits ξ's body into 4 erasure-coded shards (s1, s2, s3, s4)
/// where any 2 are enough to reconstruct (k=2 of n=4). One shard each
/// flies to Ben, Carl, Dave; one stays with Aaron. Then Aaron goes
/// silent. Carl needs ξ's body, asks Ben for s1, combines with his
/// own s2 — k=2 reached, body reconstructed. The DA problem is fixed.

enum Ch08BeatKind {
    case settle(label: String)
    case carryForward
    case splitIntoShards            // ξ body split into s1..s4
    case sendShard(id: String, to: Ch01Cast)
    case stowShard(at: Ch01Cast, id: String)
    case aaronOffline
    case askForShard(asker: Ch01Cast, target: Ch01Cast, id: String)
    case shardArrives(at: Ch01Cast, id: String)
    case reconstructBody(at: Ch01Cast)   // collected k shards → reform body
    case reconstructed                   // green badge
    case finalSummary                    // wrap-up
}

struct Ch08Beat: Identifiable {
    let id: String
    let kind: Ch08BeatKind
    let durationSeconds: Double
    let narration: String
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

struct Ch08WorldState {
    /// Whether ξ has been split into shards.
    var split: Bool = false
    /// Shards each cast holds (at most one per cast in this demo).
    var shardsAt: [Ch01Cast: Set<String>] = [:]
    /// In-flight shard envelope (success path).
    var shardFlight: ShardFlight? = nil
    /// Aaron has gone silent.
    var aaronOffline: Bool = false
    /// Reconstruction state: who has reconstructed ξ's body.
    var reconstructedAt: Set<Ch01Cast> = []
    var reconstructFlash: Ch01Cast? = nil
    var reconstructProgress: Double = 0
    var reconstructedAlpha: Double = 0
    var finalAlpha: Double = 0
    var activeBeat: Ch08Beat? = nil
    var activeProgress: Double = 0

    struct ShardFlight {
        let id: String
        let from: Ch01Cast
        let to: Ch01Cast
        let progress: Double
    }
}

enum Ch08Timeline {
    /// k=2 of n=4. Any 2 of {s1, s2, s3, s4} reconstructs ξ.
    static let shardIds: [String] = ["s1", "s2", "s3", "s4"]
    static let k: Int = 2

    static let beats: [Ch08Beat] = {
        let raw: [Ch08Beat] = [
            .init(id: "carry-forward", kind: .carryForward, durationSeconds: 4.0,
                  narration: "Coming out of Ch07's DA problem: ξ's body lives only in Aaron's vault. Time for the fix — erasure coding."),

            .init(id: "intro-ec", kind: .settle(label: "Erasure coding"),
                  durationSeconds: 5.0,
                  narration: "Aaron will split ξ's body into 4 shards using Reed-Solomon-like erasure coding. The trick: any 2 of the 4 shards is enough to reconstruct the whole body. So data survives even if half the storage nodes are offline."),

            .init(id: "split", kind: .splitIntoShards, durationSeconds: 8.0,
                  narration: "ξ's body is sliced and erasure-encoded into s1, s2, s3, s4. Each shard is roughly half the size of the original body — but together, even 2 of them suffice."),

            // Distribute one shard to each cast.
            .init(id: "send-s1-ben", kind: .sendShard(id: "s1", to: .ben), durationSeconds: 4.5,
                  narration: "Aaron sends s1 to Ben."),
            .init(id: "stow-s1-ben", kind: .stowShard(at: .ben, id: "s1"),
                  durationSeconds: 3.0,
                  narration: "Ben stows s1 in his vault."),
            .init(id: "send-s2-carl", kind: .sendShard(id: "s2", to: .carl), durationSeconds: 4.5,
                  narration: "Aaron sends s2 to Carl."),
            .init(id: "stow-s2-carl", kind: .stowShard(at: .carl, id: "s2"),
                  durationSeconds: 3.0,
                  narration: "Carl stows s2."),
            .init(id: "send-s3-dave", kind: .sendShard(id: "s3", to: .dave), durationSeconds: 4.5,
                  narration: "Aaron sends s3 to Dave. Yes — even Dave the byzantine can be a storage node. Storing a shard is harmless; tampering with it would just be detected via the shard's commitment."),
            .init(id: "stow-s3-dave", kind: .stowShard(at: .dave, id: "s3"),
                  durationSeconds: 3.0,
                  narration: "Dave stows s3."),
            .init(id: "stow-s4-aaron", kind: .stowShard(at: .aaron, id: "s4"),
                  durationSeconds: 3.0,
                  narration: "s4 stays in Aaron's own vault. So now: each of the four nodes holds exactly one shard."),

            .init(id: "distributed-settle", kind: .settle(label: "Distributed"),
                  durationSeconds: 4.5,
                  narration: "All four shards are out in the world. The body of ξ no longer lives in any single place. This is the structural shift."),

            // Aaron goes silent.
            .init(id: "aaron-offline", kind: .aaronOffline, durationSeconds: 5.0,
                  narration: "Now suppose Aaron goes offline. Or refuses to share. Or vanishes. In Ch07 this would have been game over. Watch what happens now."),

            // Reconstruction: Carl needs ξ's body, has s2, asks Ben for s1.
            .init(id: "ask-ben-s1", kind: .askForShard(asker: .carl, target: .ben, id: "s1"),
                  durationSeconds: 4.5,
                  narration: "Carl needs ξ's body. He already holds s2. He asks Ben for s1."),
            .init(id: "ben-sends-s1", kind: .sendShard(id: "s1", to: .carl), durationSeconds: 4.5,
                  narration: "Ben has no reason to refuse — sharing a shard is a tiny operation. s1 flies to Carl."),
            .init(id: "carl-receives-s1", kind: .shardArrives(at: .carl, id: "s1"),
                  durationSeconds: 3.0,
                  narration: "Carl now holds s1 and s2 — that's k=2 of 4 shards. The threshold is reached."),

            .init(id: "reconstruct", kind: .reconstructBody(at: .carl),
                  durationSeconds: 6.0,
                  narration: "Carl runs the erasure-coding decoder on s1 + s2. The original body of ξ pops out — bit-for-bit identical to what Aaron originally wrote."),

            .init(id: "reconstructed", kind: .reconstructed, durationSeconds: 5.0,
                  narration: "ξ's body is reconstructed in Carl's vault — even though Aaron is silent, even without ever talking to Dave. k-of-n is enough."),

            .init(id: "final-summary", kind: .finalSummary, durationSeconds: 6.0,
                  narration: "And that closes the curriculum: consensus on the DAG, derived round numbers, virtual voting, leader election, total order, byzantine resilience under f<n/3, and now data availability via erasure coding. Crisis works. Thanks for watching."),

            .init(id: "outro", kind: .settle(label: "End"),
                  durationSeconds: 4.0,
                  narration: "End of the curriculum. Pull the speed slider in either direction to scrub through any chapter as a movie editor would."),
        ]
        var t: Double = 0
        var assigned: [Ch08Beat] = []
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

    static func activeBeat(at t: Double) -> Ch08Beat? {
        let clamped = max(0, min(t, totalDuration))
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    static func state(at t: Double) -> Ch08WorldState {
        var w = Ch08WorldState()
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
        _ beat: Ch08Beat, progress: Double, isActive: Bool,
        into w: inout Ch08WorldState
    ) {
        switch beat.kind {
        case .settle, .carryForward:
            break
        case .splitIntoShards:
            w.split = true
        case .sendShard(let id, let to):
            if isActive {
                // Determine sender from the beat id naming convention or
                // the world state. For simplicity: Aaron is sender for
                // initial distribution, Ben is sender when carl-asks-ben
                // beat preceded.
                let from: Ch01Cast = (w.shardsAt[.ben]?.contains(id) == true && to == .carl)
                    ? .ben
                    : .aaron
                w.shardFlight = .init(id: id, from: from, to: to, progress: progress)
            }
        case .stowShard(let at, let id):
            w.shardsAt[at, default: []].insert(id)
        case .aaronOffline:
            w.aaronOffline = true
        case .askForShard:
            // Visual could draw an arrow; for now just narration drives.
            break
        case .shardArrives(let at, let id):
            // Permanent: recipient now holds the shard.
            w.shardsAt[at, default: []].insert(id)
        case .reconstructBody(let at):
            if isActive {
                w.reconstructFlash = at
                w.reconstructProgress = progress
            } else {
                w.reconstructedAt.insert(at)
            }
        case .reconstructed:
            w.reconstructedAlpha = isActive ? progress : 1.0
        case .finalSummary:
            w.finalAlpha = isActive ? progress : 1.0
        }
    }
}

enum Ch08Scenes {
    /// 5 scenes mapping to ~85s of timeline at 1×.
    static let sceneStarts: [Double] = [0, 17, 47, 64, 75]
    static let sceneDurations: [Double] = [17, 30, 17, 11, 10]

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
        return Ch08Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
