import Foundation

/// Static narration text for each scene, indexed by chapter and scene.
enum SceneNarrations {
    static func title(chapter: Int, scene: Int) -> String {
        guard chapter < titles.count, scene < titles[chapter].count else { return "" }
        return titles[chapter][scene]
    }

    static func narration(chapter: Int, scene: Int) -> String {
        guard chapter < narrations.count, scene < narrations[chapter].count else { return "" }
        return narrations[chapter][scene]
    }

    // MARK: - Titles

    private static let titles: [[String]] = [
        // Ch 0: The Problem
        ["Three Nodes, Three Truths", "Why Agreement Is Hard", "The Question"],
        // Ch 1: Building the Graph
        ["Async Gossip Begins", "The DAG Grows", "Tip References Only", "Hash Inspection",
         "Commit-Reveal", "Graph Identity", "Recursive Expansion"],
        // Ch 2: Network Partition
        ["Connections Break", "Diverging Realities", "Virtual Voting Diverges", "Reconnection"],
        // Ch 3: Rounds from Weight
        ["Weight Accumulates", "Threshold Crossing", "Unanimity"],
        // Ch 4: Virtual Voting
        ["No Vote Messages", "SVP Trace", "Deterministic Outcome"],
        // Ch 5: Leader Election
        ["Candidates by Weight", "The Hash Lottery"],
        // Ch 6: Total Order
        ["Topological Sort", "Animated Ordering", "Convergence"],
        // Ch 7: DA — The Problem
        ["Gossip ≠ Storage", "The Bootstrapping Problem", "Sybil Attack on Reveals", "The Separation"],
        // Ch 8: DA — A Design
        ["Erasure Coding", "Merkle Tree of Chunks", "On-Demand Retrieval", "Incentivized Storage", "Full Stack"],
        // Ch 9: Byzantine Resilience
        ["The Attacker", "Why Attacks Fail"],
    ]

    // MARK: - Narrations

    private static let narrations: [[String]] = [
        // Ch 0: The Problem
        [
            "Three nodes observe transactions in different orders. Without a shared clock, each node's local history tells a different story.",
            "In an asynchronous network with no central authority, agreeing on a single order requires a protocol — brute force won't work.",
            "How can nodes that never fully trust each other converge on one truth? This is the problem Crisis solves.",
        ],
        // Ch 1: Building the Graph
        [
            "Nodes grind proof-of-work at different speeds. There is no global clock — messages emerge chaotically, whenever a node finishes its PoW puzzle.",
            "Each new message references the DAG tips it has seen — the frontier of knowledge. The graph grows organically, shaped only by causality.",
            "A message references only the TIPS of the DAG — the latest messages a node knows about. Transitive hash commitment means everything behind those tips is implicitly referenced.",
            "Click any vertex to inspect it. Follow hash references backward through the graph — each hash reveals the full causal history beneath it.",
            "Hash is opaque: hash(C) reveals nothing about A or B inside. Only when the pre-image is shared can the contents be verified.",
            "Despite chaotic timing, the same set of messages always produces the same graph. The DAG is deterministic given its inputs.",
            "Opening hash layers recursively: from any message, you can trace the entire history back to genesis by following pre-images.",
        ],
        // Ch 2: Network Partition
        [
            "Two nodes lose connectivity. Their messages stop flowing to the network, and the network's messages stop reaching them.",
            "The majority continues building a rich DAG. The isolated nodes only see each other — their local DAG is sparse and incomplete.",
            "Virtual voting runs on whatever graph a node sees. Same algorithm, different graph → different election results. The isolated nodes disagree.",
            "When connectivity returns, gossip floods the gap. The isolated nodes catch up, graphs converge, and consensus resumes.",
        ],
        // Ch 3: Rounds from Weight
        [
            "Each message carries proof-of-work weight. As messages accumulate in a round, the total weight grows toward a threshold.",
            "When cumulative weight crosses the threshold, a round boundary is declared. The is_last flag marks the transition.",
            "All honest nodes, seeing the same graph, compute the same round boundaries. Weight is objective — no negotiation needed.",
        ],
        // Ch 4: Virtual Voting
        [
            "There are no vote messages in Crisis. Votes are inferred from graph structure — if you can see a path, you can count the vote.",
            "Strongly-seeing path (SVP): trace from a candidate message through the DAG to the deciding round. Each intermediate message is a witness.",
            "Same graph, same paths, same votes. Virtual voting is deterministic — all honest nodes reach the same conclusion without exchanging a single ballot.",
        ],
        // Ch 5: Leader Election
        [
            "All decided messages in a round are candidates. They're ranked by their PoW weight — heavier proof wins.",
            "The highest-weight candidate becomes the round's leader. Since PoW hashes are unpredictable, no one can game the outcome.",
        ],
        // Ch 6: Total Order
        [
            "Kahn's algorithm produces a topological ordering of the DAG. When multiple orderings are possible, PoW weight breaks ties deterministically.",
            "Watch as vertices slide into their final ordered positions. The DAG's partial order becomes a total order.",
            "Every honest node produces the identical sequence. Convergence is guaranteed — the same graph always yields the same order.",
        ],
        // Ch 7: DA — The Problem
        [
            "Gossip is push-based: nodes broadcast CURRENT messages to peers. It's a firehose for the present, not a database for the past.",
            "A new node joins and needs historical data. If it requests all pre-images via gossip: O(history) bandwidth per joiner. The network drowns.",
            "An attacker spins up 10,000 sybil nodes. Each requests full history. Bandwidth meters max out. The honest network collapses under the load.",
            "Crisis provides ORDERING — deterministic from the DAG. Data availability is a SEPARATE layer. They're coupled only by hash commitments.",
        ],
        // Ch 8: DA — A Design
        [
            "Split each message into k chunks, encode to n chunks (n > k). Any k-of-n suffice to reconstruct. Redundancy without full replication.",
            "Each chunk gets a Merkle proof. A requester can verify any single chunk without downloading all of them. Compact, trustless verification.",
            "Node Z wants a pre-image. It sends a request with a fee attached. A storage node responds with the chunk + Merkle proof. Point-to-point, not broadcast.",
            "Storage nodes earn fees for serving data. A fee market emerges: popular data is cheap (many providers), rare data commands a premium.",
            "The full stack: Crisis orders messages (consensus layer). The DA layer stores and serves pre-images (storage layer). Nodes pay for what they need.",
        ],
        // Ch 9: Byzantine Resilience
        [
            "A byzantine node is highlighted. It can send conflicting messages, withhold data, or try to manipulate voting outcomes.",
            "Attacks fail because: the protocol tolerates < 1/3 byzantine weight, hashes can't be forged, and PoW outcomes are unpredictable.",
        ],
    ]
}
