import SwiftUI

/// Ch01 unified serial timeline.
///
/// Replaces the old `GossipScript` (which had parallel beats — α flying to
/// Ben and Carl simultaneously). The pedagogical principle the user
/// articulated: even though Crisis is parallel by design, the LEARNER's
/// eye can only follow serial events. So this timeline strictly serializes
/// every micro-event:
///
///   compose → seal → choose recipient → flight (one at a time) →
///   arrive → open → read body → read parents → resolve each parent
///   recursively → verify hash → accept into local view
///
/// Every beat is a deterministic function of timeline position `t`. State
/// at any `t` is whatever you'd get by replaying every beat up to `t`. This
/// makes the timeline scrub-able and reverse-playable cleanly.
///
/// The chapter's 7 scenes are now just navigation labels — windows of
/// the same continuous timeline. The actual rendering reads `t` and
/// produces state. Narration is bound to the *currently active beat*, not
/// to scenes.

// MARK: - Types

enum Ch01Cast: String, Hashable, CaseIterable {
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

struct Ch01Message: Hashable {
    let id: String         // "α", "β", "γ"
    let author: Ch01Cast
    let payload: String
    let parents: [String]
    let hashShort: String  // e.g. "43f3"
}

enum Ch01BeatKind {
    /// A cast member fades onto the stage for the first time. Until this
    /// beat fires, that cast's lane is invisible — they don't yet exist
    /// in the story.
    case introduce(Ch01Cast)
    /// Author looks inward and decides what to do next. Renders as a
    /// thought bubble above the cast circle.
    case think(Ch01Cast, label: String)
    /// Author writes the payload. Composing slot fills the body line.
    case selectPayload(messageId: String)
    /// Author selects parent references. Composing slot reveals the
    /// parents line; in the cast's view, the parent vertices pulse.
    case selectParents(messageId: String)
    /// Author grinds proof-of-work. Composing slot shows a spinner /
    /// "computing PoW…" line. This is intentionally long — PoW is the
    /// real bottleneck in Crisis.
    case computePoW(messageId: String)
    /// Hash is now sealed. Composing slot shows the hash line filled in
    /// and a small lock icon. The author's view permanently gains the
    /// message.
    case seal(messageId: String)
    /// Author chooses a recipient. An arrow points from author to that
    /// recipient (and the recipient's lane fades in if not already on
    /// stage).
    case decideSend(from: Ch01Cast, to: Ch01Cast, messageId: String)
    /// Envelope physically flies from sender to recipient over the
    /// beat's duration.
    case fly(from: Ch01Cast, to: Ch01Cast, messageId: String)
    /// Envelope arrives at the recipient — small flash, then settles
    /// against the recipient's lane.
    case arrive(at: Ch01Cast, messageId: String)
    /// Recipient opens the envelope (animation: envelope unfolds into
    /// the body card).
    case open(at: Ch01Cast, messageId: String)
    /// Body lines reveal one by one inside the recipient's view bubble.
    case readBody(at: Ch01Cast, messageId: String)
    /// Recipient sees the parents list. Highlight: parents line glows.
    case readParents(at: Ch01Cast, messageId: String)
    /// Recipient resolves a single parent reference by looking it up in
    /// their own local view. Animation: connector line from the
    /// just-arrived envelope's parents-line to the matching vertex in
    /// the recipient's view.
    case resolveParent(at: Ch01Cast, messageId: String, parentId: String)
    /// Recipient hashes the body and confirms it equals the envelope's
    /// claimed hash. Animation: SHA arrow body→hash, ✓.
    case verifyHash(at: Ch01Cast, messageId: String)
    /// Recipient permanently accepts the message into their local view.
    /// Their view bubble grows by one row.
    case acceptIntoView(at: Ch01Cast, messageId: String)
    /// Quiet beat — no new event, just give the eye time to settle.
    case settle(label: String)
}

struct Ch01Beat: Identifiable {
    let id: String
    let kind: Ch01BeatKind
    let durationSeconds: Double
    /// Narration bound to this beat. The GlassNarration overlay shows
    /// this exact text whenever the timeline cursor is inside the beat.
    let narration: String
    /// Cumulative start time, computed once at timeline-build time.
    var startTime: Double = 0
    var endTime: Double { startTime + durationSeconds }
}

// MARK: - World state

/// Snapshot of the dramatized world at one moment in time. Pure function
/// of the timeline `t` — replaying beats up to `t` produces this.
struct Ch01WorldState {
    /// Cast members currently on the stage. Lanes for cast NOT in this
    /// set are invisible.
    var introduced: Set<Ch01Cast> = []
    /// Messages whose seal beat has fired (so their hash exists).
    var sealedMessages: Set<String> = []
    /// Each cast member's local view: messages they have fully accepted.
    var views: [Ch01Cast: Set<String>] = [:]
    /// What the active recipient has read of the just-arrived envelope —
    /// payload (if .readBody fired), parents list (if .readParents
    /// fired), each individual resolved parent.
    var openEnvelope: OpenEnvelopeState? = nil
    /// In-flight envelope animation, if active.
    var inFlight: InFlightState? = nil
    /// Composing animation, if active.
    var composing: ComposingState? = nil
    /// "Send decision" arrow from sender to recipient, if active.
    var decideArrow: DecideArrowState? = nil
    /// Thought bubble above a cast member, if active.
    var thought: ThoughtState? = nil
    /// The currently active beat plus its progress 0..1. Drives the
    /// "spotlight" effect on whichever cast member is the focus.
    var activeBeat: Ch01Beat? = nil
    var activeProgress: Double = 0

