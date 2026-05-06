import SwiftUI

/// Hand-crafted gossip dramatization for Ch01 scene 3.
///
/// The user's brief: "extreme slow motion, players appearing in random ways,
/// message bodies being created and being filled line by line, and then sent
/// out and then they fly very slowly to some guy in the gossip network and
/// also to some other guy. Once the message arrives at a player, the
/// player's perspective bubble changes slowly during the reading."
///
/// The simulation snapshots can't deliver this — they're step-aligned and
/// gossip catches up too quickly. So this is a synthetic vignette: a fixed
/// list of `Beat`s that play out over ~30 seconds. At any local time t the
/// rendering computes:
///   - which messages each cast member has CREATED (knows about)
///   - which messages have ARRIVED at each cast member (their local view)
///   - which messages are IN FLIGHT and how far along the path
///
/// Every beat's timing is explicit so a future edit just changes the script.
struct GossipScript {

    /// Lifecycle of one staged message.
    struct ScriptedMessage: Hashable {
        let id: String                 // e.g. "α", "β", "γ"
        let author: CastRoleKey        // who created it
        let parents: [String]          // ids of referenced parents
        let payload: String            // human-readable label
        let hashShort: String          // 6-char hash to display
    }

    /// Reference cast members by stable key so the script doesn't drift if
    /// the live `Cast.aaron` etc. instance changes.
    enum CastRoleKey: String, Hashable, CaseIterable {
        case aaron, ben, carl, dave
        var role: CastRole {
            switch self {
            case .aaron: return Cast.aaron
            case .ben:   return Cast.ben
            case .carl:  return Cast.carl
            case .dave:  return Cast.dave
            }
        }
    }

    /// Discrete event types in the dramatization.
    enum BeatKind {
        /// Author starts physically writing the message body. Lasts
        /// `composeDuration` seconds; bytes/parent-hashes appear line by line.
        case compose(durationSeconds: Double)
        /// The message hash is finalized (PoW completed instantly — we don't
        /// dramatize the work itself, only its outcome).
        case sealHash
        /// Author dispatches the message to a target. Hop has its own
        /// `flightDuration` so simultaneous fan-out can use different
        /// arrival times.
        case send(to: CastRoleKey, flightDuration: Double)
        /// Recipient absorbs the message into their local view. Lasts
        /// `readDuration` seconds during which their bubble grows the entry.
        case receive(at: CastRoleKey, readDuration: Double)
    }

    struct Beat {
        let startTime: Double          // scene-local seconds
        let messageId: String
        let kind: BeatKind
    }

    let messages: [ScriptedMessage]
    let beats: [Beat]
    let totalDuration: Double

    // MARK: - Snapshot computation

    /// State of one cast member's local view at time t.
    /// `received[id] = absorptionProgress (0..1)`. A message is "fully read"
    /// when progress = 1.
    struct ViewState {
        var received: [String: Double] = [:]
    }

    /// State of one in-flight (sent but not yet received) message.
    struct InFlightMessage {
        let message: ScriptedMessage
        let from: CastRoleKey
        let to: CastRoleKey
        let progress: Double           // 0 = just sent, 1 = arrived
    }

    /// State of one composition-in-progress message.
    struct ComposingMessage {
        let message: ScriptedMessage
        let author: CastRoleKey
        let progress: Double           // 0..1, controls how many lines are filled
        let sealed: Bool
    }

    struct WorldState {
        var views: [CastRoleKey: ViewState] = [:]
        var inFlight: [InFlightMessage] = []
        var composing: [ComposingMessage] = []
        /// Messages that have been finalized + sealed (so their hash is known
        /// and can be referenced by later messages).
        var sealedMessages: Set<String> = []
        /// Highlight: the most recently completed beat — used to flash the
        /// receiver/composer briefly.
        var spotlight: (CastRoleKey, BeatKind)?
    }

    func state(at t: Double) -> WorldState {
        var w = WorldState()
        for key in CastRoleKey.allCases { w.views[key] = ViewState() }

        // For each beat, advance state.
        // We must process beats in order; a `receive` beat at time T only
        // updates the receiver's view if the corresponding `send` started
        // earlier (the script is responsible for that ordering).
        for beat in beats {
            let elapsed = t - beat.startTime
            switch beat.kind {
            case .compose(let dur):
                guard elapsed >= 0 else { continue }
                let progress = min(1.0, elapsed / dur)
                if progress < 1.0 {
                    if let msg = messages.first(where: { $0.id == beat.messageId }) {
                        w.composing.append(ComposingMessage(
                            message: msg, author: authorKey(of: beat),
                            progress: progress, sealed: false
                        ))
                        w.spotlight = (authorKey(of: beat), beat.kind)
                    }
                }
                // After composition completes, the message is "owned" by the
                // author but not yet sealed (sealing is its own beat).
            case .sealHash:
                if elapsed >= 0 {
                    w.sealedMessages.insert(beat.messageId)
                    // The author KNOWS their own message the moment it's
                    // sealed. Without this the author's view bubble shows
                    // "empty" while their message is in flight, which
                    // contradicts the lesson (the author is the first to
                    // know their own message).
                    if let msg = messages.first(where: { $0.id == beat.messageId }) {
                        w.views[msg.author]?.received[msg.id] = 1.0
                    }
                }
            case .send(let to, let dur):
                guard elapsed >= 0 else { continue }
                let progress = min(1.0, elapsed / dur)
                if let msg = messages.first(where: { $0.id == beat.messageId }) {
                    if progress < 1.0 {
                        w.inFlight.append(InFlightMessage(
                            message: msg, from: msg.author,
                            to: to, progress: progress
                        ))
                    }
                }
            case .receive(let at, let dur):
                guard elapsed >= 0 else { continue }
                let progress = min(1.0, elapsed / dur)
                w.views[at]?.received[beat.messageId] = progress
                if progress < 1.0 {
                    w.spotlight = (at, beat.kind)
                }
            }
        }
        return w
    }

