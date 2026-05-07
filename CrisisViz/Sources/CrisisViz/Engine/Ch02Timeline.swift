import SwiftUI

/// Ch02 — "Dave can't hear Aaron. The graph splits."
///
/// Picks up where Ch01 left off: all four cast on lanes, three messages
/// (α, β, γ) accepted into every honest player's view. Then Dave's link
/// to the gossip network drops, two new messages (δ from Aaron, ε from
/// Dave) get written, and the resulting divergence is visible
/// physically in the perception towers — Aaron/Ben/Carl have one stack,
/// Dave has another. Then the partition heals and the towers reunite.
///
/// Same architectural pattern as Ch00/Ch01: serial beats, beat-bound
/// narration, pure `state(at: t)` function.

// MARK: - Types

struct Ch02Message: Hashable {
    let id: String
    let author: Ch01Cast
    let payload: String
    let parents: [String]
    let hashShort: String
}

enum Ch02BeatKind {
    case settle(label: String)
    /// Carry-forward of the Ch01 state: Aaron/Ben/Carl/Dave all hold {α, β, γ}.
    case carryForward
    /// The link from Dave to the gossip network starts to crack —
    /// visualized as a degrading dashed line with a small ⚠.
    case linkDegrade
    /// Link fully broken — solid red ✗ on the line, and Dave's lane
    /// gets a "PARTITIONED" badge.
    case linkBroken
    case think(Ch01Cast, label: String)
    case compose(messageId: String)
    case seal(messageId: String)
    /// Fly that succeeds: same animation as Ch01.
    case fly(from: Ch01Cast, to: Ch01Cast, messageId: String)
    /// Fly that fails — the envelope animates partway, then hits a
    /// barrier and dissolves. Used while Dave is partitioned.
    case flyFailed(from: Ch01Cast, to: Ch01Cast, messageId: String)
    case acceptIntoView(at: Ch01Cast, messageId: String)
    /// The link is restored — barrier dissolves, dashed line returns.
    case linkRestored
}

struct Ch02Beat: Identifiable {
    let id: String
    let kind: Ch02BeatKind
    let durationSeconds: Double
    let narration: String
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

struct Ch02WorldState {
    var sealedMessages: Set<String> = []
    var views: [Ch01Cast: Set<String>] = [:]
    var viewOrder: [Ch01Cast: [String]] = [:]
    /// Network status from Dave's perspective. 1 = healthy, 0 = fully
    /// broken. Drives the "broken link" rendering between Dave's lane
    /// and the rest.
    var linkHealth: Double = 1.0
    /// Active animations (mutually exclusive on the timeline)
    var inFlight: InFlight? = nil
    var failedFlight: FailedFlight? = nil
    var composing: Composing? = nil
    var thought: Thought? = nil
    var activeBeat: Ch02Beat? = nil
    var activeProgress: Double = 0

    struct InFlight {
        let messageId: String
        let from: Ch01Cast
        let to: Ch01Cast
        let progress: Double
    }
    struct FailedFlight {
        let messageId: String
        let from: Ch01Cast
        let to: Ch01Cast
        /// 0..1 along the path; the failure happens at ~0.55, where the
        /// envelope hits the barrier. After that the envelope fades.
        let progress: Double
    }
    struct Composing {
        let messageId: String
        let author: Ch01Cast
        var sealed: Bool
    }
    struct Thought {
        let cast: Ch01Cast
        let label: String
    }
}

// MARK: - Timeline

enum Ch02Timeline {
    /// Two new messages introduced in this chapter.
    static let messages: [String: Ch02Message] = [
        "δ": Ch02Message(id: "δ", author: .aaron,
                          payload: "step-4-aaron",
                          parents: ["γ"], hashShort: "be1c"),
        "ε": Ch02Message(id: "ε", author: .dave,
                          payload: "step-5-dave",
                          parents: ["γ"], hashShort: "9a02"),
    ]

    /// All five messages used during Ch02 rendering (α, β, γ from Ch01
    /// already in towers; δ, ε arrive in this chapter).
    static let initialMessages: [String] = ["α", "β", "γ"]

