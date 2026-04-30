import Foundation

/// Pre-computed consensus data for one simulation step.
/// Derived from a StepSnapshot — all the information the views need.
struct ConsensusData {
    let step: Int
    let honestNames: [String]
    let maxRound: Int

    // Per-node max round
    let nodeMaxRounds: [String: Int]

    // Round unanimity: round -> all honest nodes have reached it
    let roundUnanimous: [Int: Bool]

    // Graph identity
    let graphStats: [GraphStats]
    let allGraphsIdentical: Bool

    // Leader info
    let perNodeLeaders: [String: [Int: String]]  // name -> round -> leader hex
    let leaderUnanimous: [Int: (Bool, String)]    // round -> (unanimous, leader hex)
    let leaderNames: [Int: String]                // round -> leader node name

    // Order
    let nodeOrdered: [String: Int]
    let agreedPrefix: Int
    let converged: Bool

    // Vertices/edges from first honest node
    let vertices: [VertexData]
    let edges: [EdgeData]
    let totalVertices: Int
    let newMessages: Int

    // is_last counts
    let nLastsTotal: Int

    // Example message for anatomy diagram
    let exampleMessage: ExampleMessage?

    // Node lasts per round
    let nodeLasts: [String: Set<Int>]

    // Kahn's algorithm
    let kahnSteps: [KahnStep]
    let kahnVertices: [String: VertexData]
    let kahnEdges: [EdgeData]
    let kahnLeaderHex: String
    let kahnLeaderName: String
    let kahnLeaderRound: Int

    // Config
    let difficulty: Int
}

struct GraphStats {
    let name: String
    let vertexCount: Int
    let edgeCount: Int
    let maxRound: Int
}

struct ExampleMessage {
    let digestHex: String
    let payload: String
    let fromName: String
    let processIdHex: String
    let weight: Int
    let refHexes: [String]
    let refInfo: [String]
}

struct KahnStep {
    let available: [String]
    let chosen: String
    let chosenWeight: Int
    let position: Int
    let payload: String
    let processName: String
}

// MARK: - Builder

