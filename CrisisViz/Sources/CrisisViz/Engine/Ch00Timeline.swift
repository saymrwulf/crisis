import SwiftUI

/// Ch00 — "Four friends. One ledger. No boss."
///
/// The opener. Same architectural pattern as `Ch01Timeline`: a strictly
/// serial sequence of beats, each with its own narration, rendered as a
/// pure function of timeline position `t`.
///
/// Pedagogical job:
///   1. Plant the cast on the stage (all four lanes appear in turn).
///   2. Establish "no central server, no boss".
///   3. Show that each player keeps their own log.
///   4. Foreshadow that one of them will lie (Dave gets a quiet
///      red-glow tell on his arrival).
///
/// The chapter ends with all four lanes visible. Ch01 will begin by
/// dimming Ben/Carl/Dave to focus on Aaron's first message — that's a
/// SOFT focus shift, not a hard cut.

// MARK: - Types (mirror the Ch01 vocabulary so a shared render kit
//                can take both later)

enum Ch00BeatKind {
    case title(text: String)            // big title fades in
    case introduce(Ch01Cast)            // a lane fades in with a cast portrait
    case settle(label: String)          // quiet beat
    case logsDiverge                    // each lane gets its own scribble of vertices
    case needAgreement                  // arrows from each lane converging
    case foreshadowDave                 // Dave's lane pulses red, ominous
}