    static let beats: [Ch02Beat] = {
        let raw: [Ch02Beat] = [
            // Phase 1: carry-forward state from Ch01
            .init(id: "carry-forward", kind: .carryForward,
                  durationSeconds: 4.0,
                  narration: "Picking up from the gossip story: Aaron, Ben, Carl and Dave all hold the same three messages — α, β, γ. Their towers are aligned. The graph is stable."),

            // Phase 2: Dave's link cracks
            .init(id: "link-degrade", kind: .linkDegrade,
                  durationSeconds: 5.0,
                  narration: "Now something changes. The network connection between Dave and the rest begins to fail. The dashed link to him cracks visibly."),
            .init(id: "link-broken", kind: .linkBroken,
                  durationSeconds: 5.0,
                  narration: "The link breaks fully. Dave can no longer send to Aaron/Ben/Carl, and theirs can no longer reach him. He is partitioned."),

            // Phase 3: Aaron writes δ; reaches honest-3 but not Dave
            .init(id: "aaron-thinks-delta", kind: .think(.aaron, label: "Time for δ."),
                  durationSeconds: 3.5,
                  narration: "Aaron decides to write a new message — δ. He has no way to know that Dave is partitioned; he just writes."),
            .init(id: "aaron-compose-delta", kind: .compose(messageId: "δ"),
                  durationSeconds: 5.0,
                  narration: "Aaron composes δ. Payload: step-4-aaron. Parents: γ — the latest he saw. Then PoW."),
            .init(id: "aaron-seal-delta", kind: .seal(messageId: "δ"),
                  durationSeconds: 3.0,
                  narration: "δ is sealed. Hash: be1c. Aaron's tower grows by one block."),
            .init(id: "delta-flies-to-ben", kind: .fly(from: .aaron, to: .ben, messageId: "δ"),
                  durationSeconds: 6.0,
                  narration: "Aaron sends δ to Ben. The link to Ben is healthy — the envelope reaches him."),
            .init(id: "ben-accepts-delta", kind: .acceptIntoView(at: .ben, messageId: "δ"),
                  durationSeconds: 3.0,
                  narration: "Ben verifies δ (parent γ resolves in his view, hash matches) and accepts. Ben's tower now includes δ."),
            .init(id: "delta-flies-to-carl", kind: .fly(from: .aaron, to: .carl, messageId: "δ"),
                  durationSeconds: 6.0,
                  narration: "Aaron sends δ to Carl too. Link healthy — δ arrives."),
            .init(id: "carl-accepts-delta", kind: .acceptIntoView(at: .carl, messageId: "δ"),
                  durationSeconds: 3.0,
                  narration: "Carl accepts δ. Three towers now hold {α, β, γ, δ}."),
            .init(id: "delta-tries-dave", kind: .flyFailed(from: .aaron, to: .dave, messageId: "δ"),
                  durationSeconds: 5.5,
                  narration: "Aaron tries to send δ to Dave too — but the envelope hits the broken link. It cannot get through. Dave's tower is unchanged."),

            // Phase 4: Dave writes ε locally — only references what HE has
            .init(id: "dave-thinks-eps", kind: .think(.dave, label: "I'll write something."),
                  durationSeconds: 4.0,
                  narration: "Meanwhile, Dave is unaware of δ. From his side of the partition, the world is still {α, β, γ}. He decides to write his own message — ε."),
            .init(id: "dave-compose-eps", kind: .compose(messageId: "ε"),
                  durationSeconds: 5.0,
                  narration: "Dave composes ε. Parents: γ — the latest he saw. He doesn't know about δ; it isn't in his local view."),
            .init(id: "dave-seal-eps", kind: .seal(messageId: "ε"),
                  durationSeconds: 3.0,
                  narration: "ε is sealed. Hash: 9a02. Dave's tower grows — but with a DIFFERENT next block than Aaron/Ben/Carl have."),
            .init(id: "eps-tries-aaron", kind: .flyFailed(from: .dave, to: .aaron, messageId: "ε"),
                  durationSeconds: 5.5,
                  narration: "Dave tries to send ε out — also hits the broken link. ε stays trapped on Dave's side. Two stories now live on the canvas."),
            .init(id: "divergence-settle", kind: .settle(label: "Two stories"),
                  durationSeconds: 5.0,
                  narration: "Look at the towers. Aaron, Ben and Carl share {α, β, γ, δ}. Dave has {α, β, γ, ε}. Both internally consistent — that's exactly the danger of partitions."),

            // Phase 5: heal
            .init(id: "link-restored", kind: .linkRestored,
                  durationSeconds: 5.0,
                  narration: "The connection comes back. The barrier dissolves; the dashed link to Dave is restored."),
            .init(id: "delta-finally-dave", kind: .fly(from: .aaron, to: .dave, messageId: "δ"),
                  durationSeconds: 6.0,
                  narration: "δ floods through the gap. Aaron's pending message reaches Dave at last."),
            .init(id: "dave-accepts-delta", kind: .acceptIntoView(at: .dave, messageId: "δ"),
                  durationSeconds: 3.0,
                  narration: "Dave verifies δ (parent γ is in his view, hash matches) and accepts. His tower now contains {α, β, γ, ε, δ}. Notice ε comes BEFORE δ in his stack — that's his local history."),
            .init(id: "eps-finally-aaron", kind: .fly(from: .dave, to: .aaron, messageId: "ε"),
                  durationSeconds: 6.0,
                  narration: "ε floods the other way. Dave's pending message reaches Aaron."),
            .init(id: "aaron-accepts-eps", kind: .acceptIntoView(at: .aaron, messageId: "ε"),
                  durationSeconds: 3.0,
                  narration: "Aaron accepts ε. His tower: {α, β, γ, δ, ε}."),
            .init(id: "eps-flies-ben", kind: .fly(from: .aaron, to: .ben, messageId: "ε"),
                  durationSeconds: 5.0,
                  narration: "Aaron forwards ε to Ben."),
            .init(id: "ben-accepts-eps", kind: .acceptIntoView(at: .ben, messageId: "ε"),
                  durationSeconds: 3.0,
                  narration: "Ben accepts ε."),
            .init(id: "eps-flies-carl", kind: .fly(from: .aaron, to: .carl, messageId: "ε"),
                  durationSeconds: 5.0,
                  narration: "Aaron forwards ε to Carl."),
            .init(id: "carl-accepts-eps", kind: .acceptIntoView(at: .carl, messageId: "ε"),
                  durationSeconds: 3.0,
                  narration: "Carl accepts ε. Four towers now hold the same set {α, β, γ, δ, ε}, but in slightly different ORDERS — that's still local order, not yet total order."),

            .init(id: "convergence", kind: .settle(label: "Reunited"),
                  durationSeconds: 5.0,
                  narration: "The partition is over. The graph reunifies. Different validators recorded events in different orders during the split — but the SET of events is the same. Total order, in a later chapter, will give us the canonical sequence."),
        ]

        var t: Double = 0
        var assigned: [Ch02Beat] = []
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

    static func activeBeat(at t: Double) -> Ch02Beat? {
        let clamped = max(0, min(t, totalDuration))
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    static func state(at t: Double) -> Ch02WorldState {
        var w = Ch02WorldState()
        // Carry-forward: every cast starts the chapter with {α, β, γ}.
        for cast in Ch01Cast.allCases {
            w.views[cast] = Set(initialMessages)
            w.viewOrder[cast] = initialMessages
        }
        for mid in initialMessages { w.sealedMessages.insert(mid) }

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
        _ beat: Ch02Beat, progress: Double, isActive: Bool,
        into w: inout Ch02WorldState
    ) {
        switch beat.kind {
        case .settle, .carryForward:
            break
        case .linkDegrade:
            // Health goes 1 → 0.4 over the beat
            let target = 0.4
            w.linkHealth = isActive ? (1 - (1 - target) * progress) : target
        case .linkBroken:
            w.linkHealth = 0.0
        case .linkRestored:
            // Health goes 0 → 1 over the beat
            w.linkHealth = isActive ? progress : 1.0
        case .think(let cast, let label):
            if isActive {
                w.thought = .init(cast: cast, label: label)
            }
        case .compose(let mid):
            if w.composing?.messageId != mid,
               let msg = messages[mid] {
                w.composing = .init(messageId: mid, author: msg.author, sealed: false)
            }
        case .seal(let mid):
            w.sealedMessages.insert(mid)
            if let msg = messages[mid] {
                w.views[msg.author, default: []].insert(mid)
                if !w.viewOrder[msg.author, default: []].contains(mid) {
                    w.viewOrder[msg.author, default: []].append(mid)
                }
            }
            if !isActive { w.composing = nil }
            else if let msg = messages[mid] {
                w.composing = .init(messageId: mid, author: msg.author, sealed: true)
            }
        case .fly(let from, let to, let mid):
            if isActive {
                w.inFlight = .init(messageId: mid, from: from, to: to, progress: progress)
            }
        case .flyFailed(let from, let to, let mid):
            if isActive {
                w.failedFlight = .init(messageId: mid, from: from, to: to, progress: progress)
            }
        case .acceptIntoView(let at, let mid):
            w.views[at, default: []].insert(mid)
            if !w.viewOrder[at, default: []].contains(mid) {
                w.viewOrder[at, default: []].append(mid)
            }
        }
    }
}

// MARK: - Scene mapping

enum Ch02Scenes {
    /// 4 scenes, durations matched to the beat-group cumulative times.
    /// Total Ch02 ≈ 115.5s at 1×.
    static let sceneStarts: [Double] = [0, 14, 49, 71.5]
    static let sceneDurations: [Double] = [14, 35, 22.5, 44]

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
        return Ch02Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
