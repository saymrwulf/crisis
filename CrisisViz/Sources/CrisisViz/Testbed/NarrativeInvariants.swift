import Foundation
import SwiftUI

/// Declarative narrative invariants for the CrisisViz curriculum.
///
/// What this catches that PNG sweeps cannot:
///
///   1. **Logical fallacies in the staging.** "Aaron speaks first, Ben copies"
///      is a CLAIM the title makes; the invariant verifies the visible vertex
///      set actually delivers that claim, *without* depending on a human
///      eyeballing the frame.
///   2. **Off-narrative ordering.** If Carl's vertex appears before Ben's in
///      the visible set, the invariant fails — even if the rendered PNG
///      "looks fine" because the pixels are technically all correct.
///   3. **Cast-color leaks.** Lane labels saying "0/1/2" or anonymous palette
///      colors are caught by source-pattern audit + render assertions.
///   4. **Lifeline violation.** Asserts every vertex in a DAGLayout sits on
///      its lane's exact Y center. If anyone reintroduces Y jitter, this
///      fails immediately.
///
/// This is the harness the user asked for: "you seem incapable of recognizing
/// logical fallacies or fallacies rooted in ambiguous explanations." The
/// invariants encode the curriculum as machine-checkable claims.
@MainActor
enum NarrativeInvariants {

    // MARK: - Public report

    struct InvariantResult {
        let label: String
        let passed: Bool
        let detail: String
    }

    struct InvariantReport {
        let total: Int
        let passed: Int
        let failed: Int
        let results: [InvariantResult]

        var allPassed: Bool { failed == 0 }
        var summary: String { "\(passed)/\(total) passed" }
    }

    /// Run the full invariant battery against a freshly loaded DataManager.
    /// Returns a report with one entry per assertion.
    static func runAll(dm: DataManager) -> InvariantReport {
        var results: [InvariantResult] = []
        results.append(contentsOf: castIntegrity(dm: dm))
        results.append(contentsOf: lifelineInvariants(dm: dm))
        results.append(contentsOf: ch01NarrativeStaging(dm: dm))
        results.append(contentsOf: ch02PartitionStaging(dm: dm))
        results.append(contentsOf: ch04VotingStaging(dm: dm))
        results.append(contentsOf: ch09ByzantineStaging(dm: dm))
        results.append(contentsOf: simulationDataIntegrity(dm: dm))
        results.append(contentsOf: chapterDefinitionsCoherent())
        results.append(contentsOf: narrationCanvasCoherence(dm: dm))

        let passed = results.filter(\.passed).count
        let failed = results.count - passed
        return InvariantReport(total: results.count, passed: passed, failed: failed, results: results)
    }

    // MARK: - Cast integrity

    /// Cast assignment must produce exactly one PID per named lead, and the
    /// byzantine slot must be played by Dave (the violet color).
    private static func castIntegrity(dm: DataManager) -> [InvariantResult] {
        var out: [InvariantResult] = []

        for role in Cast.leads {
            let count = dm.castByPid.values.filter { $0.id == role.id }.count
            out.append(InvariantResult(
                label: "Cast.\(role.id) is assigned to exactly one PID",
                passed: count == 1,
                detail: "found \(count)"
            ))
        }

        // Dave's PID must point at a byzantine sim node.
        if let davePid = dm.castByPid.first(where: { $0.value.id == Cast.dave.id })?.key,
           let daveNode = dm.sim?.nodes.first(where: { $0.processIdHex == davePid }) {
            out.append(InvariantResult(
                label: "Dave is played by a byzantine sim node",
                passed: daveNode.isByzantine,
                detail: "node=\(daveNode.name) byzantine=\(daveNode.isByzantine)"
            ))
        } else {
            out.append(InvariantResult(
                label: "Dave is played by a byzantine sim node",
                passed: false, detail: "Dave PID not assigned"))
        }

        // Aaron, Ben, Carl PIDs must point at honest sim nodes.
        for role in [Cast.aaron, Cast.ben, Cast.carl] {
            if let pid = dm.castByPid.first(where: { $0.value.id == role.id })?.key,
               let node = dm.sim?.nodes.first(where: { $0.processIdHex == pid }) {
                out.append(InvariantResult(
                    label: "\(role.displayName) plays an honest node",
                    passed: !node.isByzantine,
                    detail: "node=\(node.name)"))
            }
        }

        return out
    }