    struct OpenEnvelopeState {
        let recipient: Ch01Cast
        let messageId: String
        var bodyRevealed: Bool = false
        var parentsRevealed: Bool = false
        var resolvedParents: Set<String> = []
        var verified: Bool = false
    }
    struct InFlightState {
        let messageId: String
        let from: Ch01Cast
        let to: Ch01Cast
        let progress: Double  // 0..1
    }
    struct ComposingState {
        let messageId: String
        let author: Ch01Cast
        var payloadFilled: Bool = false
        var parentsFilled: Bool = false
        var powProgress: Double = 0
        var sealed: Bool = false
    }
    struct DecideArrowState {
        let from: Ch01Cast
        let to: Ch01Cast
        let messageId: String
    }
    struct ThoughtState {
        let cast: Ch01Cast
        let label: String
    }
}

// MARK: - Timeline

enum Ch01Timeline {
    /// The three messages in Ch01.
    static let messages: [String: Ch01Message] = [
        "α": Ch01Message(id: "α", author: .aaron, payload: "step-1-aaron",
                          parents: [], hashShort: "43f3"),
        "β": Ch01Message(id: "β", author: .ben, payload: "step-2-ben",
                          parents: ["α"], hashShort: "7638"),
        "γ": Ch01Message(id: "γ", author: .carl, payload: "step-3-carl",
                          parents: ["α"], hashShort: "5ce9"),
        // Note: γ's parents = [α] only (NOT [α, β]). This is the
        // asymmetry beat — Carl wrote γ before β arrived at him.
    ]

