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
        ["Aaron broadcasts.",
         "Ben answers Aaron.",
         "Carl also points back to Aaron.",
         "Watch a message travel — slow motion gossip.",
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
            "Aaron grinds proof-of-work and broadcasts the first message we follow on this canvas. There is no global clock — he just finishes his puzzle and sends. The hash printed inside Aaron's circle is the message's own digest, computed by Aaron when he created it. From now on that hash is its name.",
            "Ben has already received Aaron's message via gossip. When Ben produces his own next message, he embeds Aaron's hash inside it as a parent reference. The arrow you see — pointing FROM Ben's vertex TO Aaron's — is that parent edge. It says \"I saw Aaron's message before I spoke.\"",
            "Carl's first message ALSO points back to Aaron's first message — same arrow shape as Ben's, just from a different lane. Carl does NOT reference Ben (Carl hadn't received Ben's message when he wrote his own). Two independent observers, both pointing at Aaron. Read the bottom panel literally: it shows what each player has actually received via gossip at this moment. Notice Ben hasn't received Carl's message yet — so the COMMON-KNOWLEDGE column drops Carl. That gap is what gossip fixes next.",
            "Slow motion. Aaron writes message α (the body and a hash header fill in line by line). When sealed, α flies through the ether — twice, once toward Ben, once toward Carl, at different speeds. Ben gets α first, his bubble grows. Ben writes β with α's hash inside. While β is in flight, Carl — who has only just received α — writes γ referencing α (NOT β, because β hasn't arrived). Watch the asymmetry: same world, different bubbles, until gossip catches up.",
            "But hashes are one-way. If you only see Carl's hash, you cannot tell what's underneath it. You need the actual messages, opened up, to verify the chain. This is why \"data availability\" will become its own chapter later.",
            "Each player keeps a LOCAL DAG — only the messages they've received. Different players have different views in real time. But the graph is determined by message contents alone: same set of messages received → same graph computed, byte-for-byte. Gossip is idempotent (re-receiving an old message changes nothing because the digest is already known), so eventually every honest player's view converges to the same DAG. This determinism is what makes consensus possible.",
            "From any vertex you can walk back through ALL its parent hashes — not just one chain, but a tree fanning out into every ancestor. The yellow ring shows the full ancestor cone of one leaf. Where the cone bottoms out (★ GENESIS) are the very first messages anyone sent. That cone is the vertex's complete causal history.",
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
            "What is a round? It is NOT a clock interval. A vertex's round number is computed by counting parent edges back: if a vertex sees enough weight from its causal history, its round is one higher than its parents'. A round-4 message can still reference round-1 messages it just received — old parents are perfectly legitimate, gossip is allowed to deliver old messages late. Each message carries proof-of-work weight; harder puzzles → heavier messages.",
            "When the total weight inside a round crosses a threshold, the round closes. The very last message to push it over the line is flagged with `is_last` — that's the round boundary marker. Rounds are *derived*, not declared — every honest validator who has the same graph computes the identical round boundary just by counting weight. Nobody negotiates.",
            "Bookkeeping: every honest player keeps their own DAG of received messages, full stop. Re-gossip is harmless — duplicate digests are detected and dropped. Players don't track who they sent what to; the gossip layer fans out and the digest dedupes on the receiver. Weight is arithmetic, and arithmetic doesn't depend on who you ask.",
        ],
        // Ch 4: Did you see what I saw?
        [
            "Crisis sends NO ballots and NO vote messages. Voting is just \"can I trace a path through my graph from your vertex back to a shared ancestor?\". If yes, you've seen what I've seen.",
            "Watch this slow walk. We pick a recent vertex from Aaron and one from Carl — both heavy enough that the protocol cares. We then draw the depth-2 ancestor cone of each: every vertex they can trace back through parent edges. The pulsing white region is where the two cones overlap — vertices BOTH of them have witnessed.",
            "Two or more shared ancestors is enough. Aaron and Carl now agree. This is the collapse: their two opinions snap together into one round-marked consensus, with no message ever named \"vote\" being sent.",
        ],
        // Ch 5: One vertex per round becomes the spokesperson.
        [
            "In each round, every validator's heaviest vertex competes for the round leadership — Aaron, Ben, Carl, the background peers, and Dave too. The heaviest weighing in for the round wins. Dave's vertices, as a Byzantine actor, are never trusted — but their PoW weight is still real, so they participate in the lottery.",
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
            "Dave is the byzantine actor. Look at his lane: every red-ringed vertex is a message that conflicts with another Dave vertex — same identity, different content or different parents. He's trying to make Aaron, Ben and Carl disagree about what they saw.",
            "It doesn't work. Aaron and Ben gossip with each other and quickly notice they have two contradictory Dave-vertices. The protocol marks Dave's vertices as banned (red X). Total order routes around them. Aaron and Ben still converge — and Dave's weight is wasted.",
        ],
    ]
}