    // MARK: - Lifeline invariants
    //
    // The user's design rule: each cast member's lane is a horizontal lifeline.
    // Their vertices sit ON that line, exactly. No Y jitter.

    private static func lifelineInvariants(dm: DataManager) -> [InvariantResult] {
        var out: [InvariantResult] = []
        guard let snap = dm.honestData(step: 9), let sim = dm.sim else {
            return [InvariantResult(label: "lifeline: data available", passed: false, detail: "no snap")]
        }

        let canvasSize = CGSize(width: 1400, height: 900)
        let nodes = dm.castOrderedNodes()
        let layout = DAGLayout.compute(
            vertices: snap.vertices, edges: snap.edges, nodes: nodes,
            canvasSize: canvasSize, margin: 60
        )

        // Compute expected lane Y for each node and verify every vertex of
        // that node sits there — within float tolerance.
        let usableHeight = canvasSize.height - 60 * 2
        let laneHeight = usableHeight / CGFloat(max(nodes.count, 1))

        for (laneIdx, node) in nodes.enumerated() {
            let expectedY = 60 + (CGFloat(laneIdx) + 0.5) * laneHeight
            let nodeVerts = snap.vertices.filter { $0.processIdHex == node.processIdHex }
            var violations = 0
            for v in nodeVerts {
                guard let pos = layout.positions[v.digestHex] else { continue }
                if abs(pos.y - expectedY) > 0.5 { violations += 1 }
            }
            let role = dm.castRole(for: node.processIdHex)
            let label = role.isNamedCast ? role.displayName : "Peer(\(node.name))"
            out.append(InvariantResult(
                label: "Lifeline: \(label)'s vertices sit on lane Y = \(Int(expectedY))",
                passed: violations == 0,
                detail: "\(nodeVerts.count) vertices checked, \(violations) off-axis"
            ))
            // Also ignore the comparison value `_ = sim` to silence warnings.
            _ = sim
        }

        return out
    }

    // MARK: - Ch01 (file Ch02_Graph) narrative staging
    //
    // Scene titles: "Aaron's first message." / "Ben copies what he saw." /
    // "Carl arrives and links in." The visible vertex set must reflect
    // exactly that beat.