extension ConsensusData {
    static func build(
        from sim: SimulationData,
        step: Int
    ) -> ConsensusData {
        let snap = sim.steps.first { $0.step == step }
        let honestNames = sim.nodes.filter { !$0.isByzantine }.map(\.name).sorted()
        let pidToName = Dictionary(uniqueKeysWithValues:
            sim.nodes.map { ($0.processIdHex, $0.name) }
        )

        guard let snap else {
            return .empty(step: step, honestNames: honestNames, difficulty: sim.config.difficulty)
        }

        // Per-node stats
        var nodeMaxRounds: [String: Int] = [:]
        var maxRound = 0
        var nodeOrdered: [String: Int] = [:]
        var perNodeLeaders: [String: [Int: String]] = [:]
        var nodeLasts: [String: Set<Int>] = [:]

        for name in honestNames {
            guard let ns = snap.nodeSnapshots[name] else { continue }
            nodeMaxRounds[name] = ns.maxRound
            maxRound = max(maxRound, ns.maxRound)
            nodeOrdered[name] = ns.numOrdered
            var leaders: [Int: String] = [:]
            for (rStr, hex) in ns.leaderRounds {
                if let r = Int(rStr) { leaders[r] = hex }
            }
            perNodeLeaders[name] = leaders

            var lasts = Set<Int>()
            for v in ns.vertices where v.isLast {
                lasts.insert(v.round)
            }
            nodeLasts[name] = lasts
        }

        // Graph stats + identity
        var graphStats: [GraphStats] = []
        for name in honestNames {
            if let ns = snap.nodeSnapshots[name] {
                graphStats.append(GraphStats(
                    name: name, vertexCount: ns.vertexCount,
                    edgeCount: ns.edges.count, maxRound: ns.maxRound
                ))
            }
        }
        let allIdentical: Bool = {
            guard let first = graphStats.first else { return false }
            return graphStats.allSatisfy {
                $0.vertexCount == first.vertexCount &&
                $0.edgeCount == first.edgeCount &&
                $0.maxRound == first.maxRound
            }
        }()

        // Round unanimity
        var roundUnanimous: [Int: Bool] = [:]
        for r in 0...maxRound {
            roundUnanimous[r] = honestNames.allSatisfy {
                (nodeMaxRounds[$0] ?? 0) >= r
            }
        }

        // First honest node data
        let firstNS = honestNames.compactMap { snap.nodeSnapshots[$0] }.first
        let vertices = firstNS?.vertices ?? []
        let edges = firstNS?.edges ?? []
        let totalVertices = firstNS?.vertexCount ?? 0
        let nLastsTotal = vertices.filter(\.isLast).count

        // New messages this step
        let stepEvents = sim.eventsForStep(step)
        let newMessages = stepEvents.filter {
            $0.type == "MESSAGE_CREATED" || $0.type == "BYZANTINE_MUTATION"
        }.count

        // Example message
        let exampleMessage = buildExampleMessage(
            events: stepEvents, ns: firstNS, pidToName: pidToName
        )

        // Leader unanimity
        var allLeaderRounds = Set<Int>()
        for leaders in perNodeLeaders.values {
            allLeaderRounds.formUnion(leaders.keys)
        }
        var leaderUnanimous: [Int: (Bool, String)] = [:]
        for r in allLeaderRounds.sorted() {
            var hexes = Set<String>()
            var allHave = true
            for name in honestNames {
                if let h = perNodeLeaders[name]?[r] {
                    hexes.insert(h)
                } else {
                    allHave = false
                }
            }
            if allHave && hexes.count == 1 {
                leaderUnanimous[r] = (true, hexes.first!)
            } else if let first = hexes.first {
                leaderUnanimous[r] = (false, first)
            }
        }

        // Leader names
        var digestToPid: [String: String] = [:]
        for v in vertices {
            digestToPid[v.digestHex] = v.processIdHex
        }
        var leaderNames: [Int: String] = [:]
        for (rnd, (_, hex)) in leaderUnanimous {
            if let pid = digestToPid[hex], let name = pidToName[pid] {
                leaderNames[rnd] = name
            }
        }

        // Kahn's algorithm
        let (kahnSteps, kahnVerts, kahnEdges, kahnHex, kahnName, kahnRound) =
            buildKahnData(leaderUnanimous: leaderUnanimous, leaderNames: leaderNames,
                          ns: firstNS, pidToName: pidToName)

        return ConsensusData(
            step: step,
            honestNames: honestNames,
            maxRound: maxRound,
            nodeMaxRounds: nodeMaxRounds,
            roundUnanimous: roundUnanimous,
            graphStats: graphStats,
            allGraphsIdentical: allIdentical,
            perNodeLeaders: perNodeLeaders,
            leaderUnanimous: leaderUnanimous,
            leaderNames: leaderNames,
            nodeOrdered: nodeOrdered,
            agreedPrefix: snap.agreedPrefixLength,
            converged: snap.convergence,
            vertices: vertices,
            edges: edges,
            totalVertices: totalVertices,
            newMessages: newMessages,
            nLastsTotal: nLastsTotal,
            exampleMessage: exampleMessage,
            nodeLasts: nodeLasts,
            kahnSteps: kahnSteps,
            kahnVertices: kahnVerts,
            kahnEdges: kahnEdges,
            kahnLeaderHex: kahnHex,
            kahnLeaderName: kahnName,
            kahnLeaderRound: kahnRound,
            difficulty: sim.config.difficulty
        )
    }

    static func empty(step: Int, honestNames: [String], difficulty: Int) -> ConsensusData {
        ConsensusData(
            step: step, honestNames: honestNames, maxRound: 0,
            nodeMaxRounds: [:], roundUnanimous: [:],
            graphStats: [], allGraphsIdentical: false,
            perNodeLeaders: [:], leaderUnanimous: [:], leaderNames: [:],
            nodeOrdered: [:], agreedPrefix: 0, converged: false,
            vertices: [], edges: [], totalVertices: 0, newMessages: 0,
            nLastsTotal: 0, exampleMessage: nil, nodeLasts: [:],
            kahnSteps: [], kahnVertices: [:], kahnEdges: [],
            kahnLeaderHex: "", kahnLeaderName: "", kahnLeaderRound: -1,
            difficulty: difficulty
        )
    }
}

// MARK: - Helpers

