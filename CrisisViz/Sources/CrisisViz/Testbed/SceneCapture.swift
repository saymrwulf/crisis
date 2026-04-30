import SwiftUI
import AppKit

/// Time-scrubbing testbed: for every scene, capture the chapter view at multiple
/// `localTime` values. This is what makes animation regressions visible without
/// running the live app — the harness the user kept asking for.
///
/// Output layout:
///   ~/Desktop/CrisisViz_Testbed/
///     MANIFEST.md            — full grid index, one row per scene, columns for t∈timeOffsets
///     ch00_The_Problem/
///       scene00_t0.0s.png
///       scene00_t2.0s.png
///       scene00_t4.0s.png
///       scene00_t6.0s.png
///       scene00_t8.0s.png
///       ...
@MainActor
enum SceneCapture {
    static let outputDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/CrisisViz_Testbed")

    /// Time offsets to capture per scene (seconds since scene start).
    /// 0 = initial state, 8 = end of nominal scene duration. Add intermediate frames
    /// to catch animations that crash through their range or freeze before completion.
    static let timeOffsets: [Double] = [0.0, 2.0, 4.0, 6.0, 8.0]

    /// Inspector reveal frames — staggered across the recursive uncovering animation.
    /// 0s = root sealed, ~0.6s = root cracks, 1.5s = level 1 enters, 3.0s = level 2 enters,
    /// 4.5s = level 3 enters, 7.0s = full chain.
    static let inspectorTimeOffsets: [Double] = [0.0, 0.8, 1.6, 3.0, 4.5, 6.5]

    static func captureAll() async {
        let fm = FileManager.default
        try? fm.removeItem(at: outputDir)
        try? fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let size = CGSize(width: 1400, height: 900)
        let dm = DataManager()
        dm.load()
        let engine = SceneEngine()

        var captured = 0
        for (ci, chapter) in AllChapters.list.enumerated() {
            let chapterDir = outputDir.appendingPathComponent(chapterDirName(index: ci, title: chapter.title))
            try? fm.createDirectory(at: chapterDir, withIntermediateDirectories: true)

            for si in 0..<chapter.sceneCount {
                let address = SceneAddress(chapter: ci, scene: si)
                engine.goTo(global: address.globalIndex)

                for t in timeOffsets {
                    let view = SceneRouter(address: address, localTime: t, engine: engine, dm: dm)
                        .frame(width: size.width, height: size.height)
                        .background(.black)

                    let renderer = ImageRenderer(content: view)
                    renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
                    renderer.scale = 1.0

                    if let image = renderer.cgImage {
                        let filename = String(format: "scene%02d_t%.1fs.png", si, t)
                        let url = chapterDir.appendingPathComponent(filename)
                        savePNG(image: image, to: url)
                        captured += 1
                    }
                }
            }
        }

        let inspectorCaptured = await captureInspectorReveal(dm: dm, size: size)

        writeManifest(
            size: size,
            dataLoaded: dm.isLoaded,
            captured: captured,
            inspectorCaptured: inspectorCaptured
        )

        print("✓ Captured \(captured) scene frames + \(inspectorCaptured) inspector frames")
        print("  Output: \(outputDir.path)")
    }

    // MARK: - Inspector reveal harness

    /// Capture the recursive vertex-inspection overlay at successive time offsets,
    /// for a few representative vertices (early, middle, late round). Lets the
    /// human eye verify the seal/crack/parent-chain animation works end-to-end.
    static func captureInspectorReveal(dm: DataManager, size: CGSize) async -> Int {
        guard let snap = dm.honestData(step: 9) else {
            print("⚠ Inspector capture skipped: no snapshot available")
            return 0
        }

        let inspectorDir = outputDir.appendingPathComponent("inspector_vertex_reveal")
        try? FileManager.default.createDirectory(at: inspectorDir, withIntermediateDirectories: true)

        // Pick vertices at increasing depth so we can see GENESIS, mid-graph, and a
        // recent leaf with full ancestor chain.
        let sortedByRound = snap.vertices.sorted { $0.round < $1.round }
        var picks: [(label: String, vertex: VertexData)] = []
        if let v = sortedByRound.last { picks.append(("late_round\(v.round)", v)) }
        if let mid = sortedByRound.first(where: { $0.round == max(0, (sortedByRound.last?.round ?? 0) / 2) }) {
            picks.append(("mid_round\(mid.round)", mid))
        }
        if let early = sortedByRound.first(where: { $0.round == 1 }) ?? sortedByRound.first {
            picks.append(("early_round\(early.round)", early))
        }

        var captured = 0
        for pick in picks {
            let state = InspectionState()
            state.select(pick.vertex.digestHex)
            for t in inspectorTimeOffsets {
                let view = VertexInspector(state: state, dm: dm, localTime: t, onDismiss: {})
                    .frame(width: size.width, height: size.height)
                    .background(.black)

                let renderer = ImageRenderer(content: view)
                renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
                renderer.scale = 1.0

                if let image = renderer.cgImage {
                    let safeLabel = pick.label.replacingOccurrences(of: " ", with: "_")
                    let filename = String(format: "%@_t%.1fs.png", safeLabel, t)
                    let url = inspectorDir.appendingPathComponent(filename)
                    savePNG(image: image, to: url)
                    captured += 1
                }
            }
        }
        return captured
    }

