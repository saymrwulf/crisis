import Foundation

/// Static-pattern audit of the source tree. Catches regressions that an
/// invariant-against-data check can't see: someone reintroducing direct
/// `DataManager.palette[i]` indexing, hardcoded honest PIDs, lane labels
/// using `node.name.suffix`, etc.
///
/// Why this is part of the test harness: the Crisis curriculum has multiple
/// "single source of truth" rules (cast color via dm.castColor, lane name via
/// dm.castRole, Y position == lane center). Violating any of them is a code
/// smell, not a runtime crash. Source patterns are the only way to detect a
/// silent regression.
enum SourceAudit {

    struct Finding {
        let severity: Severity
        let file: String
        let line: Int
        let pattern: String
        let snippet: String

        enum Severity: String {
            case error  = "ERROR"
            case warning = "WARN"
        }
    }

    struct Report {
        let scanned: Int
        let findings: [Finding]
        var errorCount: Int { findings.filter { $0.severity == .error }.count }
        var warnCount: Int { findings.filter { $0.severity == .warning }.count }
        var allClean: Bool { findings.isEmpty }
    }

    /// Each rule is a (regex, severity, explanation) tuple. The audit walks the
    /// source tree and reports every match with file:line and the offending
    /// snippet.
    private struct Rule {
        let pattern: String
        let severity: Finding.Severity
        let explanation: String
        let allowedFiles: Set<String>  // files where this pattern is OK
    }

    private static let rules: [Rule] = [
        Rule(
            pattern: #"DataManager\.palette\["#,
            severity: .error,
            explanation: "Direct palette index bypasses the cast color system. Use dm.castColor(for:) instead.",
            allowedFiles: [
                // The palette itself is defined in DataManager.swift.
                "DataManager.swift"
            ]
        ),
        Rule(
            pattern: #"dm\.colorIndex\(for:"#,
            severity: .warning,
            explanation: "colorIndex(for:) is a legacy lookup. Prefer dm.castColor(for:) or dm.castRole(for:).",
            allowedFiles: ["DataManager.swift"]  // definition site
        ),
        Rule(
            pattern: #"node\.name\.suffix\("#,
            severity: .error,
            explanation: "Lane labels must use cast names via dm.castRole(for:). Suffix-of-honest-N is the legacy anonymous label.",
            allowedFiles: []
        ),
        Rule(
            pattern: #""1058280f""#,
            severity: .error,
            explanation: "Hardcoded honest-node PID. The legacy Ch03_Partition isolated this PID as if it were the byzantine victim — the bug we just fixed.",
            // The testbed files MUST mention this PID to detect a regression
            // that re-introduces it; whitelisting them is correct, not a bypass.
            allowedFiles: ["NarrativeInvariants.swift", "SourceAudit.swift"]
        ),
        Rule(
            pattern: #""9e42015f""#,
            severity: .error,
            explanation: "Hardcoded honest-node PID. The legacy Ch03_Partition isolated this PID — see partition story-canvas mismatch.",
            allowedFiles: ["NarrativeInvariants.swift", "SourceAudit.swift"]
        ),
        Rule(
            pattern: #"hashJitterY"#,
            severity: .error,
            explanation: "Y-jitter in DAGLayout violates the lane-lifeline invariant. Vertices must sit on lane center exactly.",
            allowedFiles: ["SourceAudit.swift"]  // rule definition references the pattern
        ),
        Rule(
            pattern: #"laneHeight \* 0\."#,
            severity: .warning,
            explanation: "Suspicious multiplier on laneHeight — likely Y jitter being reintroduced. Verify against the lifeline rule.",
            allowedFiles: ["DAGLayoutEngine.swift"]  // legitimate usage in margin computation
        )
    ]

    static func runAudit(rootDir: URL? = nil) -> Report {
        let root = rootDir ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/CrisisViz")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else {
            return Report(scanned: 0, findings: [])
        }

        var findings: [Finding] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            let filename = url.lastPathComponent
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

            for (lineIdx, line) in lines.enumerated() {
                let lineStr = String(line)
                // Skip comments — we don't want to flag pattern descriptions
                // in the rule definitions or in /// doc comments that explain
                // a deprecated API.
                let trimmed = lineStr.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                if trimmed.hasPrefix("*") { continue }

                for rule in rules {
                    if rule.allowedFiles.contains(filename) { continue }
                    if let _ = lineStr.range(of: rule.pattern, options: .regularExpression) {
                        findings.append(Finding(
                            severity: rule.severity,
                            file: filename,
                            line: lineIdx + 1,
                            pattern: rule.pattern,
                            snippet: trimmed
                        ))
                    }
                }
            }
        }
        return Report(scanned: scanned, findings: findings)
    }

    static func writeReport(_ report: Report, to url: URL) {
        var md = "# CrisisViz Source Pattern Audit\n\n"
        md += "Run at: \(Date())\n\n"
        md += "**Scanned: \(report.scanned) Swift files. Errors: \(report.errorCount). Warnings: \(report.warnCount).**\n\n"

        if report.allClean {
            md += "✅ No forbidden patterns detected. The cast-color discipline, lifeline rule, and partition-victim integrity hold across every source file.\n\n"
        } else {
            md += "❌ Found pattern violations. These are silent regressions — they don't crash, but they break design rules the curriculum depends on.\n\n"
        }

        // Group by file for readability.
        let byFile = Dictionary(grouping: report.findings, by: \.file)
        for (file, findings) in byFile.sorted(by: { $0.key < $1.key }) {
            md += "## \(file)\n\n"
            for f in findings.sorted(by: { $0.line < $1.line }) {
                md += "- **\(f.severity.rawValue)** L\(f.line) — pattern `\(f.pattern)`\n"
                md += "  ```\n  \(f.snippet)\n  ```\n"
                if let rule = rules.first(where: { $0.pattern == f.pattern }) {
                    md += "  → \(rule.explanation)\n\n"
                }
            }
        }

        md += "\n## Rules enforced\n\n"
        for rule in rules {
            md += "- **\(rule.severity.rawValue)** `\(rule.pattern)` — \(rule.explanation)"
            if !rule.allowedFiles.isEmpty {
                md += " (allowed in: \(rule.allowedFiles.sorted().joined(separator: ", ")))"
            }
            md += "\n"
        }

        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}
