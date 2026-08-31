import Foundation

// What a finding is. Mirrors src/finding.ts deliberately.
//
// ⚠️ TWO IMPLEMENTATIONS OF THE SAME RULES IS A REAL COST, and it is taken with
// eyes open. The TypeScript engine serves the CLI, CI and AiOS; this one makes
// the Mac app self-contained — no Node on PATH, no localhost server, nothing to
// defend with tokens. The rules are small and their behaviour is pinned by the
// TypeScript tests; when one side changes, the other has to follow, and that is
// the price of a Mac app that cannot fail to launch because a runtime moved.

public enum Severity: String, Codable, CaseIterable {
    case critical, high, medium, low
    var rank: Int { Severity.allCases.firstIndex(of: self)! }
}

public struct FixAction: Codable {
    public enum Kind: String, Codable { case chmod, deleteFile }
    public let label: String
    public let describes: String
    public let kind: Kind
    public let target: String
    public let mode: UInt16?
    public let destructive: Bool
}

public struct Finding: Codable {
    public let rule: String
    public let layer: String
    public let severity: Severity
    public let title: String
    public let where_: String
    public let evidence: String
    public let remedy: String
    public let validation: String
    public let plain: String
    public let verified: Bool
    public let fix: FixAction?

    enum CodingKeys: String, CodingKey {
        case rule, layer, severity, title, evidence, remedy, validation, plain, verified, fix
        case where_ = "where"
    }
}

public struct ScanResult: Codable {
    public let findings: [Finding]
    public let toolsFound: [String]
    public let filesRead: Int
}

/// ⚠️ A SCANNER THAT PRINTS THE SECRET IT FOUND HAS COPIED IT SOMEWHERE NEW.
public func redact(_ text: String) -> String {
    let patterns = ["sk-[A-Za-z0-9_-]{12,}", "ghp_[A-Za-z0-9]{20,}", "AIza[A-Za-z0-9_-]{20,}",
                    "xox[baprs]-[A-Za-z0-9-]{10,}", "glpat-[A-Za-z0-9_-]{16,}", "aa_[A-Za-z0-9]{16,}"]
    var out = text
    for p in patterns {
        guard let re = try? NSRegularExpression(pattern: p) else { continue }
        out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                          withTemplate: "[redacted]")
    }
    return out
}

public struct FixOutcome: Codable {
    public let ok: Bool
    public let message: String
    // ⚠️ Explicit and public: a struct's memberwise init is internal, so without
    // this the app target cannot build one and the compiler blames Codable.
    public init(ok: Bool, message: String) { self.ok = ok; self.message = message }
}
