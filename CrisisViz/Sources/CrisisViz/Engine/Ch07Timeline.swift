import SwiftUI

/// Ch07 — "The leader knows. Did the leader tell anyone?" (Data availability problem.)
///
/// Aaron, as leader, produces a new message ξ that carries a large
/// payload (a "blob"). He sends out only ξ's hash — not the body.
/// Ben and Carl receive ξ as a hash, but they can't access the body.
/// They ask Aaron for it; Aaron doesn't respond. The system is stuck.
/// This is the data-availability problem; Ch08 introduces erasure
/// coding as the fix.

enum Ch07BeatKind {
    case settle(label: String)
    case carryForward
    case composeXi             // Aaron composes ξ with a heavy blob
    case sealXi                // ξ sealed; body sits in Aaron's vault
    case sendHashOnly(to: Ch01Cast)   // hash-only envelope flies
    case markBodyMissing(at: Ch01Cast) // ⚠ BODY MISSING on recipient's ξ
    case askForBody(asker: Ch01Cast)   // request arrow from asker to Aaron
    case aaronSilent(asker: Ch01Cast)  // request times out (red ✗)
    case stuckBadge                     // "DA PROBLEM" banner
}

struct Ch07Beat: Identifiable {
    let id: String
    let kind: Ch07BeatKind
    let durationSeconds: Double
    let narration: String
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

struct Ch07WorldState {
    var xiComposed: Bool = false
    var xiSealed: Bool = false
    var xiBodyInAaronVault: Bool = false      // permanent once sealed
    var xiInView: Set<Ch01Cast> = []          // Ben / Carl receive the HASH only
    var bodyMissingAt: Set<Ch01Cast> = []     // ⚠ flag on Ben / Carl
    var hashFlight: HashFlight? = nil
    var askArrow: AskArrow? = nil
    var timeoutFlash: Ch01Cast? = nil
    var stuckAlpha: Double = 0
    var activeBeat: Ch07Beat? = nil
    var activeProgress: Double = 0

    struct HashFlight {
        let to: Ch01Cast
        let progress: Double
    }
    struct AskArrow {
        let asker: Ch01Cast
        let progress: Double
        let willTimeout: Bool
    }
}

enum Ch07Timeline {
    static let beats: [Ch07Beat] = {
        let raw: [Ch07Beat] = [
            .init(id: "carry-forward", kind: .carryForward, durationSeconds: 4.0,
                  narration: "Coming out of Ch06 with the total order in hand. Now Aaron, as round leader, is about to produce a NEW message — call it ξ. ξ carries a large payload, a 'blob'. What happens when only the leader has the body?"),

            .init(id: "compose-xi", kind: .composeXi, durationSeconds: 6.0,
                  narration: "Aaron composes ξ. Payload is heavy — let's say a megabyte of transaction data. The body sits in Aaron's local vault on the right side of the canvas."),

            .init(id: "seal-xi", kind: .sealXi, durationSeconds: 3.5,
                  narration: "ξ is sealed. Aaron now holds the body locally and can compute the hash."),

            .init(id: "vault-settle", kind: .settle(label: "Aaron's vault"),
                  durationSeconds: 4.0,
                  narration: "Look at the vault on the right: ξ's body lives there, in Aaron's storage. Other validators do not have it. The hash is small; the body is large."),

            // Phase 2: send hash only
            .init(id: "hash-to-ben", kind: .sendHashOnly(to: .ben), durationSeconds: 5.0,
                  narration: "Aaron sends just the HASH of ξ to Ben — a small envelope, no body inside. Bandwidth-cheap. But it carries a problem with it."),
            .init(id: "ben-body-missing", kind: .markBodyMissing(at: .ben),
                  durationSeconds: 5.0,
                  narration: "Ben receives ξ's hash. He knows ξ exists. He cannot verify or use it without the body. A ⚠ BODY MISSING flag appears on Ben's copy of ξ."),
            .init(id: "hash-to-carl", kind: .sendHashOnly(to: .carl), durationSeconds: 5.0,
                  narration: "Aaron sends ξ's hash to Carl, also without the body."),
            .init(id: "carl-body-missing", kind: .markBodyMissing(at: .carl),
                  durationSeconds: 5.0,
                  narration: "Carl also has ξ's hash with no body. Same ⚠ flag. The problem is now on two lanes."),

            // Phase 3: requests + silence
            .init(id: "ben-asks", kind: .askForBody(asker: .ben), durationSeconds: 5.0,
                  narration: "Ben asks Aaron: 'Send me ξ's body.' A request arrow shoots from Ben's lane to Aaron's."),
            .init(id: "aaron-silent-ben", kind: .aaronSilent(asker: .ben),
                  durationSeconds: 5.5,
                  narration: "Aaron does not respond. Maybe he's offline. Maybe he's malicious. Maybe he's overwhelmed. Regardless: Ben's request times out with a red ✗. The protocol cannot force Aaron to share."),
            .init(id: "carl-asks", kind: .askForBody(asker: .carl), durationSeconds: 5.0,
                  narration: "Carl asks Aaron next."),
            .init(id: "aaron-silent-carl", kind: .aaronSilent(asker: .carl),
                  durationSeconds: 5.5,
                  narration: "Same outcome. Silence. Carl's request also times out."),

            // Phase 4: stuck
            .init(id: "stuck", kind: .stuckBadge, durationSeconds: 6.0,
                  narration: "DA PROBLEM. ξ is committed to the ledger — its hash is referenced — but its body is unavailable. Without the body, Ben and Carl cannot verify, cannot use, cannot replay. The chain is alive but the data behind it isn't."),

            .init(id: "outro", kind: .settle(label: "Need a fix"),
                  durationSeconds: 4.0,
                  narration: "Crisis needs a way to make data un-loseable, even if the leader stays silent. That fix — erasure coding distributed across storage nodes — is the next chapter."),
        ]
        var t: Double = 0
        var assigned: [Ch07Beat] = []
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

    static func activeBeat(at t: Double) -> Ch07Beat? {
        let clamped = max(0, min(t, totalDuration))
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    static func state(at t: Double) -> Ch07WorldState {
        var w = Ch07WorldState()
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
        _ beat: Ch07Beat, progress: Double, isActive: Bool,
        into w: inout Ch07WorldState
    ) {
        switch beat.kind {
        case .settle, .carryForward:
            break
        case .composeXi:
            w.xiComposed = true
        case .sealXi:
            w.xiSealed = true
            w.xiBodyInAaronVault = true
        case .sendHashOnly(let to):
            if isActive {
                w.hashFlight = .init(to: to, progress: progress)
            }
            // Permanent: recipient now has ξ's hash in their view.
            w.xiInView.insert(to)
        case .markBodyMissing(let at):
            w.bodyMissingAt.insert(at)
        case .askForBody(let asker):
            if isActive {
                w.askArrow = .init(asker: asker, progress: progress, willTimeout: true)
            }
        case .aaronSilent(let asker):
            if isActive {
                w.timeoutFlash = asker
            }
        case .stuckBadge:
            w.stuckAlpha = isActive ? progress : 1.0
        }
    }
}

enum Ch07Scenes {
    /// 4 scenes mapping to ~74s of timeline at 1×.
    static let sceneStarts: [Double] = [0, 17.5, 37.5, 58.5]
    static let sceneDurations: [Double] = [17.5, 20.0, 21.0, 10.0]

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
        return Ch07Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
