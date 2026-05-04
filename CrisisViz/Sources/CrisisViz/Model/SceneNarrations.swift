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

    // Scene titles use the same story-beat phrasing as chapter titles.
    // [Technical: ...] suffix is added on the *opening* scene of each
    // chapter (it would be noise on every scene); subsequent scenes are
    // pure narrative beats.
    private static let titles: [[String]] = [
        // Ch 0: Four friends, one ledger, no boss.
        ["Meet the cast.", "Each writes their own log.", "But there's only one truth."],
        // Ch 1: Aaron speaks. Ben listens. The graph begins.
        ["Aaron's first message.",
         "Ben copies what he saw.",
         "Carl arrives and links in.",
         "Click any vertex to look inside.",
         "A hash hides what's underneath.",
         "Same messages, same graph, every time.",
         "Following hashes back to the start."],
        // Ch 2: Dave can't hear Aaron. The graph splits.
        ["Dave goes silent.",
         "The world keeps building without him.",
         "Two graphs, two stories.",
         "Dave reconnects. Stories reconcile."],
        // Ch 3: Counting witnesses to mark a round.
        ["Each message carries weight.",
         "Enough weight, and a round closes.",
         "Everyone agrees on the round, without talking."],
        // Ch 4: Did you see what I saw?
        ["No vote messages — only the graph.",
         "Walking back through shared ancestors.",
         "If we share enough ancestors, we agree."],
        // Ch 5: One vertex per round becomes the spokesperson.
        ["Heaviest weight wins the round.",
         "The hash lottery picks who speaks."],
        // Ch 6: Spokespersons line up. Everyone else falls in behind.
        ["Sorting the DAG into a line.",
         "Vertices slide into their place.",
         "Everyone produces the same line."],
        // Ch 7: The leader knows. Did the leader tell anyone?
        ["Gossip is loud, but forgetful.",
         "A new joiner asks for everything.",
         "Ten thousand fake joiners ask for everything.",
         "Ordering and storage are different problems."],
        // Ch 8: Erasure shards make the data un-loseable.
        ["Cut the message into k shards, send n.",
         "Every shard carries a Merkle proof.",
         "Pay a small fee, get a shard back.",
         "Storage nodes earn for holding rare data.",
         "The full stack: order on top, data underneath."],
        // Ch 9: Dave lies. Crisis catches him.
        ["Dave forks his message.",
         "The protocol routes around him."],
    ]

    // MARK: - Narrations

    private static let narrations: [[String]] = [
        // Ch 0: Four friends, one ledger, no boss.
        [
            "Aaron, Ben, Carl and Dave each run a node. There is no central server and no boss who decides what happened first. Whatever order of events emerges has to come from the four of them talking to each other.",
            "Each of the four keeps their own log of what they have seen. Because messages travel at different speeds, they can record the same events in different orders. Right now, four logs means four different stories.",
            "Yet at the end of the day they all need to agree on ONE history — same events, same order, byte-for-byte. This is the problem Crisis solves: how to turn four independent points of view into one shared truth, even when one of the four (Dave) is lying.",
        ],
        // Ch 1: Aaron speaks. Ben listens. The graph begins.
        [
            "Aaron grinds proof-of-work and produces the first message. There is no global clock telling him when to do this — he just finishes his PoW puzzle and broadcasts. The story starts whenever he is ready.",
            "Ben hears Aaron's message and references it from his own next message. That little arrow between them — Ben's vertex pointing back to Aaron's — is what we'll call a parent edge. It says \"I saw this before I spoke\".",
            "Carl now joins in. His message points back to whatever tips of the DAG he can see — currently Aaron's and Ben's. The graph is starting to braid the four perspectives together.",
            "You can click any vertex to look inside it. The window shows what that validator saw at that moment — its own message, plus the chain of parents it acknowledged.",
            "But hashes are one-way. If you only see Carl's hash, you cannot tell what's underneath it. You need the actual messages, opened up, to verify the chain. This is why \"data availability\" will become its own chapter later.",
            "Despite the chaotic timing, the same set of messages always produces the same graph. Aaron's view, Ben's view, and Carl's view — once they've all gossiped — are byte-for-byte identical. This determinism is what makes consensus even possible.",
            "From any vertex you can walk back through parent hashes all the way to the very first message. That walk is the validator's full causal history.",
        ],
        // Ch 2: Dave can't hear Aaron. The graph splits.
        [
            "Dave's connection drops. His messages stop flowing to Aaron, Ben and Carl, and theirs stop reaching him. Notice Dave's lane is still drawing vertices — but the rest of the world stops linking to them.",
            "Aaron, Ben and Carl keep gossiping with each other and their part of the graph stays rich. Dave's lane, on the other hand, is producing messages that nobody else can see — his graph is sparse and increasingly out of step.",
            "Now we have two stories on screen. The top three lanes converge on one history. Dave's lane has its own. Both are internally consistent — that is the danger of partitions.",
            "Dave's connection comes back. Gossip floods the gap, the missing messages catch up in both directions, and Dave's view merges back into the same graph the others were building. Consensus picks up where it left off.",
        ],
        // Ch 3: Counting witnesses to mark a round.
        [
            "Every message carries a proof-of-work weight — the harder the puzzle, the heavier the message. Round 0 starts collecting weight as Aaron, Ben and Carl publish.",
            "When the total weight inside a round crosses a threshold, the round closes. The very last message to push it over the line is flagged with `is_last` — that's the round boundary marker.",
            "Crucially, every honest validator looking at the same graph computes the same round boundary. Nobody negotiates. Weight is just arithmetic — and arithmetic does not depend on who you ask.",
        ],
        // Ch 4: Did you see what I saw?
        [
            "Crisis sends NO ballots and NO vote messages. Voting is just \"can I trace a path through my graph from your vertex back to a shared ancestor?\". If yes, you've seen what I've seen.",
            "Watch this slow walk. We highlight Aaron's round-4 vertex on top, and Carl's round-4 vertex below. We then draw the depth-3 ancestor cone of each. The pulsing white region is where the cones overlap — those are the vertices BOTH of them have witnessed.",
            "Two or more shared ancestors is enough. Aaron and Carl now agree. This is the collapse: their two opinions snap together into one round-marked consensus, with no message ever named \"vote\" being sent.",
        ],
        // Ch 5: One vertex per round becomes the spokesperson.
        [
            "In each round, Aaron's, Ben's, and Carl's vertices all compete on PoW weight. Heaviest wins. Dave's vertices, as a Byzantine actor, are never trusted — but their weight is still real, so they participate in the lottery.",
            "The heaviest-weight vertex of the round becomes that round's leader — its spokesperson. Nobody can game this; PoW outcomes are unpredictable until the puzzle is solved.",
        ],
        // Ch 6: Spokespersons line up. Everyone else falls in behind.
        [
            "Every leader vertex pulls its causal history with it. Run Kahn's topological sort across that history, with PoW weight breaking ties, and you get a single ordered line.",
            "Watch as Aaron's and Ben's vertices slide into the snake. The DAG's partial order — \"this came before that\" only where parents say so — collapses into a total order: position 0, position 1, position 2, …",
            "Every honest validator produces the IDENTICAL sequence. That's convergence. Whatever Aaron's line is, Ben's line and Carl's line are byte-for-byte the same.",
        ],
        // Ch 7: The leader knows. Did the leader tell anyone?
        [
            "Gossip is great at \"here's what just happened\". It is awful at \"can you replay everything from the beginning?\". The firehose flows forward, not backward.",
            "A new validator joins. To catch up, it needs every historical message. If we serve that over gossip, every joiner asks the network to replay all of history. Bandwidth dies.",
            "An attacker spins up ten thousand fake joiners, each demanding full history. The honest network melts. This is why ordering and storage have to be separated.",
            "Crisis solves ORDERING — that's the DAG. Storing and serving the actual message bytes is a SEPARATE layer, glued on by hash commitments. The next chapter shows the design.",
        ],
        // Ch 8: Erasure shards make the data un-loseable.
        [
            "Cut each message into k shards. Encode it to n shards where n > k, so any k of those n are enough to reconstruct the whole. No single storage node holds the message — the message is *spread*.",
            "Every shard ships with a Merkle proof tying it back to the original message hash. A requester can verify any single shard against the hash they already have, without trusting the storage node.",
            "When Aaron needs an old message back, he pays a small fee and asks for shards. Storage nodes hand them over with proofs. He reconstructs the message from any k of them.",
            "Storage nodes that hold rare data earn more — a tiny fee market for memory. Popular data stays cheap; obscure data commands a premium; nothing is ever quietly forgotten.",
            "Top to bottom: Crisis orders messages, the DA layer stores and serves their bytes, and validators pay for what they actually need. The two layers are independent but locked together by hashes.",
        ],
        // Ch 9: Dave lies. Crisis catches him.
        [
            "Dave decides to send conflicting messages — one to Aaron, a different one to Ben. He's trying to make Aaron and Ben disagree about what they saw.",
            "It doesn't work. Aaron and Ben gossip with each other and quickly notice they have two contradictory Dave-vertices. The protocol marks Dave's vertices as banned (red X). Total order routes around them. Aaron and Ben still converge — and Dave's weight is wasted.",
        ],
    ]
}
