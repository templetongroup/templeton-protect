import Foundation

// What earlier scans found, so this one can say what changed.
//
// A single scan is a snapshot; the product's claim is protection, and
// protection is a curve — "two new since last week, three fixed" is the
// sentence that makes a re-scan worth running and a subscription worth
// keeping. docs/PRODUCT.md calls this out: history is what lets somebody
// show that things improved.
//
// ⚠️ THE HISTORY HOLDS FINDINGS, WHICH MEANS IT HOLDS PATHS. Everything
// written here has been through redact() at the finding level already (no
// finding carries a secret), but the store still lives under this user's
// Application Support and is written 700/600 — a security tool whose own
// records are readable by other accounts would be its own first finding.

public struct ScanRecord: Codable {
    public let date: Date
    public let kind: String        // ScanKind.rawValue
    public let result: ScanResult
}

/// What changed between the previous record of a kind and the current result.
public struct ScanDelta {
    public let new: [Finding]
    public let fixed: [Finding]
    public let since: Date
    public var isQuiet: Bool { new.isEmpty && fixed.isEmpty }
}

public final class HistoryStore {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Templeton Protect/history")
    }

    private func ensure() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    private func files(kind: String) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? [])
            .filter { $0.lastPathComponent.hasPrefix(kind + "-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The most recent record of this kind, if any scan has run before.
    public func previous(kind: String) -> ScanRecord? {
        guard let url = files(kind: kind).last,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScanRecord.self, from: data)
    }

    /// Compare against the previous record, then save this one.
    ///
    /// ⚠️ COMPARE FIRST, SAVE SECOND — the reverse order diffs a scan against
    /// itself and reports eternal quiet, which reads as safety and is a bug.
    @discardableResult
    public func record(kind: String, result: ScanResult, date: Date = Date()) -> ScanDelta? {
        let delta = previous(kind: kind).map { prev -> ScanDelta in
            let before = Dictionary(uniqueKeysWithValues: prev.result.findings.map { ($0.identity, $0) })
            let after = Dictionary(uniqueKeysWithValues: result.findings.map { ($0.identity, $0) })
            return ScanDelta(new: result.findings.filter { before[$0.identity] == nil },
                             fixed: prev.result.findings.filter { after[$0.identity] == nil },
                             since: prev.date)
        }
        // ISO stamp in the name so lexicographic order is time order.
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
        let name = "\(kind)-\(fmt.string(from: date).replacingOccurrences(of: ":", with: ""))" + ".json"
        do {
            try ensure()
            let data = try JSONEncoder().encode(ScanRecord(date: date, kind: kind, result: result))
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            prune(kind: kind)
        } catch {
            // ⚠️ A HISTORY THAT FAILED TO WRITE MUST NOT FAIL THE SCAN. The
            // findings on screen are the product; the record is the memory.
        }
        return delta
    }

    /// Keep the last 60 records per kind — enough for a year of weekly scans.
    private func prune(kind: String, keep: Int = 60) {
        let all = files(kind: kind)
        guard all.count > keep else { return }
        for url in all.prefix(all.count - keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// One line for the menu bar: when anything last ran, and what it held.
    public func lastRunLine() -> String? {
        let records = ["machine", "installations", "code"].compactMap { previous(kind: $0) }
        guard let latest = records.max(by: { $0.date < $1.date }) else { return nil }
        let total = records.reduce(0) { $0 + $1.result.findings.count }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        let when = fmt.localizedString(for: latest.date, relativeTo: Date())
        return total == 0 ? "Last scan \(when) — nothing found"
                          : "Last scan \(when) — \(total) finding\(total == 1 ? "" : "s") open"
    }
}
