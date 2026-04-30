import Foundation

// MARK: - Top-level

struct SimulationData: Codable {
    let config: SimConfig
    let nodes: [NodeMeta]
    let steps: [StepSnapshot]
    let events: [String: [SimEvent]]  // step number (string) -> events

    func eventsForStep(_ step: Int) -> [SimEvent] {
        events[String(step)] ?? []
    }
}

struct SimConfig: Codable {
    let numHonest: Int
    let numByzantine: Int
    let numSteps: Int
    let powZeros: Int
    let difficulty: Int
    let connectivityK: Int
    let seed: Int

    var numTotal: Int { numHonest + numByzantine }
    var byzantineThreshold: Int { numTotal / 3 }
}

struct NodeMeta: Codable, Identifiable {
    let name: String
    let processIdHex: String
    let isByzantine: Bool

    var id: String { name }
}

// MARK: - Step Snapshot

struct StepSnapshot: Codable, Identifiable {
    let step: Int
    let convergence: Bool
    let agreedPrefixLength: Int
    let nodeSnapshots: [String: NodeSnapshot]

    var id: Int { step }

    var honestSnapshots: [NodeSnapshot] {
        nodeSnapshots.values.filter { !$0.isByzantine }.sorted { $0.name < $1.name }
    }

    var firstHonestSnapshot: NodeSnapshot? {
        honestSnapshots.first
    }
}

struct NodeSnapshot: Codable {
    let name: String
    let vertexCount: Int
    let maxRound: Int
    let numLeaders: Int
    let numOrdered: Int
    let isByzantine: Bool
    let vertices: [VertexData]
    let edges: [EdgeData]
    let leaderRounds: [String: String]  // round (string) -> leader digest hex

    func leaderForRound(_ round: Int) -> String? {
        leaderRounds[String(round)]
    }
}

struct VertexData: Codable, Identifiable {
    let digestHex: String
    let digestFull: String
    let processIdHex: String
    let roundNumber: Int?
    let isLast: Bool
    let weight: Int
    let payloadStr: String
    let totalPosition: Int?
    let isByzantineSource: Bool

    var id: String { digestHex }
    var round: Int { roundNumber ?? 0 }
}

struct EdgeData: Codable {
    let from: String
    let to: String
}

// MARK: - Events

struct SimEvent: Codable, Identifiable {
    let seq: Int
    let type: String
    let nodeName: String
    let data: [String: AnyCodable]

    var id: Int { seq }

    func string(_ key: String) -> String {
        data[key]?.stringValue ?? ""
    }

    func int(_ key: String) -> Int {
        data[key]?.intValue ?? 0
    }

    func bool(_ key: String) -> Bool {
        data[key]?.boolValue ?? false
    }
}

// MARK: - AnyCodable helper

struct AnyCodable: Codable {
    let value: Any

    var stringValue: String { value as? String ?? "" }
    var intValue: Int { value as? Int ?? 0 }
    var boolValue: Bool { value as? Bool ?? false }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if container.decodeNil() { value = "" }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? Bool { try container.encode(v) }
        else if let v = value as? Int { try container.encode(v) }
        else if let v = value as? Double { try container.encode(v) }
        else if let v = value as? String { try container.encode(v) }
        else { try container.encodeNil() }
    }
}

// MARK: - Loading

extension SimulationData {
    static func load(from url: URL) throws -> SimulationData {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SimulationData.self, from: data)
    }
}
