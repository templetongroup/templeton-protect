import Foundation
import ProtectCore

// The command-line face of the open-source engine.
//
// The same rules the app runs, in a form that fits a pre-commit hook and a CI
// job — the free tier doing the marketing for the paid one. Exit non-zero when
// something at or above a threshold is found, so it can gate a commit.
//
//   protect                     scan this Mac (machine + installations)
//   protect code [path]         scan a folder (default: cwd)
//   protect code --deep [path]  also walk the repository's history
//   protect --json              machine-readable, for CI
//   protect --fail-on high      exit 1 if anything >= high (default: critical)

struct Options {
    var json = false
    var deep = false
    var failOn: Severity = .critical
    var mode = "mac"   // "mac" or "code"
    var path = FileManager.default.currentDirectoryPath
}

func parse() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    if args.first == "code" { o.mode = "code"; args.removeFirst() }
    var rest: [String] = []
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--json": o.json = true
        case "--deep": o.deep = true
        case "--fail-on":
            i += 1
            if i < args.count, let s = Severity(rawValue: args[i]) { o.failOn = s }
        default: rest.append(args[i])
        }
        i += 1
    }
    if o.mode == "code", let p = rest.first { o.path = p }
    return o
}

let opts = parse()
var findings: [Finding] = []
var scannedLabel = ""

switch opts.mode {
case "code":
    let target = describeCodeTarget(opts.path)
    scannedLabel = target.display
    findings = scanCode(at: opts.path).findings
    if opts.deep { findings += scanGitHistory(at: opts.path) }
default:
    scannedLabel = "this Mac"
    findings = scanMachine().findings + scanAiInstallations().findings
}
findings = sortedForReport(findings)

if opts.json {
    let result = ScanResult(findings: findings, toolsFound: [scannedLabel], filesRead: 0)
    let data = try JSONEncoder().encode(result)
    print(String(data: data, encoding: .utf8) ?? "{}")
} else {
    let c = findings.filter { $0.severity == .critical }.count
    let h = findings.filter { $0.severity == .high }.count
    let rest = findings.count - c - h
    print("Templeton Protect — scanned \(scannedLabel)")
    print("\(c) critical, \(h) worth fixing, \(rest) minor\n")
    for f in findings {
        // ⚠️ redact() on every line, exactly as the app and exports do — a CI
        // log is one of the places a printed key does the most damage.
        print("[\(f.severity.rawValue.uppercased())] \(redact(f.title))")
        print("    \(f.where_)")
        print("    → \(redact(f.remedy))\n")
    }
    if findings.isEmpty { print("Nothing found.") }
}

// ⚠️ THE EXIT CODE IS THE PRODUCT, in CI. A scan that always exits 0 gates
// nothing; the threshold is what lets this stand in a pre-commit hook.
let worst = findings.map(\.severity.rank).min() ?? Int.max
exit(worst <= opts.failOn.rank ? 1 : 0)