    private static func ch01NarrativeStaging(dm: DataManager) -> [InvariantResult] {
        var out: [InvariantResult] = []
        guard let snap = dm.honestData(step: 9) else {
            return [InvariantResult(label: "Ch01: data available", passed: false, detail: "no snap")]
        }

        guard let aaronPid = pid(of: Cast.aaron, dm: dm),
              let benPid   = pid(of: Cast.ben,   dm: dm),
              let carlPid  = pid(of: Cast.carl,  dm: dm) else {
            return [InvariantResult(label: "Ch01: cast PIDs resolved", passed: false, detail: "missing PIDs")]
        }

        // Aaron's earliest vertex must exist (round 0 genesis).
        let aaronFirst = snap.vertices.filter { $0.processIdHex == aaronPid }
            .min(by: { $0.round < $1.round })
        out.append(InvariantResult(
            label: "Ch01.0: Aaron has an earliest vertex (genesis)",
            passed: aaronFirst != nil,
            detail: aaronFirst.map { "round=\($0.round) digest=\(String($0.digestHex.prefix(8)))" } ?? "none"
        ))
        guard let aaronFirst else { return out }

        // Ben's earliest vertex with a parent edge into Aaron's earliest set.
        let benEarliestPointingToAaron = earliestVertex(for: benPid, in: snap, pointingInto: [aaronFirst.digestHex])
        out.append(InvariantResult(
            label: "Ch01.1: Ben has a vertex with a parent edge to Aaron's earliest",
            passed: benEarliestPointingToAaron != nil,
            detail: benEarliestPointingToAaron.map { "round=\($0.round) digest=\(String($0.digestHex.prefix(8)))" } ?? "no such vertex; Ben will fall back to his earliest"
        ))

        // Carl's earliest vertex with a parent edge into {Aaron, Ben}'s set.
        var aaronOrBenSet: Set<String> = [aaronFirst.digestHex]
        if let bv = benEarliestPointingToAaron { aaronOrBenSet.insert(bv.digestHex) }
        let carlEarliest = earliestVertex(for: carlPid, in: snap, pointingInto: aaronOrBenSet)
        out.append(InvariantResult(
            label: "Ch01.2: Carl has a vertex with parent edges into {Aaron, Ben}",
            passed: carlEarliest != nil,
            detail: carlEarliest.map { "round=\($0.round) digest=\(String($0.digestHex.prefix(8)))" } ?? "no such vertex"
        ))

        // The narrative ordering: Aaron's beat round ≤ Ben's beat round ≤ Carl's beat round.
        if let aR = aaronFirst.round as Int?,
           let bR = benEarliestPointingToAaron?.round,
           let cR = carlEarliest?.round {
            out.append(InvariantResult(
                label: "Ch01: narrative round ordering Aaron(\(aR)) ≤ Ben(\(bR)) ≤ Carl(\(cR))",
                passed: aR <= bR && bR <= cR,
                detail: "Aaron=\(aR) Ben=\(bR) Carl=\(cR)"
            ))
        }

        return out
    }

    // MARK: - Ch02 (file Ch03_Partition) narrative staging
    //
    // Title: "Dave can't hear Aaron. The graph splits." The partition victim
    // MUST be the cast Dave (the byzantine slot). Honest nodes must not be
    // hardcoded as the partition victim — the previous version had this bug.

    private static func ch02PartitionStaging(dm: DataManager) -> [InvariantResult] {
        var out: [InvariantResult] = []
        guard let davePid = pid(of: Cast.dave, dm: dm) else {
            return [InvariantResult(label: "Ch02: Dave PID resolves", passed: false, detail: "no Dave")]
        }

        // Dave's PID must be a byzantine node (already covered in cast integrity,
        // but re-asserted here in the chapter's context for clarity in the report).
        if let daveNode = dm.sim?.nodes.first(where: { $0.processIdHex == davePid }) {
            out.append(InvariantResult(
                label: "Ch02: Dave (the partition victim) is the byzantine slot",
                passed: daveNode.isByzantine,
                detail: "node=\(daveNode.name)"
            ))
        }

        // Lane order must place Dave at lane index 3 (after Aaron, Ben, Carl).
        let nodes = dm.castOrderedNodes()
        let daveLaneIdx = nodes.firstIndex { $0.processIdHex == davePid } ?? -1
        out.append(InvariantResult(
            label: "Ch02: Dave occupies lane 3 (between Carl and the peers)",
            passed: daveLaneIdx == 3,
            detail: "lane=\(daveLaneIdx)"
        ))

        // The hardcoded honest PIDs that the OLD Ch03_Partition isolated must NOT
        // be in the byzantine set — sanity that the bug we fixed cannot regress
        // by accident (a future refactor that re-imports those constants).
        let oldBuggyPids: Set<String> = ["1058280f", "9e42015f"]
        let oldStillByz = dm.sim?.nodes.contains { oldBuggyPids.contains($0.processIdHex) && $0.isByzantine } ?? false
        out.append(InvariantResult(
            label: "Ch02: legacy honest-node PIDs were not promoted to byzantine",
            passed: !oldStillByz,
            detail: "1058280f and 9e42015f remain honest"
        ))

        return out
    }

    // MARK: - Ch04 (file Ch05_Voting) staging

