import SwiftUI

/// Loads crisis_data.json once and provides data to all renderers.
@Observable
final class DataManager {
    private(set) var sim: SimulationData?
    private(set) var isLoaded = false

    /// Node colors keyed by processIdHex
    private(set) var nodeColors: [String: Color] = [:]

    /// Node names keyed by processIdHex (display names, e.g. "Aaron").
    /// We deliberately overwrite the simulation's "honest-0/byzantine-0"
    /// names with the cast names here so every existing call site that
    /// renders `nodeNames[pid]` automatically picks up the new naming.
    private(set) var nodeNames: [String: String] = [:]

    /// Persistent cast assignment built at load time. See `Cast.swift`.
    private(set) var castByPid: [String: CastRole] = [:]

    // Palette: distinct colors for up to 9 nodes
    static let palette: [Color] = [
        Color(red: 0.30, green: 0.69, blue: 0.94),  // cyan-blue
        Color(red: 0.35, green: 0.85, blue: 0.55),  // green
        Color(red: 0.95, green: 0.60, blue: 0.20),  // orange
        Color(red: 0.80, green: 0.40, blue: 0.90),  // purple
        Color(red: 0.95, green: 0.45, blue: 0.45),  // red-pink
        Color(red: 0.55, green: 0.80, blue: 0.30),  // lime
        Color(red: 0.40, green: 0.60, blue: 0.95),  // blue
        Color(red: 0.90, green: 0.75, blue: 0.30),  // gold
        Color(red: 0.85, green: 0.30, blue: 0.30),  // byzantine red
    ]

    static let paletteCG: [CGColor] = palette.map { c in
        // Extract RGB components
        let ns = NSColor(c)
        return CGColor(red: CGFloat(ns.redComponent),
                       green: CGFloat(ns.greenComponent),
                       blue: CGFloat(ns.blueComponent),
                       alpha: 1.0)
    }

    func load() {
        guard sim == nil else { return }
        // Try bundle resource first, then working directory
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "crisis_data", withExtension: "json"),
            Bundle.module.url(forResource: "crisis_data", withExtension: "json"),
            Bundle.main.resourceURL?.appendingPathComponent("crisis_data.json"),
            URL(fileURLWithPath: "crisis_data.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("crisis_data.json"),
            // Fallback: relative to source during development
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/CrisisViz/crisis_data.json"),
        ]
        for candidate in candidates {
            guard let url = candidate, FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let data = try SimulationData.load(from: url)
                self.sim = data
                buildLookups(data)
                self.isLoaded = true
                return
            } catch {
                print("Failed to load crisis_data.json: \(error)")
            }
        }
        print("crisis_data.json not found")
    }

    private func buildLookups(_ data: SimulationData) {
        // Cast assignment is the source of truth for both name and color now.
        // The legacy palette is kept on the type for any non-cast call site
        // that still indexes into it.
        let cast = Cast.buildAssignment(nodes: data.nodes)
        castByPid = cast
        for node in data.nodes {
            let role = cast[node.processIdHex]
            nodeColors[node.processIdHex] = role?.color ?? Cast.muted
            nodeNames[node.processIdHex]  = role?.displayName ?? node.name
        }
    }

    /// Get color index for a processIdHex
    func colorIndex(for processIdHex: String) -> Int {
        guard let sim else { return 0 }
        return sim.nodes.firstIndex(where: { $0.processIdHex == processIdHex }) ?? 0
    }

    /// Cast lookup: the named role this validator plays in the story.
    /// Returns a muted "Peer-N" placeholder for unknown PIDs so callers
    /// don't have to handle nil.
    func castRole(for processIdHex: String) -> CastRole {
        castByPid[processIdHex] ?? Cast.peer(0)
    }

    /// Direct color lookup that respects the cast assignment.
    /// Prefer this over indexing into `palette` for any new code.
    func castColor(for processIdHex: String) -> Color {
        castByPid[processIdHex]?.color ?? Cast.muted
    }

    /// Lane index 0..3 for the four leads, or nil for muted peers.
    /// Used by the lane-and-rounds layout so every chapter places Aaron at
    /// lane 0, Ben at lane 1, Carl at lane 2, Dave at lane 3.
    func laneIndex(for processIdHex: String) -> Int? {
        guard let role = castByPid[processIdHex], role.isNamedCast else { return nil }
        return Cast.leads.firstIndex(where: { $0.id == role.id })
    }

    /// Nodes in cast lane order (Aaron → Ben → Carl → Dave) followed by any
    /// muted peers. Pass this into `DAGLayout.compute(...)`'s `nodes:`
    /// parameter so the layout's vertical ordering matches the CastSidebar
    /// — Dave ends up just below Carl rather than at the bottom of the
    /// list of seven simulation nodes.
    func castOrderedNodes() -> [NodeMeta] {
        guard let sim else { return [] }
        let pidToNode = Dictionary(uniqueKeysWithValues: sim.nodes.map { ($0.processIdHex, $0) })

        // Look up each cast lead by id, then by finding the pid assigned to that role.
        var ordered: [NodeMeta] = []
        var taken = Set<String>()
        for lead in Cast.leads {
            // First pid whose role.id == lead.id
            if let pid = castByPid.first(where: { $0.value.id == lead.id })?.key,
               let node = pidToNode[pid] {
                ordered.append(node)
                taken.insert(pid)
            }
        }
        // Append any remaining (muted peers, etc.) in their original order.
        for node in sim.nodes where !taken.contains(node.processIdHex) {
            ordered.append(node)
        }
        return ordered
    }

    /// Get snapshot for a given step (clamped)
    func snapshot(step: Int) -> StepSnapshot? {
        guard let sim else { return nil }
        let clamped = max(0, min(step, sim.steps.count - 1))
        return sim.steps[clamped]
    }

    /// Get first honest node's data for a step
    func honestData(step: Int) -> NodeSnapshot? {
        snapshot(step: step)?.firstHonestSnapshot
    }
}
