import Foundation

struct ChapterDef: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let sceneCount: Int
}

struct SceneAddress: Equatable {
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
    static let list: [ChapterDef] = [
        ChapterDef(id: 0, title: "The Problem", subtitle: "Why is consensus hard?", sceneCount: 3),
        ChapterDef(id: 1, title: "Building the Graph", subtitle: "Asynchronous gossip & the Lamport DAG", sceneCount: 7),
        ChapterDef(id: 2, title: "Network Partition", subtitle: "When nodes lose connectivity", sceneCount: 4),
        ChapterDef(id: 3, title: "Rounds from Weight", subtitle: "PoW accumulation triggers boundaries", sceneCount: 3),
        ChapterDef(id: 4, title: "Virtual Voting", subtitle: "No vote messages — just graph inference", sceneCount: 3),
        ChapterDef(id: 5, title: "Leader Election", subtitle: "The PoW lottery picks a winner", sceneCount: 2),
        ChapterDef(id: 6, title: "Total Order", subtitle: "Deterministic ordering = convergence", sceneCount: 3),
        ChapterDef(id: 7, title: "Data Availability — The Problem", subtitle: "Why gossip is not storage", sceneCount: 4),
        ChapterDef(id: 8, title: "Data Availability — A Design", subtitle: "Erasure coding, Merkle proofs & incentives", sceneCount: 5),
        ChapterDef(id: 9, title: "Byzantine Resilience", subtitle: "Why attackers fail", sceneCount: 2),
    ]

    static var totalScenes: Int {
        list.reduce(0) { $0 + $1.sceneCount }
    }
}