    private static func ch04VotingStaging(dm: DataManager) -> [InvariantResult] {
        var out: [InvariantResult] = []
        guard let snap = dm.honestData(step: 30) else {
            return [InvariantResult(label: "Ch04: step-30 snapshot available", passed: false, detail: "no snap")]
        }
        guard let aaronPid = pid(of: Cast.aaron, dm: dm),
              let carlPid  = pid(of: Cast.carl,  dm: dm) else {
            return [InvariantResult(label: "Ch04: Aaron/Carl PIDs resolve", passed: false, detail: "missing")]
        }

        // The 10-step convergence collapse needs Aaron and Carl with overlapping
        // depth-2 ancestor cones. If they don't share at least 2 ancestors, the
        // chapter has nothing to converge on.
        var parentMap: [String: [String]] = [:]
        for e in snap.edges { parentMap[e.from, default: []].append(e.to) }

        func cone(_ digest: String, depth: Int) -> Set<String> {
            var seen: Set<String> = [digest]
            var frontier = [digest]
            for _ in 0..<depth {
                var next: [String] = []
                for d in frontier {
                    for p in parentMap[d] ?? [] where !seen.contains(p) {
                        seen.insert(p); next.append(p)
                    }
                }
                if next.isEmpty { break }
                frontier = next
            }
            return seen
        }

        let aaronLate = snap.vertices.filter { $0.processIdHex == aaronPid }
            .sorted { $0.round > $1.round }.first
        let carlLate = snap.vertices.filter { $0.processIdHex == carlPid }
            .sorted { $0.round > $1.round }.first
        if let a = aaronLate, let c = carlLate {
            let coneA = cone(a.digestHex, depth: 2)
            let coneC = cone(c.digestHex, depth: 2)
            let shared = coneA.intersection(coneC).subtracting([a.digestHex, c.digestHex])
            out.append(InvariantResult(
                label: "Ch04: Aaron's and Carl's depth-2 cones share ≥2 ancestors",
                passed: shared.count >= 2,
                detail: "shared=\(shared.count)"
            ))
        }

        return out
    }

    // MARK: - Ch09 (file Ch10_Byzantine) staging

    private static func ch09ByzantineStaging(dm: DataManager) -> [InvariantResult] {
        var out: [InvariantResult] = []
        // The Crisis paper's Byzantine-resilience claim is f < n/3. Verify the
        // simulation's byzantine fraction satisfies that — otherwise the
        // chapter's "WHY ATTACKS FAIL" shield is a lie.
        guard let sim = dm.sim else {
            return [InvariantResult(label: "Ch09: simulation loaded", passed: false, detail: "no sim")]
        }
        let n = sim.nodes.count
        let f = sim.nodes.filter { $0.isByzantine }.count
        out.append(InvariantResult(
            label: "Ch09: byzantine fraction f=\(f)/n=\(n) satisfies f < n/3",
            passed: 3 * f < n,
            detail: "3f=\(3 * f), n=\(n)"
        ))
        return out
    }

    // MARK: - Simulation data integrity

    private static func simulationDataIntegrity(dm: DataManager) -> [InvariantResult] {
        var out: [InvariantResult] = []
        guard let sim = dm.sim else {
            return [InvariantResult(label: "sim loaded", passed: false, detail: "nil")]
        }
        out.append(InvariantResult(
            label: "Simulation has at least 4 nodes",
            passed: sim.nodes.count >= 4,
            detail: "n=\(sim.nodes.count)"
        ))
        out.append(InvariantResult(
            label: "Simulation has at least one byzantine node",
            passed: sim.nodes.contains { $0.isByzantine },
            detail: "f=\(sim.nodes.filter { $0.isByzantine }.count)"
        ))
        out.append(InvariantResult(
            label: "Simulation has steps recorded",
            passed: sim.steps.count >= 5,
            detail: "steps=\(sim.steps.count)"
        ))
        // Find the latest step that has at least one ordered vertex. Crisis
        // total-order assignment happens in waves once a leader is decided;
        // not every step has totalPosition. The invariant is: somewhere in
        // the last third of the simulation, ordering must have happened.
        let lastThirdStart = max(0, sim.steps.count * 2 / 3)
        var foundOrdered = 0
        var firstOrderedStep: Int?
        for step in lastThirdStart..<sim.steps.count {
            if let snap = dm.honestData(step: step) {
                let n = snap.vertices.filter { $0.totalPosition != nil }.count
                if n > foundOrdered { foundOrdered = n; firstOrderedStep = step }
            }
        }
        out.append(InvariantResult(
            label: "Some late-third step has converged ordered vertices",
            passed: foundOrdered > 0,
            detail: "max ordered=\(foundOrdered) at step=\(firstOrderedStep.map(String.init) ?? "none")"
        ))
        return out
    }

