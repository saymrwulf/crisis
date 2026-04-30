import SwiftUI

/// Loads crisis_data.json once and provides data to all renderers.
@Observable
final class DataManager {
    private(set) var sim: SimulationData?
    private(set) var isLoaded = false

    /// Node colors keyed by processIdHex
    private(set) var nodeColors: [String: Color] = [:]

    /// Node names keyed by processIdHex
    private(set) var nodeNames: [String: String] = [:]

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
        for (i, node) in data.nodes.enumerated() {
            nodeColors[node.processIdHex] = Self.palette[min(i, Self.palette.count - 1)]
            nodeNames[node.processIdHex] = node.name
        }
    }

    /// Get color index for a processIdHex
    func colorIndex(for processIdHex: String) -> Int {
        guard let sim else { return 0 }
        return sim.nodes.firstIndex(where: { $0.processIdHex == processIdHex }) ?? 0
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
