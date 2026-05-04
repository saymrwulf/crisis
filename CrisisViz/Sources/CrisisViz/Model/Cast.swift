import SwiftUI

/// The four named validators that anchor the entire teaching narrative.
///
/// Why this exists: in the redesign we made on 2026-05-04, we replaced the
/// generic "honest-0…honest-5 + byzantine-0" naming with a persistent cast of
/// four MALE characters who appear in every chapter with a stable color and
/// vertical lane. A returning viewer always knows where Aaron is.
///
/// **Mapping policy** (since the loaded simulation has 6 honest + 1 byzantine,
/// not 4 total):
///   - First three honest nodes (sorted by `name`) → Aaron, Ben, Carl
///   - First byzantine node → Dave
///   - Any remaining honest nodes → unnamed `Peer-N` rendered in muted gray
///
/// All chapters read color and display name through `Cast.role(for:)`. Never
/// use `DataManager.palette` directly for cast members — go through Cast so the
/// whole story stays color-consistent.
struct CastRole: Identifiable, Hashable {
    let id: String          // stable cast slot id ("aaron", "ben", "carl", "dave", "peer-N")
    let displayName: String // "Aaron", "Ben", "Carl", "Dave", "Peer-1"
    let color: Color
    let cue: String         // one-line personality cue shown in the sidebar
    let isByzantineSlot: Bool
    let isNamedCast: Bool   // true for the 4 leads, false for muted peers
}

enum Cast {
    // MARK: - Color slots — never used outside the cast

    static let coral  = Color(red: 0.97, green: 0.50, blue: 0.45)  // Aaron
    static let teal   = Color(red: 0.30, green: 0.78, blue: 0.78)  // Ben
    static let amber  = Color(red: 0.96, green: 0.74, blue: 0.30)  // Carl
    static let violet = Color(red: 0.72, green: 0.50, blue: 0.92)  // Dave (Byzantine)
    static let muted  = Color(red: 0.55, green: 0.58, blue: 0.62)  // Peer-N

    // MARK: - The four named leads

    static let aaron = CastRole(
        id: "aaron",
        displayName: "Aaron",
        color: coral,
        cue: "Proposer — \"I saw it first\"",
        isByzantineSlot: false,
        isNamedCast: true
    )
    static let ben = CastRole(
        id: "ben",
        displayName: "Ben",
        color: teal,
        cue: "Careful witness",
        isByzantineSlot: false,
        isNamedCast: true
    )
    static let carl = CastRole(
        id: "carl",
        displayName: "Carl",
        color: amber,
        cue: "Late joiner — graph fills in last",
        isByzantineSlot: false,
        isNamedCast: true
    )
    static let dave = CastRole(
        id: "dave",
        displayName: "Dave",
        color: violet,
        cue: "Partitioned / Byzantine actor",
        isByzantineSlot: true,
        isNamedCast: true
    )

    /// The four leads in fixed lane order — top to bottom: Aaron, Ben, Carl, Dave.
    /// Lane order never changes; this is what makes "where is Aaron?" a trivial
    /// question for the viewer in every chapter.
    static let leads: [CastRole] = [aaron, ben, carl, dave]

    static func peer(_ index: Int) -> CastRole {
        CastRole(
            id: "peer-\(index)",
            displayName: "Peer-\(index)",
            color: muted,
            cue: "background validator",
            isByzantineSlot: false,
            isNamedCast: false
        )
    }

    // MARK: - processIdHex → CastRole assignment
    //
    // Built once when DataManager finishes loading the simulation. Cached on
    // DataManager so every Canvas render is a dictionary lookup, not a sort.

    /// Build the assignment for an ordered list of `NodeMeta`. Returns a
    /// dictionary keyed by `processIdHex`. Honest nodes are assigned in
    /// alphabetical-by-name order (matches the testbed's deterministic sort).
    static func buildAssignment(nodes: [NodeMeta]) -> [String: CastRole] {
        let honest = nodes.filter { !$0.isByzantine }.sorted { $0.name < $1.name }
        let byz    = nodes.filter {  $0.isByzantine }.sorted { $0.name < $1.name }

        var out: [String: CastRole] = [:]
        let leadHonestSlots: [CastRole] = [aaron, ben, carl]

        for (i, node) in honest.enumerated() {
            if i < leadHonestSlots.count {
                out[node.processIdHex] = leadHonestSlots[i]
            } else {
                // Surplus honest nodes become muted peers, numbered from 1.
                out[node.processIdHex] = peer(i - leadHonestSlots.count + 1)
            }
        }
        // Byzantine slot: first byzantine claims Dave; any extras also become peers.
        for (i, node) in byz.enumerated() {
            if i == 0 {
                out[node.processIdHex] = dave
            } else {
                out[node.processIdHex] = peer(100 + i)  // distinct namespace
            }
        }
        return out
    }
}