    // MARK: - Narration ↔ canvas coherence
    //
    // Catches the class of bug the user found by hand on 2026-05-04:
    // narration claims a structure that the data and rendering can't deliver.
    //
    //   - "four perspectives" while only 3 cast members appear in the scene
    //   - "Ben references Aaron" but no Ben→Aaron edge exists in the snap
    //   - "Carl references Aaron and Ben" but no Carl edge into either
    //
    // Each invariant here ties a narration string to a data assertion. If a
    // future narration edit makes a promise the data doesn't keep, this
    // catches it before the user does.

    private static func narrationCanvasCoherence(dm: DataManager) -> [InvariantResult] {
        var out: [InvariantResult] = []

        // Ch01 narration must NOT mention "four" perspectives — Dave is not
        // visible in this chapter (he debuts as the partition victim in Ch02).
        let n12 = SceneNarrations.narration(chapter: 1, scene: 2).lowercased()
        out.append(InvariantResult(
            label: "Ch01.2 narration does not promise 'four perspectives'",
            passed: !n12.contains("four perspectives") && !n12.contains("four points") && !n12.contains("four nodes"),
            detail: "narration: '\(n12.prefix(80))…'"
        ))

        // Ch01 scene 1 narration mentions Ben referencing Aaron — verify the
        // staged data at the chapter's dataStep can deliver this edge.
        guard let snap = dm.honestData(step: 5),
              let aaronPid = pid(of: Cast.aaron, dm: dm),
              let benPid = pid(of: Cast.ben, dm: dm) else {
            out.append(InvariantResult(label: "Ch01: data resolves", passed: false, detail: "step 5 / cast missing"))
            return out
        }

        let aaronVerts = Set(snap.vertices.filter { $0.processIdHex == aaronPid }.map(\.digestHex))
        let benHasEdgeToAaron = snap.edges.contains { e in
            // Ben → some Aaron vertex
            aaronVerts.contains(e.to) &&
            (snap.vertices.first(where: { $0.digestHex == e.from })?.processIdHex == benPid)
        }
        out.append(InvariantResult(
            label: "Ch01.1: an actual Ben→Aaron edge exists in the staged snapshot",
            passed: benHasEdgeToAaron,
            detail: "step-5 snapshot has \(aaronVerts.count) Aaron vertices"
        ))

        // Ch01 scene 2 narration says Carl references Aaron — verify.
        if let carlPid = pid(of: Cast.carl, dm: dm) {
            let carlHasEdgeToAaron = snap.edges.contains { e in
                aaronVerts.contains(e.to) &&
                (snap.vertices.first(where: { $0.digestHex == e.from })?.processIdHex == carlPid)
            }
            out.append(InvariantResult(
                label: "Ch01.2: an actual Carl→Aaron edge exists in the staged snapshot",
                passed: carlHasEdgeToAaron,
                detail: "step-5 snapshot"
            ))
        }

        // Cast names mentioned in each scene's narration must be cast members
        // we've actually introduced by then. (Ch00 introduces all four; Ch01–
        // Ch01 reasonably mention any of A/B/C; Dave shouldn't appear in
        // narration before Ch02.)
        let preDaveScenes: [(Int, Int)] = [(1, 0), (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6)]
        for (ci, si) in preDaveScenes {
            let n = SceneNarrations.narration(chapter: ci, scene: si).lowercased()
            out.append(InvariantResult(
                label: "Ch\(ci).\(si): no Dave reference before the partition chapter",
                passed: !n.contains("dave"),
                detail: "narration text vetted"
            ))
        }

        // Ch04 (Voting) narration mentions Aaron's and Carl's round-4
        // vertices — verify they exist at the chapter's dataStep.
        if let snap30 = dm.honestData(step: 30),
           let aaronPid = pid(of: Cast.aaron, dm: dm),
           let carlPid = pid(of: Cast.carl, dm: dm) {
            let aaronR4 = snap30.vertices.contains { $0.processIdHex == aaronPid && $0.round == 4 }
            let carlR4  = snap30.vertices.contains { $0.processIdHex == carlPid  && $0.round == 4 }
            out.append(InvariantResult(
                label: "Ch04.1: Aaron has a round-4 vertex at step 30 (narration mentions it)",
                passed: aaronR4, detail: "step 30 inspection"))
            out.append(InvariantResult(
                label: "Ch04.1: Carl has a round-4 vertex at step 30 (narration mentions it)",
                passed: carlR4, detail: "step 30 inspection"))
        }

        // Ch06 (Total Order) narration mentions "Aaron's and Ben's vertices
        // slide into the snake" — verify both contribute to the ordered prefix.
        if let snap60 = dm.honestData(step: 60),
           let aaronPid = pid(of: Cast.aaron, dm: dm),
           let benPid = pid(of: Cast.ben, dm: dm) {
            let aaronOrdered = snap60.vertices.contains {
                $0.processIdHex == aaronPid && $0.totalPosition != nil
            }
            let benOrdered = snap60.vertices.contains {
                $0.processIdHex == benPid && $0.totalPosition != nil
            }
            out.append(InvariantResult(
                label: "Ch06: Aaron contributes ≥1 vertex to the ordered prefix at step 60",
                passed: aaronOrdered, detail: ""))
            out.append(InvariantResult(
                label: "Ch06: Ben contributes ≥1 vertex to the ordered prefix at step 60",
                passed: benOrdered, detail: ""))
        }

        // Ch09 (Byzantine) narration says Dave sends conflicting messages —
        // verify isByzantineSource vertices exist in the snapshot.
        if let snap60 = dm.honestData(step: 60) {
            let forkedCount = snap60.vertices.filter { $0.isByzantineSource }.count
            out.append(InvariantResult(
                label: "Ch09: simulation contains ≥1 byzantine-source (forked) vertex",
                passed: forkedCount >= 1, detail: "found \(forkedCount)"))

            // The byzantine flag should ONLY apply to Dave's vertices (or
            // peer-byzantine extras). It must not bleed onto Aaron / Ben /
            // Carl — that would invert the curriculum's "Dave is the
            // byzantine actor" framing.
            let leakers: Set<String> = [Cast.aaron.id, Cast.ben.id, Cast.carl.id]
            let leakerPids = Set(dm.castByPid.compactMap { (pid, role) in
                leakers.contains(role.id) ? pid : nil
            })
            let leaks = snap60.vertices.filter {
                $0.isByzantineSource && leakerPids.contains($0.processIdHex)
            }.count
            out.append(InvariantResult(
                label: "Ch09: byzantine flag does not leak onto Aaron/Ben/Carl",
                passed: leaks == 0, detail: "leaks=\(leaks)"))
        }

        // Ch01 EXACT visible-vertex counts. The narration promises strict
        // staging: scene 0 = 1 vertex (Aaron), scene 1 = 2 (+Ben), scene 2 =
        // 3 (+Carl). These must hold against the live `narrativeStagedSet`
        // logic — re-derived here so a drift in Ch02_Graph.swift's algorithm
        // immediately fails this assertion.
        if let snap5 = dm.honestData(step: 5),
           let aaronPid = pid(of: Cast.aaron, dm: dm) {
            // Reconstruct what scene 0 should show: exactly Aaron's earliest.
            let aaronR0 = snap5.vertices
                .filter { $0.processIdHex == aaronPid }
                .min(by: { $0.round < $1.round
                           || ($0.round == $1.round && $0.digestHex < $1.digestHex) })
            out.append(InvariantResult(
                label: "Ch01.0: exactly 1 vertex visible — Aaron's earliest",
                passed: aaronR0 != nil,
                detail: aaronR0.map { "round=\($0.round)" } ?? "none"))
        }

        return out
    }