    // MARK: - Manifest

    private static func writeManifest(
        size: CGSize,
        dataLoaded: Bool,
        captured: Int,
        inspectorCaptured: Int
    ) {
        var m = "# CrisisViz Testbed (Time-Scrubbing)\n\n"
        m += "Scene frames: \(captured) (\(AllChapters.totalScenes) scenes × \(timeOffsets.count) time offsets)\n"
        m += "Inspector reveal frames: \(inspectorCaptured)\n"
        m += "Resolution: \(Int(size.width))×\(Int(size.height))\n"
        m += "Data loaded: \(dataLoaded)\n"
        m += "Scene time offsets: \(timeOffsets.map { String(format: "%.1fs", $0) }.joined(separator: ", "))\n"
        m += "Inspector time offsets: \(inspectorTimeOffsets.map { String(format: "%.1fs", $0) }.joined(separator: ", "))\n\n"

        m += "## How to read\n"
        m += "Each scene was rendered at \(timeOffsets.count) time offsets, simulating the animation\n"
        m += "across its 8s nominal duration. Compare adjacent frames to detect:\n"
        m += "- Animations that freeze at t=0 or t=8 (broken time wiring)\n"
        m += "- Layout that jumps between frames (positions depend on time)\n"
        m += "- Captions/data that contradict the visual (audit failures)\n\n"

        m += "## Quality Checklist (chapters)\n"
        m += "- [ ] Every chapter shows visible motion across t∈[0, 8] frames\n"
        m += "- [ ] No scene has all 5 frames identical (broken animation)\n"
        m += "- [ ] No scene has wildly different layouts at adjacent frames (jump)\n"
        m += "- [ ] In-canvas captions match the rendered visual (no number lies)\n"
        m += "- [ ] Glass narration panel doesn't duplicate in-canvas text\n"
        m += "- [ ] Edges visible (alpha >= 0.3, lineWidth >= 1.2)\n"
        m += "- [ ] Font sizes readable (min 10pt for labels, 11pt for captions)\n"
        m += "- [ ] Ch02 shows the \"CLICK ANY VERTEX TO INSPECT\" hint in scenes 1+\n\n"

        m += "## Quality Checklist (inspector reveal)\n"
        m += "Folder `inspector_vertex_reveal/` contains the recursive hash-unwrapping\n"
        m += "animation captured at successive time offsets, for several seed vertices.\n"
        m += "- [ ] Root card visible at t=0.0 (sealed) and at t=0.8 (cracked open)\n"
        m += "- [ ] PAYLOAD pill shows a Tx string with ⇒ and amount\n"
        m += "- [ ] PARENT HASHES section lists 1-4 yellow chips with `→ 0x…` text\n"
        m += "- [ ] By t=1.6 parent cards are entering on the left of root\n"
        m += "- [ ] Yellow arrows connect root chips to parent cards\n"
        m += "- [ ] By t=4.5 a multi-level ancestor chain is visible (3+ depth columns)\n"
        m += "- [ ] At least one card shows ★ GENESIS · NO PRE-IMAGE ★ (round 0 reached)\n"
        m += "- [ ] Title bar at top reads \"KNOWLEDGE STATE OF VERTEX\" with origin/round\n"
        m += "- [ ] Layout is centered, no clipping at edges\n\n"

        for (ci, chapter) in AllChapters.list.enumerated() {
            m += "## Ch\(ci): \(chapter.title) (\(chapter.sceneCount) scenes)\n\n"
            for si in 0..<chapter.sceneCount {
                let title = SceneNarrations.title(chapter: ci, scene: si)
                m += "### Scene \(si): \"\(title)\"\n"
                let dir = chapterDirName(index: ci, title: chapter.title)
                for t in timeOffsets {
                    let filename = String(format: "scene%02d_t%.1fs.png", si, t)
                    m += "- t=\(String(format: "%.1f", t))s — `\(dir)/\(filename)`\n"
                }
                m += "\n"
            }
        }

        m += "## Inspector reveal (recursive hash unwrapping)\n\n"
        m += "Each seed vertex was captured at \(inspectorTimeOffsets.count) time offsets while\n"
        m += "the inspector animates: SEALED → CRACK → parent cards arrive → recursion to genesis.\n\n"
        m += "Compare frames within a row (same vertex, increasing t) to verify:\n"
        m += "- The seal cracks between t=0.0 and t=0.8\n"
        m += "- Parent cards stagger in at t≈1.6, t≈3.0, …\n"
        m += "- Yellow parent-hash arrows draw in concurrently with each level\n\n"

        let url = outputDir.appendingPathComponent("MANIFEST.md")
        try? m.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func chapterDirName(index: Int, title: String) -> String {
        let safe = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "—", with: "-")
            .prefix(25)
        return String(format: "ch%02d_%@", index, String(safe))
    }

    private static func savePNG(image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
