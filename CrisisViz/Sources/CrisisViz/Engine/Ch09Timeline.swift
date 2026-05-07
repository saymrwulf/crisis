import SwiftUI

/// Ch09 — "Dave lies. Crisis catches him."
///
/// Dave produces two conflicting messages under the same identity,
/// sends one to Aaron and a different one to Ben, and tries to make
/// the honest validators disagree about what they saw. The protocol
/// catches him: as soon as Aaron and Ben gossip with each other, a
/// fork is detected, Dave's vertices are banned, and the honest 3
/// converge without him.

// MARK: - Types

enum Ch09BeatKind {
    case settle(label: String)
    case carryForward
    case think(Ch01Cast, label: String)
    case forkCompose(versionId: String)        // composing one of the two conflicting messages
    case forkSeal(versionId: String)           // both forks now visible on Dave's lane
    case forkSend(versionId: String, to: Ch01Cast)
    case forkAccept(at: Ch01Cast, versionId: String)
    case gossipExchange(from: Ch01Cast, to: Ch01Cast)  // Aaron sends his ζ_a to Ben
    case forkDetected                          // "FORK DETECTED" badge
    case banDave                               // red X across Dave's forks + lane
    case convergeWithoutDave                   // honest 3 converge, Dave's weight wasted
    case thresholdBar                          // f<n/3 visualization
}

struct Ch09Beat: Identifiable {
    let id: String
    let kind: Ch09BeatKind
    let durationSeconds: Double
    let narration: String
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

struct Ch09WorldState {
    /// Honest-cast tower contents — carry-forward from Ch03's converged
    /// state {α, β, γ, δ, ε}, plus whatever Dave-fork they accepted.
    var views: [Ch01Cast: [String]] = [:]
    /// Both fork versions: ζ_a and ζ_b. Once a `forkSeal` beat fires,
    /// the corresponding version is in `forksOnDaveLane`.
    var forksOnDaveLane: [String] = []
    /// Composing animation for the current fork being written.
    var composing: Ch09Composing? = nil
    /// In-flight fork envelope, if active.
    var inFlight: Ch09Flight? = nil
    /// "FORK DETECTED" overlay opacity 0..1.
    var forkDetectedAlpha: Double = 0
    /// Once Dave's vertices are banned, this flag flips.
    var daveBanned: Bool = false
    /// The threshold bar (f<n/3) appears in scene 1.
    var thresholdBarAlpha: Double = 0
    /// Convergence flag — show "AARON · BEN · CARL CONVERGE" badge.
    var convergedAlpha: Double = 0
    /// Thought bubble.
    var thought: Ch09Thought? = nil
    var activeBeat: Ch09Beat? = nil
    var activeProgress: Double = 0

    struct Ch09Composing {
        let versionId: String
        var sealed: Bool
    }
    struct Ch09Flight {
        let versionId: String
        let from: Ch01Cast
        let to: Ch01Cast
        let progress: Double
    }
    struct Ch09Thought {
        let cast: Ch01Cast
        let label: String
    }
}

// MARK: - Timeline

enum Ch09Timeline {
    /// Two conflicting fork versions Dave writes.
    static let forkVersions: [String: (label: String, claim: String, hashShort: String)] = [
        "ζ_a": ("ζ_a", "claims: send 50 BTC to Aaron", "f1aa"),
        "ζ_b": ("ζ_b", "claims: send 50 BTC to Charlie", "f1bb"),
    ]