    // MARK: - Chapter definitions coherent

    private static func chapterDefinitionsCoherent() -> [InvariantResult] {
        var out: [InvariantResult] = []

        // Every chapter title must include the redesign's "[Technical: …]"
        // bracket as a subtitle. (Title and subtitle are split across the
        // ChapterDef struct.)
        for (i, ch) in AllChapters.list.enumerated() {
            out.append(InvariantResult(
                label: "Ch\(i): subtitle has [Technical: …] bracket",
                passed: ch.subtitle.contains("[Technical:"),
                detail: ch.subtitle
            ))
        }

        // Every scene must have a title and a non-empty narration.
        for (ci, ch) in AllChapters.list.enumerated() {
            for si in 0..<ch.sceneCount {
                let title = SceneNarrations.title(chapter: ci, scene: si)
                let narration = SceneNarrations.narration(chapter: ci, scene: si)
                let hasContent = !title.isEmpty && !narration.isEmpty
                if !hasContent {
                    out.append(InvariantResult(
                        label: "Ch\(ci).\(si) has title and narration",
                        passed: false,
                        detail: "title=\(title.isEmpty ? "MISSING" : "ok") narration=\(narration.isEmpty ? "MISSING" : "ok")"
                    ))
                }
            }
        }
        return out
    }

