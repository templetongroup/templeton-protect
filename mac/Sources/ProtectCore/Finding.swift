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
    public var rank: Int { Severity.allCases.firstIndex(of: self)! }
}

public struct FixAction: Codable {
    /**
     ⚠️ `openSettings` DOES NOT FIX ANYTHING, AND THAT IS THE POINT. Turning the
     firewall on or switching off Remote Login needs an administrator, and an app
     that asks for admin rights so it can flip a system switch on your behalf is
     asking for more trust than a scanner has any business holding. The rule this
     project keeps instead is that a finding never leaves somebody with a
     sentence and no button — so the button opens the exact pane, and the person
     makes the change.
     */
    public enum Kind: String, Codable { case chmod, deleteFile, openSettings, redactInFile }
    public let label: String
    public let describes: String
    public let kind: Kind
    public let target: String
    public let mode: UInt16?
    public let destructive: Bool

    /// What the confirming button says.
    ///
    /// ⚠️ IT USED TO BE "Yes, delete it" FOR EVERY DESTRUCTIVE FIX, which was
    /// true while deleting a file was the only one. Redaction is destructive too
    /// and deletes nothing, so the button was describing the wrong action at the
    /// exact moment somebody was deciding whether to take it.
    public var confirmLabel: String {
        switch kind {
        case .deleteFile: return "Yes, delete it"
        case .redactInFile: return "Yes, remove the key"
        default: return "Yes, do it"
        }
    }
    public init(label: String, describes: String, kind: Kind, target: String,
                mode: UInt16?, destructive: Bool) {
        self.label = label; self.describes = describes; self.kind = kind
        self.target = target; self.mode = mode; self.destructive = destructive
    }
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
    /**
     ⚠️ A FIX BUTTON AND A REMEDY ARE NOT THE SAME AS KNOWING WHAT TO DO NEXT.
     Removing a key from a transcript changes nothing about whether that key
     still works; the step that matters happens on somebody else's website. This
     carries that step — in words, with the page as a button — rather than the
     name of a document. See NextSteps.swift for why the first version did not.
     */
    public let guidance: NextSteps?

    /**
     What makes this finding *this* finding.

     ⚠️ NOT THE PATH ALONE. Three scans now share one list, and the path was
     already doing double duty as the key for the fix outcomes and for the
     SwiftUI list. Two findings about the same file — a key in it and its being
     readable by other accounts — would collapse into one row, and applying a fix
     to either would report its result on both.
     */
    public var identity: String { "\(layer)/\(rule)/\(where_)" }

    enum CodingKeys: String, CodingKey {
        case rule, layer, severity, title, evidence, remedy, validation, plain, verified, fix, guidance
        case where_ = "where"
    }

    public init(rule: String, layer: String, severity: Severity, title: String,
                where_: String, evidence: String, remedy: String, validation: String,
                plain: String, verified: Bool, fix: FixAction?, guidance: NextSteps?) {
        self.rule = rule; self.layer = layer; self.severity = severity; self.title = title
        self.where_ = where_; self.evidence = evidence; self.remedy = remedy
        self.validation = validation; self.plain = plain; self.verified = verified
        self.fix = fix; self.guidance = guidance
    }
}

/**
 Which of the three scans a finding came from.

 ⚠️ THE THREE SCANS SHARE ONE FINDINGS LIST, DELIBERATELY. Somebody with a key in
 a transcript, a firewall that is off and an `.env` committed to a repository has
 one problem — this Mac — not three separate reports to read in sequence. The
 layer says where a finding came from so the list can be grouped and filtered;
 it does not split the assessment into three.
 */
public enum ScanKind: String, Codable, CaseIterable, Sendable {
    case machine, installations, code

    public var layer: String { rawValue == "installations" ? "harness" : rawValue }

    public var title: String {
        switch self {
        case .machine: return "Scan your hardware"
        case .installations: return "Scan your installations"
        case .code: return "Scan your code"
        }
    }

    public var blurb: String {
        switch self {
        case .machine:
            return "What this Mac is, and every setting that makes leaving an agent running on it riskier than it needs to be — encryption, the firewall, what it is sharing, what is listening to the network, and whether it ever sleeps or locks."
        case .installations:
            return "Every AI assistant installed here. Reads their conversation logs and configuration for credentials left behind, and for files another account on this Mac can open."
        case .code:
            return "A folder you choose. Finds keys committed to the repository, secrets an agent can read, and the code patterns that turn a mistake into a breach."
        }
    }

    public var icon: String {
        switch self {
        case .machine: return "desktopcomputer"
        case .installations: return "bubble.left.and.bubble.right.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    public static func from(layer: String) -> ScanKind {
        switch layer {
        case "machine": return .machine
        case "code": return .code
        default: return .installations
        }
    }
}



public struct ScanResult: Codable {
    public let findings: [Finding]
    public let toolsFound: [String]
    public let filesRead: Int
    public init(findings: [Finding], toolsFound: [String], filesRead: Int) {
        self.findings = findings; self.toolsFound = toolsFound; self.filesRead = filesRead
    }
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