    private func authorKey(of beat: Beat) -> CastRoleKey {
        messages.first(where: { $0.id == beat.messageId })?.author ?? .aaron
    }

    // MARK: - Default script

    /// The Ch01 scene-3 dramatization. Total ~28 seconds, designed to fit
    /// within an extended scene duration when localTime is unconstrained.
    /// Beats:
    ///   t= 0.5: Aaron starts composing α (3s)
    ///   t= 3.5: α sealed
    ///   t= 4.0: Aaron sends α to Ben (4s flight)
    ///   t= 4.0: Aaron sends α to Carl (5s flight)
    ///   t= 8.0: Ben receives α (1.5s read)
    ///   t= 9.0: Carl receives α (1.5s read)
    ///   t=10.5: Ben starts composing β (referencing α) (3s)
    ///   t=13.5: β sealed
    ///   t=14.0: Ben sends β to Aaron (3.5s flight)
    ///   t=14.0: Ben sends β to Carl (4s flight)
    ///   t=15.0: Carl starts composing γ (referencing α only — Carl has not
    ///           received β yet) (3s)
    ///   t=18.0: γ sealed
    ///   t=18.0: Aaron receives β (1.5s)
    ///   t=18.5: Carl sends γ to Aaron (3s flight)
    ///   t=18.5: Carl sends γ to Ben (3s flight)
    ///   t=18.0: Carl receives β (1.5s) — by this point Carl already sent γ
    ///           without referencing β; the asymmetry is the lesson
    ///   t=21.5: Aaron receives γ
    ///   t=21.5: Ben receives γ
    ///   t=23.5: All three views have {α, β, γ}
    static let ch01 = GossipScript(
        messages: [
            ScriptedMessage(id: "α", author: .aaron, parents: [],
                            payload: "step-1-aaron",
                            hashShort: "43f3"),
            ScriptedMessage(id: "β", author: .ben, parents: ["α"],
                            payload: "step-2-ben",
                            hashShort: "7638"),
            ScriptedMessage(id: "γ", author: .carl, parents: ["α"],
                            payload: "step-3-carl",
                            hashShort: "5ce9"),
        ],
        beats: [
            Beat(startTime: 0.5, messageId: "α", kind: .compose(durationSeconds: 3.0)),
            Beat(startTime: 3.5, messageId: "α", kind: .sealHash),
            Beat(startTime: 4.0, messageId: "α", kind: .send(to: .ben,  flightDuration: 4.0)),
            Beat(startTime: 4.0, messageId: "α", kind: .send(to: .carl, flightDuration: 5.0)),
            Beat(startTime: 8.0, messageId: "α", kind: .receive(at: .ben,  readDuration: 1.5)),
            Beat(startTime: 9.0, messageId: "α", kind: .receive(at: .carl, readDuration: 1.5)),
            Beat(startTime: 10.5, messageId: "β", kind: .compose(durationSeconds: 3.0)),
            Beat(startTime: 13.5, messageId: "β", kind: .sealHash),
            Beat(startTime: 14.0, messageId: "β", kind: .send(to: .aaron, flightDuration: 3.5)),
            Beat(startTime: 14.0, messageId: "β", kind: .send(to: .carl,  flightDuration: 4.0)),
            // Carl starts composing γ at 15s — only references α because β
            // hasn't arrived yet. This is the punch line of the chapter:
            // async means simultaneous-yet-different views.
            Beat(startTime: 15.0, messageId: "γ", kind: .compose(durationSeconds: 3.0)),
            Beat(startTime: 17.5, messageId: "β", kind: .receive(at: .aaron, readDuration: 1.5)),
            Beat(startTime: 18.0, messageId: "γ", kind: .sealHash),
            Beat(startTime: 18.0, messageId: "β", kind: .receive(at: .carl,  readDuration: 1.5)),
            Beat(startTime: 18.5, messageId: "γ", kind: .send(to: .aaron, flightDuration: 3.0)),
            Beat(startTime: 18.5, messageId: "γ", kind: .send(to: .ben,   flightDuration: 3.0)),
            Beat(startTime: 21.5, messageId: "γ", kind: .receive(at: .aaron, readDuration: 1.5)),
            Beat(startTime: 21.5, messageId: "γ", kind: .receive(at: .ben,   readDuration: 1.5)),
        ],
        totalDuration: 24.0
    )
}
