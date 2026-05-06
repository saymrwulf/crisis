import Foundation

struct ChapterDef: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let sceneCount: Int
}

struct SceneAddress: Equatable, Hashable {
    let chapter: Int   // 0-based
    let scene: Int     // 0-based within chapter

    var globalIndex: Int {
        var idx = 0
        for ch in 0..<chapter {
            idx += AllChapters.list[ch].sceneCount
        }
        return idx + scene
    }

    static func from(globalIndex: Int) -> SceneAddress {
        var remaining = globalIndex
        for (ci, ch) in AllChapters.list.enumerated() {
            if remaining < ch.sceneCount {
                return SceneAddress(chapter: ci, scene: remaining)
            }
            remaining -= ch.sceneCount
        }
        let last = AllChapters.list.count - 1
        return SceneAddress(chapter: last, scene: AllChapters.list[last].sceneCount - 1)
    }
}

enum AllChapters {
    // Titles use the redesign's story-beat + [Technical: ...] format. The
    // story-beat sentence makes the chapter approachable for a noob; the
    // bracket reminds engineers which protocol concept the chapter maps to.
    // Scene counts unchanged from the previous structure so every existing
    // SceneRouter case keeps lining up.
    static let list: [ChapterDef] = [
        ChapterDef(id: 0, title: "Four friends, one ledger, no boss.",
                   subtitle: "[Technical: validator set & the BFT consensus problem]",
                   sceneCount: 3),
        ChapterDef(id: 1, title: "Aaron speaks. Ben listens. The graph begins.",
                   subtitle: "[Technical: asynchronous gossip & the Lamport DAG]",
                   sceneCount: 7),
        ChapterDef(id: 2, title: "Dave can't hear Aaron. The graph splits.",
                   subtitle: "[Technical: network partition & local divergence]",
                   sceneCount: 4),
        ChapterDef(id: 3, title: "Counting witnesses to mark a round.",
                   subtitle: "[Technical: PoW weight accumulation → round boundary]",
                   sceneCount: 3),
        ChapterDef(id: 4, title: "Did you see what I saw?",
                   subtitle: "[Technical: virtual voting via strongly-seeing paths]",
                   sceneCount: 3),
        ChapterDef(id: 5, title: "One vertex per round becomes the spokesperson.",
                   subtitle: "[Technical: PoW leader election]",
                   sceneCount: 2),
        ChapterDef(id: 6, title: "Spokespersons line up. Everyone else falls in behind.",
                   subtitle: "[Technical: total order via Kahn's algorithm]",
                   sceneCount: 3),
        ChapterDef(id: 7, title: "The leader knows. Did the leader tell anyone?",
                   subtitle: "[Technical: data availability — gossip is not storage]",
                   sceneCount: 4),
        ChapterDef(id: 8, title: "Erasure shards make the data un-loseable.",
                   subtitle: "[Technical: erasure coding + Merkle proofs + fee market]",
                   sceneCount: 5),
        ChapterDef(id: 9, title: "Dave lies. Crisis catches him.",
                   subtitle: "[Technical: Byzantine resilience under f < n/3]",
                   sceneCount: 2),
    ]

    static var totalScenes: Int {
        list.reduce(0) { $0 + $1.sceneCount }
    }
}