    /// Build the beat list with cumulative startTimes filled in. Heavy
    /// pedagogical pacing: long PoW beats, slow flights, distinct
    /// thinking beats, every parent reference resolved one at a time.
    static let beats: [Ch01Beat] = {
        let raw: [Ch01Beat] = [
            // ────────── Phase 1: Aaron writes α ──────────
            .init(id: "intro-aaron", kind: .introduce(.aaron), durationSeconds: 4.0,
                  narration: "Meet Aaron. He's one of four validators who will eventually share a single ordered history. Right now he's alone on stage."),
            .init(id: "aaron-thinks-write", kind: .think(.aaron, label: "Time to write."), durationSeconds: 4.0,
                  narration: "Aaron decides to write the very first message. There is no global clock — he just chooses to start now."),
            .init(id: "aaron-payload", kind: .selectPayload(messageId: "α"), durationSeconds: 4.0,
                  narration: "First, Aaron picks his payload — the body of the message. He writes 'step-1-aaron'."),
            .init(id: "aaron-parents", kind: .selectParents(messageId: "α"), durationSeconds: 3.5,
                  narration: "Next, Aaron lists parent messages. He references nothing — α is the genesis, the first message ever."),
            .init(id: "aaron-pow", kind: .computePoW(messageId: "α"), durationSeconds: 9.0,
                  narration: "Aaron grinds proof-of-work. He hashes the message header with successive nonces until the hash starts with enough zeros. This is the real cost of producing a message in Crisis."),
            .init(id: "aaron-seal", kind: .seal(messageId: "α"), durationSeconds: 3.5,
                  narration: "Done. The valid hash is 43f3…. From this moment on, the message's name IS its hash. α is sealed."),
            .init(id: "aaron-knows-alpha", kind: .acceptIntoView(at: .aaron, messageId: "α"), durationSeconds: 3.0,
                  narration: "Aaron's local view now contains α — the first vertex on his lifeline."),

            // ────────── Phase 2: Aaron sends α to Ben ──────────
            .init(id: "intro-ben", kind: .introduce(.ben), durationSeconds: 3.5,
                  narration: "Meet Ben — Aaron's first recipient. He fades in on his own lane, ready to listen."),
            .init(id: "aaron-decides-ben", kind: .decideSend(from: .aaron, to: .ben, messageId: "α"), durationSeconds: 3.5,
                  narration: "Aaron decides to send α to Ben first. A choice arrow appears from Aaron's lane toward Ben's."),
            .init(id: "alpha-flies-to-ben", kind: .fly(from: .aaron, to: .ben, messageId: "α"), durationSeconds: 11.0,
                  narration: "α travels through the gossip network. Slow motion: this is the only time-and-distance the protocol cares about."),
            .init(id: "alpha-arrives-ben", kind: .arrive(at: .ben, messageId: "α"), durationSeconds: 2.5,
                  narration: "The envelope reaches Ben's lane. He sees something has arrived — but he hasn't opened it yet."),
            .init(id: "ben-opens-alpha", kind: .open(at: .ben, messageId: "α"), durationSeconds: 3.0,
                  narration: "Ben opens the envelope. The body and metadata become visible to him."),
            .init(id: "ben-reads-body-alpha", kind: .readBody(at: .ben, messageId: "α"), durationSeconds: 4.0,
                  narration: "Ben reads the body line by line: 'step-1-aaron'. This is what Aaron actually said."),
            .init(id: "ben-reads-parents-alpha", kind: .readParents(at: .ben, messageId: "α"), durationSeconds: 3.0,
                  narration: "Ben reads the parents list: empty. So α is a genesis message — no prior context to resolve."),
            .init(id: "ben-verifies-alpha", kind: .verifyHash(at: .ben, messageId: "α"), durationSeconds: 4.5,
                  narration: "Ben hashes the body himself and gets 43f3…. It matches the envelope's claimed hash. The message is authentic. ✓"),
            .init(id: "ben-accepts-alpha", kind: .acceptIntoView(at: .ben, messageId: "α"), durationSeconds: 3.0,
                  narration: "Ben accepts α into his local view. His lifeline now carries α as well: {α}."),

            // ────────── Phase 3: Aaron sends α to Carl ──────────
            .init(id: "intro-carl", kind: .introduce(.carl), durationSeconds: 3.5,
                  narration: "Meet Carl. He fades in on his lane — Aaron is about to send α to him too."),
            .init(id: "aaron-decides-carl", kind: .decideSend(from: .aaron, to: .carl, messageId: "α"), durationSeconds: 3.5,
                  narration: "Aaron now decides to send α to Carl as well. This is the SECOND copy of α — in real Crisis it would fan out simultaneously, but we serialize for clarity."),
            .init(id: "alpha-flies-to-carl", kind: .fly(from: .aaron, to: .carl, messageId: "α"), durationSeconds: 11.0,
                  narration: "α travels to Carl. Different path, possibly different speed — but the same content."),
            .init(id: "alpha-arrives-carl", kind: .arrive(at: .carl, messageId: "α"), durationSeconds: 2.5,
                  narration: "The envelope reaches Carl."),
            .init(id: "carl-opens-alpha", kind: .open(at: .carl, messageId: "α"), durationSeconds: 3.0,
                  narration: "Carl opens it."),
            .init(id: "carl-reads-body-alpha", kind: .readBody(at: .carl, messageId: "α"), durationSeconds: 4.0,
                  narration: "Carl reads the body. Same payload Ben saw: 'step-1-aaron'."),
            .init(id: "carl-reads-parents-alpha", kind: .readParents(at: .carl, messageId: "α"), durationSeconds: 3.0,
                  narration: "Carl reads parents: empty. Same as for Ben."),
            .init(id: "carl-verifies-alpha", kind: .verifyHash(at: .carl, messageId: "α"), durationSeconds: 4.5,
                  narration: "Carl recomputes the hash, matches 43f3…. ✓"),
            .init(id: "carl-accepts-alpha", kind: .acceptIntoView(at: .carl, messageId: "α"), durationSeconds: 3.0,
                  narration: "Carl accepts α. His view: {α}. Three players now share α."),

            // ────────── Phase 4: Ben writes β (referencing α) ──────────
            .init(id: "ben-thinks-write", kind: .think(.ben, label: "I should respond."), durationSeconds: 4.0,
                  narration: "Now Ben decides to write his own message. He has α in his local view, so β can reference it."),
            .init(id: "ben-payload", kind: .selectPayload(messageId: "β"), durationSeconds: 4.0,
                  narration: "Ben picks his payload: 'step-2-ben'."),
            .init(id: "ben-parents", kind: .selectParents(messageId: "β"), durationSeconds: 4.5,
                  narration: "Ben picks parents: α — he saw α before he started writing, so he embeds α's hash in β. This is what 'I saw your message before I spoke' looks like in code."),
            .init(id: "ben-pow", kind: .computePoW(messageId: "β"), durationSeconds: 9.0,
                  narration: "Ben grinds proof-of-work for β. Same cost as Aaron paid for α."),
            .init(id: "ben-seal", kind: .seal(messageId: "β"), durationSeconds: 3.5,
                  narration: "β is sealed. Hash: 7638…."),
            .init(id: "ben-knows-beta", kind: .acceptIntoView(at: .ben, messageId: "β"), durationSeconds: 3.0,
                  narration: "Ben's local view: {α, β}. Two vertices on his lifeline."),

            // ────────── Phase 5: Ben sends β to Aaron — RESOLVE PARENT ──────────
            .init(id: "ben-decides-aaron", kind: .decideSend(from: .ben, to: .aaron, messageId: "β"), durationSeconds: 3.5,
                  narration: "Ben sends β back to Aaron first."),
            .init(id: "beta-flies-to-aaron", kind: .fly(from: .ben, to: .aaron, messageId: "β"), durationSeconds: 11.0,
                  narration: "β travels."),
            .init(id: "beta-arrives-aaron", kind: .arrive(at: .aaron, messageId: "β"), durationSeconds: 2.5,
                  narration: "Aaron receives the envelope."),
            .init(id: "aaron-opens-beta", kind: .open(at: .aaron, messageId: "β"), durationSeconds: 3.0,
                  narration: "Aaron opens β."),
            .init(id: "aaron-reads-body-beta", kind: .readBody(at: .aaron, messageId: "β"), durationSeconds: 4.0,
                  narration: "He reads the body: 'step-2-ben'. So Ben said something."),
            .init(id: "aaron-reads-parents-beta", kind: .readParents(at: .aaron, messageId: "β"), durationSeconds: 3.5,
                  narration: "He reads parents: α. So β refers to a message named α."),
            .init(id: "aaron-resolves-alpha-from-beta", kind: .resolveParent(at: .aaron, messageId: "β", parentId: "α"), durationSeconds: 5.0,
                  narration: "Aaron looks up α in his own local view. Yes — he already has α. (It's his own message. He wrote it.) The reference resolves cleanly. ✓"),
            .init(id: "aaron-verifies-beta", kind: .verifyHash(at: .aaron, messageId: "β"), durationSeconds: 4.0,
                  narration: "Aaron hashes β's body, gets 7638…. Matches. ✓"),
            .init(id: "aaron-accepts-beta", kind: .acceptIntoView(at: .aaron, messageId: "β"), durationSeconds: 3.0,
                  narration: "Aaron accepts β. His view: {α, β}."),

            // ────────── Phase 6: Carl writes γ — THE ASYMMETRY BEAT ──────────
            .init(id: "asymmetry-pause", kind: .settle(label: "Crucial moment ahead"), durationSeconds: 3.5,
                  narration: "PAY ATTENTION. The next beat is the lesson of this chapter. Carl is about to write his own message — but β has not yet reached him."),
            .init(id: "carl-thinks-write", kind: .think(.carl, label: "I have α; let me write."), durationSeconds: 4.5,
                  narration: "Carl decides to write γ. At this moment his local view contains only α — β is still in flight in the background of the story (we'll get to it)."),
            .init(id: "carl-payload", kind: .selectPayload(messageId: "γ"), durationSeconds: 4.0,
                  narration: "Carl picks his payload: 'step-3-carl'."),
            .init(id: "carl-parents", kind: .selectParents(messageId: "γ"), durationSeconds: 5.5,
                  narration: "Carl picks parents from HIS local view. He has only α. So γ references just α — NOT β. This is the asymmetry: γ does not depend on β. Different validators see different worlds at the moment they speak."),
            .init(id: "carl-pow", kind: .computePoW(messageId: "γ"), durationSeconds: 9.0,
                  narration: "Carl grinds proof-of-work for γ."),
            .init(id: "carl-seal", kind: .seal(messageId: "γ"), durationSeconds: 3.5,
                  narration: "γ is sealed. Hash: 5ce9…."),
            .init(id: "carl-knows-gamma", kind: .acceptIntoView(at: .carl, messageId: "γ"), durationSeconds: 3.0,
                  narration: "Carl's local view: {α, γ}. Notice — he STILL doesn't have β."),

            // ────────── Phase 7: Carl sends γ to Aaron ──────────
            .init(id: "carl-decides-aaron", kind: .decideSend(from: .carl, to: .aaron, messageId: "γ"), durationSeconds: 3.5,
                  narration: "Carl sends γ to Aaron."),
            .init(id: "gamma-flies-to-aaron", kind: .fly(from: .carl, to: .aaron, messageId: "γ"), durationSeconds: 10.0,
                  narration: "γ travels to Aaron."),
            .init(id: "gamma-arrives-aaron", kind: .arrive(at: .aaron, messageId: "γ"), durationSeconds: 2.5,
                  narration: "Aaron receives γ."),
            .init(id: "aaron-opens-gamma", kind: .open(at: .aaron, messageId: "γ"), durationSeconds: 3.0,
                  narration: "Aaron opens γ."),
            .init(id: "aaron-reads-body-gamma", kind: .readBody(at: .aaron, messageId: "γ"), durationSeconds: 3.5,
                  narration: "He reads body: 'step-3-carl'."),
            .init(id: "aaron-reads-parents-gamma", kind: .readParents(at: .aaron, messageId: "γ"), durationSeconds: 3.5,
                  narration: "He reads parents: α (only). Notice — γ does NOT mention β. Aaron now sees evidence of the asymmetry: Carl wrote γ before β reached him."),
            .init(id: "aaron-resolves-alpha-from-gamma", kind: .resolveParent(at: .aaron, messageId: "γ", parentId: "α"), durationSeconds: 4.5,
                  narration: "Aaron resolves the α reference in his local view. ✓"),
            .init(id: "aaron-verifies-gamma", kind: .verifyHash(at: .aaron, messageId: "γ"), durationSeconds: 3.5,
                  narration: "Hash check: 5ce9…. Matches. ✓"),
            .init(id: "aaron-accepts-gamma", kind: .acceptIntoView(at: .aaron, messageId: "γ"), durationSeconds: 3.0,
                  narration: "Aaron's local view: {α, β, γ}. He's the first to hold all three."),

            // ────────── Phase 8: Ben sends β to Carl (closes the asymmetry gap) ──────────
            .init(id: "ben-decides-carl", kind: .decideSend(from: .ben, to: .carl, messageId: "β"), durationSeconds: 3.5,
                  narration: "Ben now sends β to Carl. By the time it gets there, Carl has already written γ — but β is still useful to him."),
            .init(id: "beta-flies-to-carl", kind: .fly(from: .ben, to: .carl, messageId: "β"), durationSeconds: 11.0,
                  narration: "β travels to Carl."),
            .init(id: "beta-arrives-carl", kind: .arrive(at: .carl, messageId: "β"), durationSeconds: 2.5,
                  narration: "Carl receives β — finally."),
            .init(id: "carl-opens-beta", kind: .open(at: .carl, messageId: "β"), durationSeconds: 3.0,
                  narration: "Carl opens β."),
            .init(id: "carl-reads-body-beta", kind: .readBody(at: .carl, messageId: "β"), durationSeconds: 3.5,
                  narration: "Reads body: 'step-2-ben'."),
            .init(id: "carl-reads-parents-beta", kind: .readParents(at: .carl, messageId: "β"), durationSeconds: 3.5,
                  narration: "Reads parents: α."),
            .init(id: "carl-resolves-alpha-from-beta", kind: .resolveParent(at: .carl, messageId: "β", parentId: "α"), durationSeconds: 4.0,
                  narration: "Carl resolves α in his local view. ✓"),
            .init(id: "carl-verifies-beta", kind: .verifyHash(at: .carl, messageId: "β"), durationSeconds: 3.5,
                  narration: "Hash: 7638…. Matches. ✓"),
            .init(id: "carl-accepts-beta", kind: .acceptIntoView(at: .carl, messageId: "β"), durationSeconds: 3.0,
                  narration: "Carl's local view: {α, β, γ}. He has all three now — even though γ doesn't reference β. The DAG records what Carl actually KNEW when he spoke, not what was true elsewhere."),

            // ────────── Phase 9: Carl sends γ to Ben ──────────
            .init(id: "carl-decides-ben", kind: .decideSend(from: .carl, to: .ben, messageId: "γ"), durationSeconds: 3.5,
                  narration: "Carl sends γ to Ben."),
            .init(id: "gamma-flies-to-ben", kind: .fly(from: .carl, to: .ben, messageId: "γ"), durationSeconds: 10.0,
                  narration: "γ travels to Ben."),
            .init(id: "gamma-arrives-ben", kind: .arrive(at: .ben, messageId: "γ"), durationSeconds: 2.5,
                  narration: "Ben receives γ."),
            .init(id: "ben-opens-gamma", kind: .open(at: .ben, messageId: "γ"), durationSeconds: 3.0,
                  narration: "Ben opens γ."),
            .init(id: "ben-reads-body-gamma", kind: .readBody(at: .ben, messageId: "γ"), durationSeconds: 3.5,
                  narration: "Reads body."),
            .init(id: "ben-reads-parents-gamma", kind: .readParents(at: .ben, messageId: "γ"), durationSeconds: 3.5,
                  narration: "Reads parents: α (only). Same evidence Aaron saw — Carl wrote γ before he knew about β."),
            .init(id: "ben-resolves-alpha-from-gamma", kind: .resolveParent(at: .ben, messageId: "γ", parentId: "α"), durationSeconds: 4.0,
                  narration: "Ben resolves α. ✓"),
            .init(id: "ben-verifies-gamma", kind: .verifyHash(at: .ben, messageId: "γ"), durationSeconds: 3.5,
                  narration: "Hash check passes. ✓"),
            .init(id: "ben-accepts-gamma", kind: .acceptIntoView(at: .ben, messageId: "γ"), durationSeconds: 3.0,
                  narration: "Ben's local view: {α, β, γ}."),

            // ────────── Phase 10: Convergence ──────────
            .init(id: "convergence", kind: .settle(label: "Converged"), durationSeconds: 8.0,
                  narration: "All three honest validators now hold the SAME set of messages: {α, β, γ}. Their local DAGs have converged. This is local consensus emerging — not from any vote, but from each player observing what the others said and accepting it after verification. Common knowledge of the events has formed."),
        ]

        // Fill in cumulative startTimes.
        var t: Double = 0
        var assigned: [Ch01Beat] = []
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

    /// Find the active beat at timeline position `t`. Returns nil before
    /// the first beat or after the last.
    static func activeBeat(at t: Double) -> Ch01Beat? {
        let clamped = max(0, min(t, totalDuration))
        // Linear scan is fine for ~75 beats. Could binary-search if it ever matters.
        return beats.first { $0.startTime <= clamped && clamped < $0.endTime }
            ?? beats.last
    }

    /// Pure function: world state at any timeline position.
    static func state(at t: Double) -> Ch01WorldState {
        var w = Ch01WorldState()
        for cast in Ch01Cast.allCases { w.views[cast] = [] }
        let clamped = max(0, min(t, totalDuration))

        for beat in beats {
            // Beats fully in the past contribute their permanent effects.
            // Beats currently active contribute permanent-up-to-now plus
            // their ephemeral animation state.
            // Beats in the future contribute nothing.
            if clamped < beat.startTime { break }
            let isActive = clamped < beat.endTime
            let progress = isActive
                ? max(0, min(1, (clamped - beat.startTime) / beat.durationSeconds))
                : 1.0

            applyBeat(beat, progress: progress, isActive: isActive, into: &w)

            if isActive {
                w.activeBeat = beat
                w.activeProgress = progress
            }
        }
        return w
    }

    private static func applyBeat(
        _ beat: Ch01Beat, progress: Double, isActive: Bool,
        into w: inout Ch01WorldState
    ) {
        switch beat.kind {
        case .introduce(let cast):
            // Permanent once started.
            w.introduced.insert(cast)

        case .think(let cast, let label):
            if isActive {
                w.thought = .init(cast: cast, label: label)
            }

        case .selectPayload(let mid):
            // Permanent: composing exists with payload filled (until seal).
            ensureComposing(messageId: mid, into: &w)
            w.composing?.payloadFilled = true
            if isActive { /* current focus */ }

        case .selectParents(let mid):
            ensureComposing(messageId: mid, into: &w)
            w.composing?.parentsFilled = true

        case .computePoW(let mid):
            ensureComposing(messageId: mid, into: &w)
            // PoW progress equals the beat's progress (0..1).
            w.composing?.powProgress = progress

        case .seal(let mid):
            // Permanent: message is sealed; composing finishes.
            w.sealedMessages.insert(mid)
            // Author "knows" their own message after sealing.
            if let msg = messages[mid] {
                w.views[msg.author, default: []].insert(mid)
            }
            // Once sealed, drop the composing state.
            if !isActive { w.composing = nil }
            else {
                ensureComposing(messageId: mid, into: &w)
                w.composing?.sealed = true
            }

        case .decideSend(let from, let to, let mid):
            if isActive {
                w.decideArrow = .init(from: from, to: to, messageId: mid)
            }

        case .fly(let from, let to, let mid):
            if isActive {
                w.inFlight = .init(messageId: mid, from: from, to: to,
                                    progress: progress)
            }

        case .arrive(let at, let mid):
            if isActive {
                // The envelope is settling against the recipient's lane.
                w.openEnvelope = .init(recipient: at, messageId: mid)
            }

        case .open(let at, let mid):
            if isActive {
                w.openEnvelope = .init(recipient: at, messageId: mid)
            } else {
                // Stays "open" until verify completes — handled below.
                if w.openEnvelope?.recipient != at || w.openEnvelope?.messageId != mid {
                    w.openEnvelope = .init(recipient: at, messageId: mid)
                }
            }

        case .readBody(let at, let mid):
            ensureOpenEnvelope(at: at, messageId: mid, into: &w)
            w.openEnvelope?.bodyRevealed = true

        case .readParents(let at, let mid):
            ensureOpenEnvelope(at: at, messageId: mid, into: &w)
            w.openEnvelope?.parentsRevealed = true

        case .resolveParent(let at, let mid, let parentId):
            ensureOpenEnvelope(at: at, messageId: mid, into: &w)
            w.openEnvelope?.resolvedParents.insert(parentId)

        case .verifyHash(let at, let mid):
            ensureOpenEnvelope(at: at, messageId: mid, into: &w)
            w.openEnvelope?.verified = true

        case .acceptIntoView(let at, let mid):
            // Permanent: recipient now holds the message.
            w.views[at, default: []].insert(mid)
            // Once accepted, the open envelope is dismissed.
            if !isActive {
                if w.openEnvelope?.recipient == at && w.openEnvelope?.messageId == mid {
                    w.openEnvelope = nil
                }
            }

        case .settle:
            break  // pure narration / quiet beat
        }

        // Clear ephemeral state on transition out: if this beat is in the
        // past, its ephemeral things should not bleed forward.
        if !isActive {
            switch beat.kind {
            case .think:
                if w.thought != nil && w.activeBeat?.id != beat.id {
                    // Only clear if a later think doesn't override.
                    w.thought = nil
                }
            case .decideSend:
                if w.decideArrow != nil && w.activeBeat?.id != beat.id {
                    w.decideArrow = nil
                }
            case .fly:
                if w.inFlight != nil && w.activeBeat?.id != beat.id {
                    w.inFlight = nil
                }
            default: break
            }
        }
    }

    private static func ensureComposing(messageId: String, into w: inout Ch01WorldState) {
        if w.composing?.messageId != messageId {
            guard let msg = messages[messageId] else { return }
            w.composing = .init(messageId: messageId, author: msg.author)
        }
    }

    private static func ensureOpenEnvelope(at: Ch01Cast, messageId: String, into w: inout Ch01WorldState) {
        if w.openEnvelope?.recipient != at || w.openEnvelope?.messageId != messageId {
            w.openEnvelope = .init(recipient: at, messageId: messageId)
        }
    }
}
