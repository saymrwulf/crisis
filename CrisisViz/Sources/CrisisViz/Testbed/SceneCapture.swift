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

    /// Convergence playback time slices — captures each of the four narrated steps
    /// in mid-bloom plus the final stamp. Step boundaries: 1.6 / 3.4 / 5.4 seconds.
    /// Slices: mid-S1, end-S1, mid-S2, mid-S3, mid-S4 (entering stamp), late-S4 (stamp settled).
    static let convergenceTimeOffsets: [Double] = [0.4, 1.4, 2.4, 4.2, 5.6, 7.0]

    /// Fine-grained convergence slicing for animation regression detection.
    /// Hits every visible phase at multiple points so a frozen interpolator or
    /// missed easing curve becomes obvious in adjacent frames.
    static let convergenceFineOffsets: [Double] = [
        0.0, 0.4, 0.8, 1.2, 1.5,           // Step 1
        1.8, 2.2, 2.6, 3.0, 3.3,           // Step 2
        3.6, 3.9, 4.2, 4.5, 4.8, 5.1, 5.3, // Step 3 (kinetic snap)
        5.6, 6.2, 6.8, 7.5                  // Step 4
    ]

    /// Text scales to verify slider end-to-end coverage. The middle entry is the
    /// "default" so it's the baseline; the extremes catch text that bypasses
    /// `settings.scaled(_:)` (which is the bug we keep regressing on).
    static let textScalesToCapture: [Double] = [0.85, 1.0, 1.6]

    /// Full ladder of text scales for the comparison view — exercises every
    /// notch of the slider, not just the extremes.
    static let textScaleLadder: [Double] = [0.85, 1.0, 1.15, 1.30, 1.45, 1.60]

    /// Canvas sizes that simulate the rendered output of the app at common
    /// window sizes. Includes "snapped to half-screen" (1280x800), default
    /// (1400x900), full-HD, and ultrawide. Layout regressions caused by window
    /// resize (cards overflowing, captions clipped, divider misaligned) become
    /// visible by comparing the same view across this matrix.
    static let canvasSizeMatrix: [(CGFloat, CGFloat, String)] = [
        ( 800,  600,  "tiny_800x600"),         // smallest reasonable window
        (1024,  768,  "compact_1024x768"),     // half of older iMacs
        (1280,  800,  "laptop_1280x800"),      // common laptop snap-half
        (1400,  900,  "default_1400x900"),     // app's default
        (1680, 1050,  "desktop_1680x1050"),    // typical external display
        (1920, 1080,  "fullhd_1920x1080"),     // Full-HD
        (2560, 1440,  "ultrawide_2560x1440")   // QHD / ultrawide
    ]

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

                // Per-scene time offsets: extended scenes (e.g. the Ch1.3
                // gossip dramatization) need more samples across their
                // longer duration to capture each pedagogical beat.
                let offsetsForThisScene: [Double]
                if address == SceneAddress(chapter: 1, scene: 3) {
                    offsetsForThisScene = [0.5, 4.0, 8.0, 12.0, 16.0, 20.0, 23.0]
                } else {
                    offsetsForThisScene = timeOffsets
                }
                for t in offsetsForThisScene {
                    let settings = AppSettings()
                    let view = SceneRouter(address: address, localTime: t, engine: engine, dm: dm)
                        .environment(settings)
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
        let comparisonCaptured = await captureComparisonAndConvergence(dm: dm, size: size)
        let comparisonAtSizesCount = await captureComparisonAtAllSizes(dm: dm)
        let comparisonAtScalesCount = await captureComparisonAtAllScales(dm: dm, size: size)
        let convergenceFineCount = await captureConvergenceFineGrained(dm: dm, size: size)
        let inspectorScalesCount = await captureInspectorAtAllScales(dm: dm, size: size)

        let totalNew = comparisonAtSizesCount + comparisonAtScalesCount + convergenceFineCount + inspectorScalesCount

        writeManifest(
            size: size,
            dataLoaded: dm.isLoaded,
            captured: captured,
            inspectorCaptured: inspectorCaptured,
            comparisonCaptured: comparisonCaptured,
            extendedCaptured: totalNew
        )

        // Sanity check: scan every comparison frame for non-trivial content
        // (catch the "rendered all-black" regression) and any frame too similar
        // to its neighbor (catch the "convergence didn't fire" regression).
        let sanityReport = runSanityChecks()

        // ─── Dynamic harness ─────────────────────────────────────────────
        // Three additional layers PNG sweeps cannot provide:
        //   1. Narrative invariants: code-level claims about cast assignment,
        //      lifeline geometry, per-chapter staging. Catches "Carl appears
        //      before Ben" and similar logical fallacies.
        //   2. Source audit: forbidden patterns (palette[i], hardcoded honest
        //      PIDs, Y-jitter). Catches silent regressions that don't crash.
        //   3. Per-scene MP4 video clips: the only way to verify animation
        //      continuity without running the live app.
        let invariantReport = NarrativeInvariants.runAll(dm: dm)
        NarrativeInvariants.writeReport(invariantReport,
            to: outputDir.appendingPathComponent("INVARIANTS.md"))

        let auditReport = SourceAudit.runAudit()
        SourceAudit.writeReport(auditReport,
            to: outputDir.appendingPathComponent("SOURCE_AUDIT.md"))

        let videoClips = await SceneVideoCapture.captureAll(dm: dm, outputDir: outputDir)
        SceneVideoCapture.writeReport(videoClips,
            to: outputDir.appendingPathComponent("VIDEO_CLIPS.md"))

        print("✓ Captured \(captured) scene + \(inspectorCaptured) inspector + \(comparisonCaptured) comparison + \(totalNew) extended frames")
        print("  Sanity: \(sanityReport)")
        print("  Invariants: \(invariantReport.summary) (\(invariantReport.failed) failed)")
        print("  Source audit: \(auditReport.errorCount) errors, \(auditReport.warnCount) warnings across \(auditReport.scanned) files")
        print("  Video clips: \(videoClips.filter(\.succeeded).count)/\(videoClips.count) MP4 written")
        print("  Output: \(outputDir.path)")
    }

    // MARK: - Inspector reveal harness

    /// Capture the recursive vertex-inspection overlay at successive time offsets,
    /// for a few representative vertices (early, middle, late round). Lets the
    /// human eye verify the seal/crack/parent-chain animation works end-to-end.
    static func captureInspectorReveal(dm: DataManager, size: CGSize) async -> Int {
        // Use a late step so the graph has rich ancestor chains to walk.
        guard let snap = dm.honestData(step: 30) else {
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
                let settings = AppSettings()
                let view = VertexInspector(state: state, dm: dm, localTime: t, onDismiss: {})
                    .environment(settings)
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

    // MARK: - Comparison + convergence harness
    //
    // This is the missing capture path that let the convergence playback ship
    // unverified. Captures three things:
    //   1. Static side-by-side comparison at THREE text scales (0.85 / 1.0 / 1.6).
    //   2. Convergence playback at six time slices spanning all four steps.
    //   3. (3) is at default text scale only — the goal is animation correctness,
    //      not slider coverage (which is in the static set).
    static func captureComparisonAndConvergence(dm: DataManager, size: CGSize) async -> Int {
        guard let snap = dm.honestData(step: 30) else {
            print("⚠ Comparison capture skipped: no snapshot available")
            return 0
        }

        // Pick A and B such that they're contemporary AND their depth-3 ancestor
        // cones provably share at least one vertex — otherwise the convergence
        // playback has nothing to converge on and renders identical to static.
        // We do an explicit BFS check here so the testbed can't silently capture
        // a non-converging pair.
        var parentMap: [String: [String]] = [:]
        for e in snap.edges { parentMap[e.from, default: []].append(e.to) }
        func cone(_ root: VertexData, depth: Int = 3) -> Set<String> {
            var seen: Set<String> = [root.digestHex]
            var frontier: [String] = [root.digestHex]
            for _ in 0..<depth {
                var next: [String] = []
                for d in frontier {
                    for p in (parentMap[d] ?? []).prefix(3) where !seen.contains(p) {
                        seen.insert(p); next.append(p)
                    }
                }
                if next.isEmpty { break }
                frontier = next
            }
            return seen
        }

        let lateRound = snap.vertices.map(\.round).max() ?? 0
        // Search the top few rounds for a (A, B) pair from different nodes whose
        // cones share at least 2 ancestors (so convergence is non-trivial).
        var rootA: VertexData?
        var rootB: VertexData?
        outer: for r in stride(from: lateRound, through: max(0, lateRound - 2), by: -1) {
            let candidates = snap.vertices.filter { $0.round == r }
            for a in candidates {
                let coneA = cone(a)
                for b in candidates where b.processIdHex != a.processIdHex && b.digestHex != a.digestHex {
                    let coneB = cone(b)
                    if coneA.intersection(coneB).count >= 2 {
                        rootA = a; rootB = b
                        break outer
                    }
                }
            }
        }
        guard let rootA, let rootB else {
            print("⚠ Comparison capture: no converging pair found in top 3 rounds")
            return 0
        }
        print("  comparison: A=\(String(rootA.digestHex.prefix(10)))(R\(rootA.round)) ↔ B=\(String(rootB.digestHex.prefix(10)))(R\(rootB.round))")

        let dir = outputDir.appendingPathComponent("comparison_convergence")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var captured = 0

        // ── (1) Static comparison at three text scales ───────────────────
        for scale in textScalesToCapture {
            let state = InspectionState()
            state.select(rootA.digestHex)
            state.setCompare(rootB.digestHex)
            let settings = AppSettings()
            settings.textScale = scale
            // Render at a fixed localTime well past the recursive reveal so all
            // cards are open and visible.
            let view = VertexInspector(
                state: state, dm: dm, localTime: 8.0,
                convergenceTime: 0,
                onDismiss: {}
            )
            .environment(settings)
            .frame(width: size.width, height: size.height)
            .background(.black)

            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
            renderer.scale = 1.0
            if let image = renderer.cgImage {
                let filename = String(format: "static_comparison_textScale%.2f.png", scale)
                let url = dir.appendingPathComponent(filename)
                savePNG(image: image, to: url)
                captured += 1
            }
        }

        // ── (2) Convergence playback at every time slice ─────────────────
        for ct in convergenceTimeOffsets {
            let state = InspectionState()
            state.select(rootA.digestHex)
            state.setCompare(rootB.digestHex)
            state.playConvergence()
            let settings = AppSettings()
            settings.textScale = 1.0
            let view = VertexInspector(
                state: state, dm: dm, localTime: 8.0,
                convergenceTime: ct,
                onDismiss: {}
            )
            .environment(settings)
            .frame(width: size.width, height: size.height)
            .background(.black)

            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
            renderer.scale = 1.0
            if let image = renderer.cgImage {
                let stepHint: String
                switch ct {
                case ..<1.6: stepHint = "step1"
                case ..<3.4: stepHint = "step2"
                case ..<5.4: stepHint = "step3"
                default:     stepHint = "step4"
                }
                let filename = String(format: "convergence_%@_t%.1fs.png", stepHint, ct)
                let url = dir.appendingPathComponent(filename)
                savePNG(image: image, to: url)
                captured += 1
            }
        }

        return captured
    }

    // MARK: - Smart pair-picker (shared by every comparison capture)

    /// Find two vertices A, B from different validators whose depth-3 ancestor
    /// cones share at least 2 vertices. Returns nil only when the snapshot is
    /// too sparse to contain any converging pair (in practice never happens
    /// for the bundled honest run).
    private static func pickConvergingPair(snap: NodeSnapshot) -> (VertexData, VertexData)? {
        var parentMap: [String: [String]] = [:]
        for e in snap.edges { parentMap[e.from, default: []].append(e.to) }
        func cone(_ root: VertexData, depth: Int = 3) -> Set<String> {
            var seen: Set<String> = [root.digestHex]
            var frontier: [String] = [root.digestHex]
            for _ in 0..<depth {
                var next: [String] = []
                for d in frontier {
                    for p in (parentMap[d] ?? []).prefix(3) where !seen.contains(p) {
                        seen.insert(p); next.append(p)
                    }
                }
                if next.isEmpty { break }
                frontier = next
            }
            return seen
        }
        let lateRound = snap.vertices.map(\.round).max() ?? 0
        for r in stride(from: lateRound, through: max(0, lateRound - 2), by: -1) {
            let candidates = snap.vertices.filter { $0.round == r }
            for a in candidates {
                let coneA = cone(a)
                for b in candidates where b.processIdHex != a.processIdHex && b.digestHex != a.digestHex {
                    let coneB = cone(b)
                    if coneA.intersection(coneB).count >= 2 {
                        return (a, b)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Extended capture: window resize / scale ladder / fine convergence

    /// Render the comparison view at every entry in `canvasSizeMatrix`. Catches
    /// regressions where cards bleed off the edge, captions clip, or the
    /// divider misaligns when the window is snapped/resized to a different
    /// aspect ratio. Three frames per size: static, snap (step3), stamp (step4).
    static func captureComparisonAtAllSizes(dm: DataManager) async -> Int {
        guard let snap = dm.honestData(step: 30),
              let pair = pickConvergingPair(snap: snap) else {
            print("⚠ Window-size sweep skipped: no converging pair")
            return 0
        }
        let dir = outputDir.appendingPathComponent("resize_window_sweep")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var captured = 0
        for (w, h, label) in canvasSizeMatrix {
            let size = CGSize(width: w, height: h)
            // Static comparison
            captured += renderComparisonFrame(
                dm: dm, pair: pair, size: size, scale: 1.0,
                convergenceTime: 0,
                fileURL: dir.appendingPathComponent("\(label)_static.png")
            )
            // Step 3 mid-snap (kinetic motion in flight)
            captured += renderComparisonFrame(
                dm: dm, pair: pair, size: size, scale: 1.0,
                convergenceTime: 4.5,
                fileURL: dir.appendingPathComponent("\(label)_snap_t4.5.png")
            )
            // Step 4 stamp settled
            captured += renderComparisonFrame(
                dm: dm, pair: pair, size: size, scale: 1.0,
                convergenceTime: 7.0,
                fileURL: dir.appendingPathComponent("\(label)_stamp_t7.0.png")
            )
        }
        return captured
    }

    /// Render the comparison view at every notch of the text-scale slider.
    /// Catches text that bypasses `settings.scaled(_:)` and overflows cards at
    /// extreme scales (the recurring textScale regression).
    static func captureComparisonAtAllScales(dm: DataManager, size: CGSize) async -> Int {
        guard let snap = dm.honestData(step: 30),
              let pair = pickConvergingPair(snap: snap) else {
            print("⚠ Scale-ladder sweep skipped: no converging pair")
            return 0
        }
        let dir = outputDir.appendingPathComponent("textscale_ladder_sweep")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var captured = 0
        for scale in textScaleLadder {
            // Static
            captured += renderComparisonFrame(
                dm: dm, pair: pair, size: size, scale: scale,
                convergenceTime: 0,
                fileURL: dir.appendingPathComponent(String(format: "scale%.2f_static.png", scale))
            )
            // Mid-snap
            captured += renderComparisonFrame(
                dm: dm, pair: pair, size: size, scale: scale,
                convergenceTime: 4.5,
                fileURL: dir.appendingPathComponent(String(format: "scale%.2f_snap_t4.5.png", scale))
            )
            // Stamp
            captured += renderComparisonFrame(
                dm: dm, pair: pair, size: size, scale: scale,
                convergenceTime: 7.0,
                fileURL: dir.appendingPathComponent(String(format: "scale%.2f_stamp_t7.0.png", scale))
            )
        }
        return captured
    }

    /// Fine-grained slicing of the convergence playback. Adjacent frames in
    /// this folder should differ visibly; if two are byte-identical that's a
    /// frozen interpolator (the failure mode we keep hitting).
    static func captureConvergenceFineGrained(dm: DataManager, size: CGSize) async -> Int {
        guard let snap = dm.honestData(step: 30),
              let pair = pickConvergingPair(snap: snap) else {
            print("⚠ Convergence fine-grain skipped: no converging pair")
            return 0
        }
        let dir = outputDir.appendingPathComponent("convergence_fine_grained")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var captured = 0
        for ct in convergenceFineOffsets {
            let stepHint: String
            switch ct {
            case ..<1.6: stepHint = "step1"
            case ..<3.4: stepHint = "step2"
            case ..<5.4: stepHint = "step3"
            default:     stepHint = "step4"
            }
            let filename = String(format: "%@_t%.2fs.png", stepHint, ct)
            captured += renderComparisonFrame(
                dm: dm, pair: pair, size: size, scale: 1.0,
                convergenceTime: ct,
                fileURL: dir.appendingPathComponent(filename)
            )
        }
        return captured
    }

    /// Single-vertex inspector at every text-scale notch × two reveal phases
    /// (early crack and full-chain). Catches the same scale regressions as the
    /// comparison sweep but for the simpler one-vertex path.
    static func captureInspectorAtAllScales(dm: DataManager, size: CGSize) async -> Int {
        guard let snap = dm.honestData(step: 30) else {
            print("⚠ Inspector scale sweep skipped: no snapshot")
            return 0
        }
        // A late-round vertex with the deepest ancestor chain we can find.
        guard let root = snap.vertices.sorted(by: { $0.round > $1.round }).first else {
            return 0
        }
        let dir = outputDir.appendingPathComponent("inspector_textscale_sweep")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var captured = 0
        for scale in textScaleLadder {
            for t in [1.6, 6.5] {  // crack-open + fully revealed
                let state = InspectionState()
                state.select(root.digestHex)
                let settings = AppSettings()
                settings.textScale = scale
                let view = VertexInspector(state: state, dm: dm, localTime: t, onDismiss: {})
                    .environment(settings)
                    .frame(width: size.width, height: size.height)
                    .background(.black)
                let renderer = ImageRenderer(content: view)
                renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
                renderer.scale = 1.0
                if let image = renderer.cgImage {
                    let filename = String(format: "scale%.2f_t%.1fs.png", scale, t)
                    let url = dir.appendingPathComponent(filename)
                    savePNG(image: image, to: url)
                    captured += 1
                }
            }
        }
        return captured
    }

    /// Internal helper used by every comparison sweep above. Renders one
    /// VertexInspector frame in convergence-playback mode at the given size,
    /// scale, and `convergenceTime`. Returns 1 on success, 0 on render failure.
    private static func renderComparisonFrame(
        dm: DataManager,
        pair: (VertexData, VertexData),
        size: CGSize,
        scale: Double,
        convergenceTime: Double,
        fileURL: URL
    ) -> Int {
        let state = InspectionState()
        state.select(pair.0.digestHex)
        state.setCompare(pair.1.digestHex)
        if convergenceTime > 0 { state.playConvergence() }
        let settings = AppSettings()
        settings.textScale = scale
        let view = VertexInspector(
            state: state, dm: dm, localTime: 8.0,
            convergenceTime: convergenceTime,
            onDismiss: {}
        )
        .environment(settings)
        .frame(width: size.width, height: size.height)
        .background(.black)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = 1.0
        guard let image = renderer.cgImage else { return 0 }
        savePNG(image: image, to: fileURL)
        return 1
    }

    // MARK: - Sanity checks (programmatic regression detection)

    /// Walk every PNG under the output directory and flag two failure modes:
    ///   1. **Identical-size groups** in animation folders → frozen interpolator
    ///      or stuck animation (adjacent frames should differ).
    ///   2. **Suspiciously small files** (< 8 KB) → all-black or empty render.
    /// Returns a one-line summary suitable for stdout, plus writes a longer
    /// `SANITY.md` report into the output directory.
    static func runSanityChecks() -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: outputDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "FAIL: enumerator could not open \(outputDir.path)"
        }
        struct Frame {
            let url: URL
            let size: Int
            let folder: String
        }
        var frames: [Frame] = []
        for case let url as URL in enumerator where url.pathExtension == "png" {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int) ?? 0
            let folder = url.deletingLastPathComponent().lastPathComponent
            frames.append(Frame(url: url, size: size, folder: folder))
        }
        var report = "# CrisisViz Testbed Sanity Report\n\n"
        report += "Total PNGs: \(frames.count)\n\n"

        // Tiny-file flag: anything under 8 KB is almost certainly broken.
        let tiny = frames.filter { $0.size < 8 * 1024 }
        report += "## Suspiciously small files (< 8 KB)\n"
        if tiny.isEmpty {
            report += "_None._\n\n"
        } else {
            for f in tiny {
                report += "- `\(f.folder)/\(f.url.lastPathComponent)` — \(f.size) bytes\n"
            }
            report += "\n"
        }

        // Identical-size groups within animation folders. Two failure modes:
        //   - REAL FREEZE: 3+ identical frames clustered in the EARLY/MID portion
        //     of the timeline → broken interpolator.
        //   - SETTLED PLATEAU: 3+ identical frames at the END of the timeline →
        //     animation correctly reached its final state and held there.
        // We separate these by extracting the numeric `t<value>s` suffix from
        // each filename, sorting by it, and asking: does the identical group
        // include the very last frame? If yes, it's a plateau (informational).
        // If no, it's a real freeze (warning).
        let animationFolders: Set<String> = [
            "convergence_fine_grained",
            "comparison_convergence",
            "inspector_vertex_reveal",
            "inspector_textscale_sweep"
        ]
        struct AnimGroup { let folder, key: String; let size: Int; let files: [String] }
        var frozenMid: [AnimGroup] = []
        var settledTail: [AnimGroup] = []

        // Extract `_t<value>s` from a filename — returns nil for non-time-keyed.
        func timeOf(_ filename: String) -> Double? {
            guard let tRange = filename.range(of: #"_t([0-9]+\.[0-9]+)s"#, options: .regularExpression) else { return nil }
            let s = filename[tRange].dropFirst(2).dropLast()  // strip "_t" and "s"
            return Double(s)
        }
        // Group key (everything before "_t<n>s") so we don't compare across
        // different seed vertices / scales / sizes.
        func keyOf(_ filename: String) -> String {
            if let r = filename.range(of: #"_t[0-9]+\.[0-9]+s\.png$"#, options: .regularExpression) {
                return String(filename[..<r.lowerBound])
            }
            return filename
        }

        for folder in animationFolders {
            let group = frames.filter { $0.folder == folder }
            // Bucket by (animation key, byte size). A bucket with 3+ members
            // means those frames are byte-identical for the same animation.
            var byKey: [String: [Frame]] = [:]
            for f in group { byKey[keyOf(f.url.lastPathComponent), default: []].append(f) }
            for (animKey, members) in byKey {
                let sortedByTime = members.sorted {
                    (timeOf($0.url.lastPathComponent) ?? 0) < (timeOf($1.url.lastPathComponent) ?? 0)
                }
                let lastFile = sortedByTime.last?.url.lastPathComponent
                let bySize = Dictionary(grouping: members, by: \.size)
                for (sz, sameSize) in bySize where sameSize.count >= 3 {
                    let names = sameSize.map(\.url.lastPathComponent).sorted()
                    let touchesEnd = names.contains(lastFile ?? "")
                    let g = AnimGroup(folder: folder, key: animKey, size: sz, files: names)
                    if touchesEnd { settledTail.append(g) } else { frozenMid.append(g) }
                }
            }
        }
        report += "## Real freezes (mid-animation, NOT touching end frame)\n"
        if frozenMid.isEmpty {
            report += "_None — every animation either varies or correctly settles at its end._\n\n"
        } else {
            for g in frozenMid {
                report += "- `\(g.folder)` / `\(g.key)` — \(g.files.count) files all \(g.size) bytes:\n"
                for f in g.files { report += "  - \(f)\n" }
            }
            report += "\n"
        }
        report += "## Settled-state plateaus (informational — animation correctly held final frame)\n"
        if settledTail.isEmpty {
            report += "_None._\n\n"
        } else {
            for g in settledTail {
                report += "- `\(g.folder)` / `\(g.key)` — \(g.files.count) frames at \(g.size) bytes:\n"
                for f in g.files { report += "  - \(f)\n" }
            }
            report += "\n"
        }

        // Per-folder size variance summary.
        report += "## Folder coverage\n"
        let byFolder = Dictionary(grouping: frames, by: \.folder)
        for folder in byFolder.keys.sorted() {
            let group = byFolder[folder] ?? []
            let sizes = group.map(\.size)
            let minSz = sizes.min() ?? 0
            let maxSz = sizes.max() ?? 0
            let avgSz = sizes.isEmpty ? 0 : sizes.reduce(0, +) / sizes.count
            report += "- `\(folder)`: \(group.count) PNGs, size \(minSz)…\(maxSz) bytes (avg \(avgSz))\n"
        }

        // Window-resize unit tests: verify CrisisAppDelegate.clampResize behaves
        // correctly across the size matrix that the user actually exercises
        // (tiny, normal, oversized, exactly screen-sized). This catches the
        // "drag snaps to top of screen and locks height" regression — the
        // root cause was an unbounded `windowWillResize` letting the window
        // push past the menu bar, which triggered macOS auto-tiling.
        let resizeReport = runWindowResizeUnitTests()
        report += "\n## Window resize clamp unit tests\n"
        report += resizeReport.body

        let url = outputDir.appendingPathComponent("SANITY.md")
        try? report.write(to: url, atomically: true, encoding: .utf8)

        let summary: String
        let baseOk = tiny.isEmpty && frozenMid.isEmpty
        if baseOk && resizeReport.failures == 0 {
            summary = "OK — \(frames.count) PNGs, no tiny files, no mid-animation freezes (\(settledTail.count) plateaus expected); window-resize \(resizeReport.passes)/\(resizeReport.passes + resizeReport.failures) pass"
        } else {
            summary = "WARN — \(tiny.count) tiny, \(frozenMid.count) freeze, \(settledTail.count) plateaus, \(resizeReport.failures) resize fail(s); see SANITY.md"
        }
        return summary
    }

    // MARK: - Window resize unit tests
    //
    // Pure-logic regression suite for `CrisisAppDelegate.clampResize`. We don't
    // (and can't) drive a real NSWindow drag from tests, but we CAN verify
    // every clamp invariant the live drag path depends on:
    //   - shrink below min → snaps to min
    //   - grow above visible screen → snaps to visible (prevents tiling)
    //   - exactly at min/max boundary → returned unchanged
    //   - nil screen (test harness) → no upper bound
    // Each row in the matrix is one assertion. The list both documents the
    // contract and gives the testbed something to fail loudly on.

    struct ResizeUnitReport {
        let passes: Int
        let failures: Int
        let body: String
    }

    static func runWindowResizeUnitTests() -> ResizeUnitReport {
        struct Case {
            let name: String
            let proposed: NSSize
            let visible: CGSize?
            let expected: NSSize
        }
        let visible1080 = CGSize(width: 1920, height: 1055)  // 1920x1080 minus menu bar ~25
        let visible1440 = CGSize(width: 2560, height: 1415)
        let cases: [Case] = [
            Case(name: "shrink below min width  → clamp to min",
                 proposed: NSSize(width: 400,  height: 800),
                 visible: visible1080,
                 expected: NSSize(width: 960,  height: 800)),
            Case(name: "shrink below min height → clamp to min",
                 proposed: NSSize(width: 1200, height: 300),
                 visible: visible1080,
                 expected: NSSize(width: 1200, height: 640)),
            Case(name: "shrink below both       → clamp both to min",
                 proposed: NSSize(width: 100,  height: 100),
                 visible: visible1080,
                 expected: NSSize(width: 960,  height: 640)),
            Case(name: "exactly at min          → unchanged",
                 proposed: NSSize(width: 960,  height: 640),
                 visible: visible1080,
                 expected: NSSize(width: 960,  height: 640)),
            Case(name: "normal mid-range size   → unchanged",
                 proposed: NSSize(width: 1400, height: 900),
                 visible: visible1080,
                 expected: NSSize(width: 1400, height: 900)),
            Case(name: "grow past screen width  → clamp to visible",
                 proposed: NSSize(width: 9999, height: 900),
                 visible: visible1080,
                 expected: NSSize(width: 1920, height: 900)),
            Case(name: "grow past screen height → clamp to visible (PREVENTS TILING)",
                 proposed: NSSize(width: 1400, height: 9999),
                 visible: visible1080,
                 expected: NSSize(width: 1400, height: 1055)),
            Case(name: "grow past both          → clamp to visible (PREVENTS TILING)",
                 proposed: NSSize(width: 9999, height: 9999),
                 visible: visible1080,
                 expected: NSSize(width: 1920, height: 1055)),
            Case(name: "exactly at visible      → unchanged",
                 proposed: NSSize(width: 1920, height: 1055),
                 visible: visible1080,
                 expected: NSSize(width: 1920, height: 1055)),
            Case(name: "ultrawide screen, big   → clamp to visible",
                 proposed: NSSize(width: 5000, height: 5000),
                 visible: visible1440,
                 expected: NSSize(width: 2560, height: 1415)),
            Case(name: "no screen (test harness) → only min applies",
                 proposed: NSSize(width: 100,  height: 100),
                 visible: nil,
                 expected: NSSize(width: 960,  height: 640)),
            Case(name: "no screen, gigantic     → unbounded above",
                 proposed: NSSize(width: 50_000, height: 50_000),
                 visible: nil,
                 expected: NSSize(width: 50_000, height: 50_000))
        ]

        var passes = 0, failures = 0
        var body = ""
        for c in cases {
            let actual = CrisisAppDelegate.clampResize(proposed: c.proposed, visibleSize: c.visible)
            let ok = abs(actual.width - c.expected.width) < 0.5 && abs(actual.height - c.expected.height) < 0.5
            if ok { passes += 1 } else { failures += 1 }
            let mark = ok ? "✓" : "✘"
            body += "- \(mark) \(c.name)\n"
            if !ok {
                body += "    proposed=\(c.proposed)  expected=\(c.expected)  got=\(actual)\n"
            }
        }
        body += "\n**\(passes) passed, \(failures) failed.**\n"
        return ResizeUnitReport(passes: passes, failures: failures, body: body)
    }

    // MARK: - Manifest

    private static func writeManifest(
        size: CGSize,
        dataLoaded: Bool,
        captured: Int,
        inspectorCaptured: Int,
        comparisonCaptured: Int = 0,
        extendedCaptured: Int = 0
    ) {
        var m = "# CrisisViz Testbed (Time-Scrubbing)\n\n"
        m += "Scene frames: \(captured) (\(AllChapters.totalScenes) scenes × \(timeOffsets.count) time offsets)\n"
        m += "Inspector reveal frames: \(inspectorCaptured)\n"
        m += "Comparison/convergence frames: \(comparisonCaptured)\n"
        m += "Extended sweep frames: \(extendedCaptured) (window sizes × text scales × fine convergence × inspector scales)\n"
        m += "Resolution: \(Int(size.width))×\(Int(size.height))\n"
        m += "Data loaded: \(dataLoaded)\n"
        m += "Scene time offsets: \(timeOffsets.map { String(format: "%.1fs", $0) }.joined(separator: ", "))\n"
        m += "Inspector time offsets: \(inspectorTimeOffsets.map { String(format: "%.1fs", $0) }.joined(separator: ", "))\n"
        m += "Window sizes swept: \(canvasSizeMatrix.map(\.2).joined(separator: ", "))\n"
        m += "Text scales swept: \(textScaleLadder.map { String(format: "%.2f", $0) }.joined(separator: ", "))\n"
        m += "Convergence fine slices: \(convergenceFineOffsets.count) frames covering all 4 lesson steps\n\n"

        m += "## Extended sweep folders\n"
        m += "- `resize_window_sweep/` — comparison rendered at \(canvasSizeMatrix.count) window sizes ×3 phases.\n"
        m += "  Verify: cards never bleed off canvas, divider stays vertically centered,\n"
        m += "  step-3 ghost cards land on the divider regardless of aspect ratio,\n"
        m += "  step-4 stamp is fully on-screen on the smallest (800×600) and widest (2560×1440).\n"
        m += "- `textscale_ladder_sweep/` — comparison at \(textScaleLadder.count) text scales ×3 phases.\n"
        m += "  Verify: at scale 1.60 no text clips card edges, captions wrap not truncate;\n"
        m += "  at scale 0.85 text still readable; spotlights align with cards at every scale.\n"
        m += "- `convergence_fine_grained/` — \(convergenceFineOffsets.count) slices through the 4 lesson steps.\n"
        m += "  Verify: adjacent frames in step3 (t=3.6…5.3) show ghost cards in DIFFERENT positions\n"
        m += "  (kinetic motion, not freeze); step4 stamp blooms (small→full) between t=5.6 and 6.8.\n"
        m += "- `inspector_textscale_sweep/` — single-vertex inspector at \(textScaleLadder.count) scales × 2 reveal phases.\n"
        m += "  Verify: cards stay inside canvas at every scale, no text overflow.\n\n"

        m += "## SANITY.md\n"
        m += "Programmatic checks ran after capture. Open `SANITY.md` in this folder.\n"
        m += "If it reports tiny files (<8 KB) or 'frozen animation groups' (3+ byte-identical\n"
        m += "frames in an animation folder), open the listed files and look for the regression.\n\n"

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