struct Ch00Beat: Identifiable {
    let id: String
    let kind: Ch00BeatKind
    let durationSeconds: Double
    let narration: String
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

struct Ch00WorldState {
    var titleText: String? = nil
    var titleAlpha: Double = 0
    var introduced: Set<Ch01Cast> = []
    var divergeProgress: Double = 0      // 0..1, drives "logs diverge" scribble
    var convergeProgress: Double = 0     // 0..1, drives "they need to agree" arrows
    var daveOminous: Double = 0          // 0..1, red glow + warning text
    var activeBeat: Ch00Beat? = nil
    var activeProgress: Double = 0
    /// Per-cast tower contents — abstract preview blocks. During the
    /// `logsDiverge` beat each cast accumulates a few colored blocks in
    /// a DIFFERENT order, foreshadowing the asymmetry that becomes
    /// concrete in Ch01.
    var towerBlocks: [Ch01Cast: [Ch00TowerBlock]] = [:]
}

/// One block in a Ch00 perception tower — abstract, no real digest.
struct Ch00TowerBlock {
    let label: String
    /// Whose color the block carries (so each tower mixes colors,
    /// the way local logs in real Crisis would).
    let authorCast: Ch01Cast
}

// MARK: - Timeline

enum Ch00Timeline {
    static let beats: [Ch00Beat] = {
        let raw: [Ch00Beat] = [
            // Phase 1: Title
            .init(id: "title", kind: .title(text: "Four friends. One ledger. No boss."),
                  durationSeconds: 4.0,
                  narration: "Welcome. This app teaches Crisis — a consensus protocol for a small group of validators who must agree on history without a central authority. We start with the cast."),

            // Phase 2: Cast intros (one at a time, in lane order)
            .init(id: "intro-aaron", kind: .introduce(.aaron),
                  durationSeconds: 3.0,
                  narration: "Meet Aaron. He's the first validator. His lane is the top of the canvas — every message he writes will live on this horizontal lifeline."),

            .init(id: "intro-ben", kind: .introduce(.ben),
                  durationSeconds: 3.0,
                  narration: "Meet Ben. The second validator. Same idea: his lifeline is the next lane down. Each player has their own row."),

            .init(id: "intro-carl", kind: .introduce(.carl),
                  durationSeconds: 3.0,
                  narration: "Meet Carl. Third validator, third lane. Three honest players so far."),

            .init(id: "intro-dave", kind: .introduce(.dave),
                  durationSeconds: 3.5,
                  narration: "And Dave. Fourth validator, fourth lane. Watch this one — Dave will eventually try to lie. We'll spot him later."),

            .init(id: "all-four-settle", kind: .settle(label: "Four lifelines"),
                  durationSeconds: 3.5,
                  narration: "Four lanes, four lifelines. One per validator. The whole story of Crisis plays out as marks on these four lines."),

            // Phase 3 (scene 1): no boss, each keeps their own log
            .init(id: "no-boss", kind: .settle(label: "No boss"),
                  durationSeconds: 4.5,
                  narration: "There is no chairperson here. No central server, no boss who decides what happened first. Order has to emerge from the four of them talking to each other."),

            .init(id: "logs-diverge", kind: .logsDiverge,
                  durationSeconds: 6.0,
                  narration: "Each player keeps their own log — only what they have personally received. Because messages travel at different speeds, they can record the same events in different orders. Right now, four logs means four different stories."),

            // Phase 4 (scene 2): need agreement; foreshadow Dave
            .init(id: "need-agreement", kind: .needAgreement,
                  durationSeconds: 5.5,
                  narration: "Yet at the end of the day they all need to agree on ONE history — same events, same order, byte-for-byte. That's the problem Crisis solves."),

            .init(id: "foreshadow-dave", kind: .foreshadowDave,
                  durationSeconds: 5.0,
                  narration: "There is one more twist. One of these four — Dave — is going to try to lie. Crisis has to converge anyway. We'll see how, chapter by chapter."),

            .init(id: "let-us-begin", kind: .settle(label: "Let us begin"),
                  durationSeconds: 3.0,
                  narration: "Four friends. One ledger. No boss. Let's see how they pull it off."),
        ]

        var t: Double = 0
        var assigned: [Ch00Beat] = []
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

    static func activeBeat(at t: Double) -> Ch00Beat? {
        let clamped = max(0, min(t, totalDuration))
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    /// Pure-function world state at any timeline position.
    static func state(at t: Double) -> Ch00WorldState {
        var w = Ch00WorldState()
        let clamped = max(0, min(t, totalDuration))

        for beat in beats {
            if clamped < beat.startTime { break }
            let isActive = clamped < beat.endTime
            let progress = isActive
                ? max(0, min(1, (clamped - beat.startTime) / beat.durationSeconds))
                : 1.0

            switch beat.kind {
            case .title(let txt):
                if isActive {
                    w.titleText = txt
                    w.titleAlpha = progress
                } else {
                    // Title fades back out as soon as cast intros begin —
                    // it's an opener, not a permanent label.
                    w.titleText = nil
                }
            case .introduce(let cast):
                w.introduced.insert(cast)
            case .settle:
                break
            case .logsDiverge:
                w.divergeProgress = progress
                if !isActive { w.divergeProgress = 1 }
                // Populate each tower with a sequence of mixed-color
                // blocks in a DIFFERENT order per cast. The blocks
                // appear one at a time, paced over the beat's duration,
                // so the viewer can see each player's stack grow
                // independently — same population, different histories.
                let perTowerOrders: [Ch01Cast: [Ch00TowerBlock]] = [
                    .aaron: [
                        .init(label: "tx-1", authorCast: .aaron),
                        .init(label: "tx-2", authorCast: .ben),
                        .init(label: "tx-3", authorCast: .carl),
                    ],
                    .ben: [
                        .init(label: "tx-2", authorCast: .ben),
                        .init(label: "tx-1", authorCast: .aaron),
                        .init(label: "tx-3", authorCast: .carl),
                    ],
                    .carl: [
                        .init(label: "tx-3", authorCast: .carl),
                        .init(label: "tx-2", authorCast: .ben),
                        .init(label: "tx-1", authorCast: .aaron),
                    ],
                    .dave: [
                        .init(label: "tx-4", authorCast: .dave),
                        .init(label: "tx-1", authorCast: .aaron),
                    ],
                ]
                let perTowerProgress = isActive ? progress : 1.0
                for (cast, blocks) in perTowerOrders {
                    let revealed = Int(Double(blocks.count) * perTowerProgress)
                    w.towerBlocks[cast] = Array(blocks.prefix(revealed))
                }
            case .needAgreement:
                w.convergeProgress = progress
                if !isActive { w.convergeProgress = 1 }
            case .foreshadowDave:
                w.daveOminous = progress
                if !isActive { w.daveOminous = 1 }
            }

            if isActive {
                w.activeBeat = beat
                w.activeProgress = progress
            }
        }
        return w
    }
}

// MARK: - Scene mapping

/// Ch00 has 3 scenes mapping to windows of the unified timeline.
enum Ch00Scenes {
    static let sceneStarts: [Double] = [0, 16.0, 30.0]
    static let sceneDurations: [Double] = [16.0, 14.0, 13.5]

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
        return Ch00Timeline.activeBeat(at: t)?.narration ?? ""
    }
}