    static let beats: [Ch09Beat] = {
        let raw: [Ch09Beat] = [
            .init(id: "carry-forward", kind: .carryForward, durationSeconds: 4.0,
                  narration: "By now Aaron, Ben, Carl and Dave all hold the same converged set of messages from earlier chapters. The graph has been clean. But what if a player tries to lie?"),

            .init(id: "dave-thinks", kind: .think(.dave, label: "I'll send different things to different people."),
                  durationSeconds: 4.5,
                  narration: "Dave decides to attack. He'll write TWO messages with the SAME identity — same author, same parent set — but different content. He'll send one to Aaron and the other to Ben. If they trust him, they'll disagree about what Dave actually said."),

            // Compose ζ_a
            .init(id: "compose-zeta-a", kind: .forkCompose(versionId: "ζ_a"),
                  durationSeconds: 5.0,
                  narration: "First fork: ζ_a. Body: 'send 50 BTC to Aaron'. Parents: ε. Hash: f1aa."),
            .init(id: "seal-zeta-a", kind: .forkSeal(versionId: "ζ_a"),
                  durationSeconds: 3.0,
                  narration: "ζ_a is sealed. A red-ringed vertex appears on Dave's lane — the ring is the visual cue that this vertex is part of a fork."),

            // Compose ζ_b
            .init(id: "compose-zeta-b", kind: .forkCompose(versionId: "ζ_b"),
                  durationSeconds: 5.0,
                  narration: "Second fork: ζ_b. SAME identity (Dave), SAME parent set (ε), but DIFFERENT body: 'send 50 BTC to Charlie'. Hash: f1bb. This is the lie."),
            .init(id: "seal-zeta-b", kind: .forkSeal(versionId: "ζ_b"),
                  durationSeconds: 3.5,
                  narration: "ζ_b is sealed. A SECOND red-ringed vertex appears on Dave's lane, right next to ζ_a. Now Dave has two contradictory messages with the same identity. Watch what he does next."),

            // Send ζ_a to Aaron, ζ_b to Ben
            .init(id: "send-zeta-a-aaron", kind: .forkSend(versionId: "ζ_a", to: .aaron),
                  durationSeconds: 6.0,
                  narration: "Dave sends ζ_a to Aaron — and only to Aaron."),
            .init(id: "aaron-accepts-zeta-a", kind: .forkAccept(at: .aaron, versionId: "ζ_a"),
                  durationSeconds: 3.0,
                  narration: "Aaron has no reason yet to suspect anything. ζ_a is signed by Dave, references a parent he knows, hashes correctly. Aaron accepts. His tower grows by ζ_a."),

            .init(id: "send-zeta-b-ben", kind: .forkSend(versionId: "ζ_b", to: .ben),
                  durationSeconds: 6.0,
                  narration: "Dave sends ζ_b to Ben — and only to Ben."),
            .init(id: "ben-accepts-zeta-b", kind: .forkAccept(at: .ben, versionId: "ζ_b"),
                  durationSeconds: 3.5,
                  narration: "Ben also has no reason to suspect. ζ_b is signed, parent matches, hash matches. Ben accepts ζ_b. Now Aaron and Ben hold DIFFERENT Dave-versions."),

            .init(id: "scene-0-end", kind: .settle(label: "Two stories from one liar"),
                  durationSeconds: 4.0,
                  narration: "Look at Aaron's tower — it has ζ_a. Ben's tower has ζ_b. Same author, different content. Dave has succeeded in splitting their views. For exactly this moment."),

            // Scene 1: gossip exchange → fork detected → ban → converge
            .init(id: "gossip-aaron-ben", kind: .gossipExchange(from: .aaron, to: .ben),
                  durationSeconds: 6.0,
                  narration: "Now Aaron and Ben gossip. Aaron forwards his copy of Dave's message — ζ_a — to Ben."),

            .init(id: "fork-detected", kind: .forkDetected,
                  durationSeconds: 5.5,
                  narration: "Ben already has ζ_b from Dave. Now ζ_a arrives from Aaron. SAME author, SAME parent, DIFFERENT content. Ben's verifier flags this immediately: a fork. No vote, no committee — just arithmetic on two signed messages."),

            .init(id: "threshold-bar", kind: .thresholdBar,
                  durationSeconds: 5.0,
                  narration: "How does Crisis tolerate this? f < n/3. One byzantine out of four is f=1, n=4. 3f = 3 < 4 = n. The protocol's safety threshold holds — Dave alone cannot break consensus."),

            .init(id: "ban-dave", kind: .banDave,
                  durationSeconds: 5.5,
                  narration: "Both Dave-vertices get banned — a red X across each. Total order routes around them. Dave's PoW weight is wasted. The honest validators continue without him."),

            .init(id: "converge", kind: .convergeWithoutDave,
                  durationSeconds: 6.0,
                  narration: "Aaron, Ben and Carl now agree. They're missing none of each other's messages. Dave's two forks are explicitly excluded. Convergence holds — even with a liar in the room."),

            .init(id: "outro", kind: .settle(label: "Crisis catches the liar"),
                  durationSeconds: 4.0,
                  narration: "That is Byzantine resilience under f < n/3. The system tolerates one liar; if more than a third of validators were byzantine, all bets are off. With one — exactly one — Crisis routes around them and converges anyway. Done."),
        ]

        var t: Double = 0
        var assigned: [Ch09Beat] = []
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

    static func activeBeat(at t: Double) -> Ch09Beat? {
        let clamped = max(0, min(t, totalDuration))
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    static func state(at t: Double) -> Ch09WorldState {
        var w = Ch09WorldState()
        // Carry-forward: every cast starts with {α, β, γ, δ, ε}.
        let initial = ["α", "β", "γ", "δ", "ε"]
        for cast in Ch01Cast.allCases {
            w.views[cast] = initial
        }

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
        _ beat: Ch09Beat, progress: Double, isActive: Bool,
        into w: inout Ch09WorldState
    ) {
        switch beat.kind {
        case .settle, .carryForward:
            break
        case .think(let cast, let label):
            if isActive { w.thought = .init(cast: cast, label: label) }
        case .forkCompose(let vid):
            if w.composing?.versionId != vid {
                w.composing = .init(versionId: vid, sealed: false)
            }
        case .forkSeal(let vid):
            if !w.forksOnDaveLane.contains(vid) {
                w.forksOnDaveLane.append(vid)
            }
            if !isActive { w.composing = nil }
            else { w.composing = .init(versionId: vid, sealed: true) }
        case .forkSend(let vid, let to):
            if isActive {
                w.inFlight = .init(versionId: vid, from: .dave,
                                    to: to, progress: progress)
            }
        case .forkAccept(let at, let vid):
            if !w.views[at, default: []].contains(vid) {
                w.views[at, default: []].append(vid)
            }
        case .gossipExchange(let from, let to):
            // Animate Aaron sending his ζ_a to Ben.
            if isActive {
                w.inFlight = .init(versionId: "ζ_a", from: from,
                                    to: to, progress: progress)
            } else {
                // Permanent: Ben now also has ζ_a (in addition to ζ_b).
                if !w.views[to, default: []].contains("ζ_a") {
                    w.views[to, default: []].append("ζ_a")
                }
            }
        case .forkDetected:
            w.forkDetectedAlpha = isActive ? progress : 1.0
        case .thresholdBar:
            w.thresholdBarAlpha = isActive ? progress : 1.0
        case .banDave:
            w.daveBanned = true
        case .convergeWithoutDave:
            w.convergedAlpha = isActive ? progress : 1.0
        }
    }
}

// MARK: - Scene mapping

enum Ch09Scenes {
    /// 2 scenes, total ~79.5s. Scene 0 = Dave creates the fork; Scene 1
    /// = detection + threshold + ban + convergence.
    static let sceneStarts: [Double] = [0, 47.5]
    static let sceneDurations: [Double] = [47.5, 32.0]

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
        return Ch09Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