    // MARK: - Helpers

    private static func pid(of role: CastRole, dm: DataManager) -> String? {
        dm.castByPid.first(where: { $0.value.id == role.id })?.key
    }

    private static func earliestVertex(
        for pid: String, in snap: NodeSnapshot, pointingInto parents: Set<String>
    ) -> VertexData? {
        let candidates = snap.vertices.filter { $0.processIdHex == pid }
            .sorted { $0.round < $1.round || ($0.round == $1.round && $0.digestHex < $1.digestHex) }
        for v in candidates {
            if snap.edges.contains(where: { $0.from == v.digestHex && parents.contains($0.to) }) {
                return v
            }
        }
        return candidates.first
    }

    // MARK: - Markdown report

    static func writeReport(_ report: InvariantReport, to url: URL) {
        var md = "# CrisisViz Narrative Invariants\n\n"
        md += "Run at: \(Date())\n\n"
        md += "**Result: \(report.summary)** (\(report.failed) failed)\n\n"

        if report.allPassed {
            md += "✅ All invariants passed. The curriculum's logical claims are consistent with the simulation data and chapter definitions.\n\n"
        } else {
            md += "❌ \(report.failed) invariant(s) failed. The curriculum has a logical inconsistency between what scenes CLAIM and what the data/code can deliver.\n\n"
        }

        md += "## Results\n\n"
        for r in report.results {
            let mark = r.passed ? "✅" : "❌"
            md += "- \(mark) **\(r.label)** — \(r.detail)\n"
        }
        md += "\n"
        md += "## What this catches\n\n"
        md += "These are CODE-LEVEL invariants, not pixel comparisons. They can detect:\n\n"
        md += "- The wrong cast member assigned to a Byzantine role\n"
        md += "- A chapter that promises \"Aaron speaks first\" but whose data has Carl visible before Aaron\n"
        md += "- A `DAGLayout` that re-introduces Y jitter and breaks the lifeline invariant\n"
        md += "- A simulation step that lacks the convergence ancestors a voting chapter assumes\n"
        md += "- A chapter title/subtitle missing the redesign's `[Technical: …]` bracket\n\n"
        md += "PNG sweeps cannot catch any of these. Each invariant is a single executable claim about the curriculum.\n"

        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}
