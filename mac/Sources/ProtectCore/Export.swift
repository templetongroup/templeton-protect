import Foundation

/// Findings, out of the app and into a file someone can send to a colleague.
///
/// ⚠️ EVERY EXPORT RUNS THROUGH redact(). A report that carries the key it found
/// has copied that key somewhere new — into a Downloads folder, an email, a
/// ticket — which is the exact failure this tool exists to catch. The scan
/// already redacts on screen; an export that skipped it would quietly undo that.

public enum ExportFormat: String, CaseIterable, Sendable {
    case pdf, csv, markdown

    public var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .csv: return "csv"
        case .markdown: return "md"
        }
    }

    public var label: String {
        switch self {
        case .pdf: return "PDF"
        case .csv: return "CSV"
        case .markdown: return "Markdown"
        }
    }
}

public func exportFilename(_ format: ExportFormat, on date: Date = Date()) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return "Templeton Protect \(f.string(from: date)).\(format.fileExtension)"
}

private func stamp(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .long
    f.timeStyle = .short
    return f.string(from: date)
}

/// ⚠️ RFC 4180 QUOTING, NOT "wrap it in quotes". A finding's path can contain a
/// comma and its evidence can contain a quote mark; either one unescaped shifts
/// every later column into the wrong header, which is worse than no export at
/// all because the file still opens and still looks plausible.
func csvCell(_ raw: String) -> String {
    let value = redact(raw)
    guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
        return value
    }
    return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

public func exportCSV(_ result: ScanResult, on date: Date = Date()) -> String {
    var rows = ["severity,rule,title,location,found,what to do,how to check"]
    for f in sortedForReport(result.findings) {
        rows.append([f.severity.rawValue, f.rule, f.title, f.where_,
                     f.evidence, f.remedy, f.validation].map(csvCell).joined(separator: ","))
    }
    // A trailing newline: some tools drop the last row without one.
    return rows.joined(separator: "\n") + "\n"
}

public func exportMarkdown(_ result: ScanResult, on date: Date = Date()) -> String {
    var out = ["# Templeton Protect", "", "\(stamp(date))", ""]
    out.append(summaryLine(result))
    out.append("")

    if result.findings.isEmpty {
        out.append("Nothing to worry about. No credentials are sitting in your AI conversation logs, and nothing another account on this Mac could read.")
        return out.joined(separator: "\n") + "\n"
    }

    var lastSeverity: Severity?
    for f in sortedForReport(result.findings) {
        if f.severity != lastSeverity {
            out.append("## \(headingFor(f.severity))")
            out.append("")
            lastSeverity = f.severity
        }
        out.append("### \(f.title)")
        out.append("")
        out.append(redact(f.plain))
        out.append("")
        out.append("- **Where:** `\(f.where_)`")
        out.append("- **Found:** \(redact(f.evidence))")
        out.append("- **What to do:** \(redact(f.remedy))")
        out.append("- **How to check:** \(redact(f.validation))")
        out.append("- **Confirmed:** \(f.verified ? "yes, by a direct check" : "no — pattern match only")")
        out.append("")
    }
    return out.joined(separator: "\n") + "\n"
}

/// Critical first. A report whose first page is the minor stuff wastes the one
/// glance most people give it.
public func sortedForReport(_ findings: [Finding]) -> [Finding] {
    let order: [Severity: Int] = [.critical: 0, .high: 1, .medium: 2, .low: 3]
    return findings.sorted {
        let a = order[$0.severity] ?? 9, b = order[$1.severity] ?? 9
        return a == b ? $0.where_ < $1.where_ : a < b
    }
}

public func headingFor(_ severity: Severity) -> String {
    switch severity {
    case .critical: return "Critical"
    case .high: return "Worth fixing"
    case .medium, .low: return "Minor"
    }
}

public func summaryLine(_ result: ScanResult) -> String {
    let c = result.findings.filter { $0.severity == .critical }.count
    let h = result.findings.filter { $0.severity == .high }.count
    let m = result.findings.count - c - h
    let tools = result.toolsFound.isEmpty ? "no AI installations" : result.toolsFound.joined(separator: ", ")
    return "Checked \(result.filesRead.formatted()) files across \(tools). Found \(c) critical, \(h) worth fixing, \(m) minor."
}