private func buildExampleMessage(
    events: [SimEvent], ns: NodeSnapshot?, pidToName: [String: String]
) -> ExampleMessage? {
    guard let ns else { return nil }
    guard let createEvent = events.first(where: { $0.type == "MESSAGE_CREATED" }) else {
        return nil
    }
    let targetHex = createEvent.string("digest_hex")
    guard !targetHex.isEmpty else { return nil }
    guard let targetV = ns.vertices.first(where: { $0.digestHex == targetHex }) else {
        return nil
    }

    let refHexes = ns.edges.filter { $0.from == targetHex }.map(\.to)
    let vsByHex = Dictionary(uniqueKeysWithValues: ns.vertices.map { ($0.digestHex, $0) })
    let refInfo = refHexes.map { rh -> String in
        if let rv = vsByHex[rh] {
            let rname = pidToName[rv.processIdHex] ?? String(rv.processIdHex.prefix(6))
            return "round \(rv.round), by \(rname)"
        }
        return "unknown"
    }

    return ExampleMessage(
        digestHex: targetV.digestHex,
        payload: targetV.payloadStr.isEmpty ? "(empty)" : targetV.payloadStr,
        fromName: pidToName[targetV.processIdHex] ?? "unknown",
        processIdHex: targetV.processIdHex,
        weight: targetV.weight,
        refHexes: refHexes,
        refInfo: refInfo
    )
}

private func buildKahnData(
    leaderUnanimous: [Int: (Bool, String)],
    leaderNames: [Int: String],
    ns: NodeSnapshot?,
    pidToName: [String: String]
) -> ([KahnStep], [String: VertexData], [EdgeData], String, String, Int) {
    guard let ns else { return ([], [:], [], "", "", -1) }

    // Find latest unanimous leader
    let unanimousRounds = leaderUnanimous.filter { $0.value.0 }
    guard let latestRound = unanimousRounds.keys.max(),
          let (_, latestHex) = unanimousRounds[latestRound] else {
        return ([], [:], [], "", "", -1)
    }

    // BFS from leader to find causal past
    var edgesMap: [String: [String]] = [:]
    for e in ns.edges {
        edgesMap[e.from, default: []].append(e.to)
    }
    var past = Set<String>()
    var queue = [latestHex]
    while !queue.isEmpty {
        let v = queue.removeFirst()
        guard !past.contains(v) else { continue }
        past.insert(v)
        for cause in edgesMap[v] ?? [] where !past.contains(cause) {
            queue.append(cause)
        }
    }

    // Limit to 60 vertices
    let vsByHex = Dictionary(uniqueKeysWithValues: ns.vertices.map { ($0.digestHex, $0) })
    if past.count > 60 {
        let sorted = past.sorted { (vsByHex[$0]?.round ?? 0) > (vsByHex[$1]?.round ?? 0) }
        past = Set(sorted.prefix(60))
        past.insert(latestHex)
    }

    let kahnVertices = past.reduce(into: [String: VertexData]()) { dict, h in
        if let v = vsByHex[h] { dict[h] = v }
    }
    let kahnEdges = ns.edges.filter { past.contains($0.from) && past.contains($0.to) }

    // Run Kahn's algorithm
    var outEdges: [String: Set<String>] = past.reduce(into: [:]) { $0[$1] = [] }
    var reverse: [String: Set<String>] = past.reduce(into: [:]) { $0[$1] = [] }
    for e in kahnEdges {
        outEdges[e.from, default: []].insert(e.to)
        reverse[e.to, default: []].insert(e.from)
    }

    var ordered = Set<String>()
    var position = 0
    var steps: [KahnStep] = []

    var available = past.filter { (outEdges[$0] ?? []).isEmpty }
        .sorted { (kahnVertices[$0]?.weight ?? 0) > (kahnVertices[$1]?.weight ?? 0) }

    while !available.isEmpty {
        let chosen = available.removeFirst()
        let vs = kahnVertices[chosen]
        let pname = pidToName[vs?.processIdHex ?? ""] ?? "?"

        steps.append(KahnStep(
            available: available,
            chosen: chosen,
            chosenWeight: vs?.weight ?? 0,
            position: position,
            payload: String((vs?.payloadStr ?? "").prefix(30)),
            processName: pname
        ))

        ordered.insert(chosen)
        position += 1

        var newly: [String] = []
        for referrer in reverse[chosen] ?? [] where !ordered.contains(referrer) {
            outEdges[referrer]?.remove(chosen)
            if (outEdges[referrer] ?? []).isEmpty {
                newly.append(referrer)
            }
        }
        available.append(contentsOf: newly)
        available.sort { (kahnVertices[$0]?.weight ?? 0) > (kahnVertices[$1]?.weight ?? 0) }
    }

    return (steps, kahnVertices, kahnEdges, latestHex,
            leaderNames[latestRound] ?? "", latestRound)
}
