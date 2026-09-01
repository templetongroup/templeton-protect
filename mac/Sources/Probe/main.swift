import AppKit
import Foundation
import ProtectCore

// The scratch harness. There is no Swift test target, so this is how a rule is
// measured against the real filesystem before the app is rebuilt.
//
//     swift build --product Probe && .build/debug/Probe [folder]
//
// ⚠️ IT RUNS ALL THREE SCANS, and that is the point. Two of them were added
// after the app already worked, and the way both sets of false positives were
// caught was running them here and reading every line — not by reasoning about
// the regular expressions.

let folder = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath

func report(_ name: String, _ r: ScanResult, _ seconds: Double) {
    print(String(format: "\n%@ — %d findings, %d read, %.1fs", name, r.findings.count, r.filesRead, seconds))
    for f in r.findings {
        print("  [\(f.severity.rawValue)] \(f.title)")
        print("      \(f.where_)")
        print("      \(f.evidence)")
    }
}

let spec = describeMachine()
print("\(spec.headline) · \(spec.cores) cores · \(spec.memory) · \(spec.storage)")

var t = Date()
let machine = scanMachine()
report("hardware", machine, -t.timeIntervalSinceNow)

t = Date()
let installs = scanAiInstallations()
report("installations", installs, -t.timeIntervalSinceNow)

t = Date()
let code = scanCode(at: folder)
report("code (\(describeCodeTarget(folder).headline))", code, -t.timeIntervalSinceNow)

if ProcessInfo.processInfo.environment["PROTECT_DEEP"] != nil {
    t = Date()
    let hist = scanGitHistory(at: folder)
    report("history", ScanResult(findings: hist, toolsFound: [], filesRead: 0), -t.timeIntervalSinceNow)
}

// ⚠️ THE EXPORTS ARE THE PART WITH NO TEST AND THE MOST WAYS TO LEAK. A report
// carrying the key it found has copied that key somewhere new.
let all = ScanResult(findings: machine.findings + installs.findings + code.findings,
                     toolsFound: machine.toolsFound + installs.toolsFound + code.toolsFound,
                     filesRead: machine.filesRead + installs.filesRead + code.filesRead)
print("\n\(summaryLine(all))")
let markdown = exportMarkdown(all)
var leaked = false
for shape in ["sk-ant-", "sk-proj-", "ghp_", "AIza", "AKIA", "glpat-", "xoxb-"] where markdown.contains(shape) {
    print("LEAK: \(shape) survived redact() into the markdown export")
    leaked = true
}
print(leaked ? "exports: LEAKING" : "exports: clean")

// ⚠️ WRITE THE PDF OUT TOO. It is the one export with real layout and no test,
// and "the swirl at the bottom is pixelated" is not something a string check
// finds. Render it and look at it.
if let out = ProcessInfo.processInfo.environment["PROTECT_EXPORT_DIR"] {
    try exportCSV(all).write(toFile: out + "/protect.csv", atomically: true, encoding: .utf8)
    try markdown.write(toFile: out + "/protect.md", atomically: true, encoding: .utf8)
    // ⚠️ LOAD THE MARK FROM DISK. Probe is not a bundle, so the export's default
    // `Bundle.main.image(forResource:)` returns nil here and the PDF comes out
    // with no watermark at all — which is exactly the part that needed looking at.
    let markPath = "Resources/swirl.png"
    let mark = NSImage(contentsOfFile: markPath) ?? NSImage(contentsOfFile: "mac/" + markPath)
    if mark == nil { print("⚠️ no swirl.png found — run Probe from mac/, or the PDF has no watermark") }
    try PDFReport.write(all, to: URL(fileURLWithPath: out + "/protect.pdf"), mark: mark)
    print("wrote \(out)/protect.{csv,md,pdf}")
}
