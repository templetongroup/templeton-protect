import Foundation

// The scan. Read-only, always.
//
// ⚠️ NOTHING HERE OPENS A FILE FOR WRITING. Fixes live in Fix.swift and run only
// when somebody clicks. templetongroup/ai-structure-audit opens with the same
// rule — begin read-only, change nothing during the audit — and a scanner that
// touches anything has stopped being one.

public struct AiHome { public let tool: String; public let dir: String }

public let aiHomes: [AiHome] = [
    AiHome(tool: "Claude Code", dir: ".claude"),
    AiHome(tool: "Codex", dir: ".codex"),
    AiHome(tool: "OpenClaw", dir: ".openclaw"),
    AiHome(tool: "Hermes", dir: ".hermes"),
    AiHome(tool: "Cursor", dir: ".cursor"),
    AiHome(tool: "Aider", dir: ".aider"),
]

private let configNames = try! NSRegularExpression(
    pattern: #"^(\.credentials\.json|auth\.json|settings(\.local)?\.json|config\.(json|ya?ml|toml)|openclaw\.json|\.env(\..*)?)$"#)
private let transcriptExt = try! NSRegularExpression(pattern: #"\.(jsonl|md|log)$"#)

/// Vendor-specific enough that a match is worth acting on.
private let keyShapes: [(String, NSRegularExpression)] = [
    ("Anthropic", try! NSRegularExpression(pattern: #"\bsk-ant-[A-Za-z0-9_-]{20,}\b"#)),
    ("OpenAI", try! NSRegularExpression(pattern: #"\bsk-[A-Za-z0-9_-]{20,}\b"#)),
    ("GitHub", try! NSRegularExpression(pattern: #"\bgh[pousr]_[A-Za-z0-9]{30,}\b"#)),
    ("Google", try! NSRegularExpression(pattern: #"\bAIza[A-Za-z0-9_-]{30,}\b"#)),
    ("Slack", try! NSRegularExpression(pattern: #"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"#)),
    ("GitLab", try! NSRegularExpression(pattern: #"\bglpat-[A-Za-z0-9_-]{16,}\b"#)),
]

/// ⚠️ THE WHOLE BODY, NOT ITS FIRST FEW CHARACTERS. The TypeScript version's
/// first attempt matched a prefix list containing "abcd" and silently ate a real
/// key beginning "abcdef…" — a false negative, which for a scanner is the worse
/// half of the trade. Same mistake is not repeated here.
func isPlaceholder(_ body: String) -> Bool {
    if body.count > 5, Set(body).count == 1 { return true }
    let lowered = body.lowercased()
    for word in ["your", "example", "placeholder", "redacted", "sample", "dummy", "replace", "here", "xxxx"] {
        if lowered.contains(word) { return true }
    }
    return lowered.hasPrefix("xxxx") || lowered.hasPrefix("0000") || lowered.hasPrefix("1111")
}

/// ⚠️ THE CHEAP CHECK FIRST. NSRegularExpression over an 8 MB transcript is slow,
/// and almost no file contains a key at all — so a plain substring scan decides
/// the common case and the regex only runs on the few that could match. Without
/// this the packaged app took 24.7s on this Mac; with it, seconds.
private let keyHints = ["sk-", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "AIza", "xox", "glpat-"]
private let keyHintData: [Data] = keyHints.map { Data($0.utf8) }

/// Could this file contain a key at all, decided without turning it into a String.
///
/// ⚠️ MEASURED, NOT ASSUMED: 76 files are 78% of the bytes this scan touches on
/// one Mac — multi-megabyte agent transcripts. Building a Swift String out of
/// each was the entire cost. Memory-mapping and scanning the raw bytes decides
/// the common case for nothing, and only a file that might hold a key pays to be
/// decoded.
public func mightHoldKey(at path: String) -> Bool {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return false }
    // ⚠️ "sk-" MATCHES THE WORD "task-", AND AGENT TRANSCRIPTS ARE FULL OF THE
    // WORD TASK. The first pre-filter passed almost every file straight through
    // to a full decode, which is why the scan stayed at 23s however the search
    // itself was optimised — the filter was not filtering. Measured: walk, stat
    // and reachability together are 2.6s; everything else was decoding files
    // that never held a key.
    //
    // A key prefix is preceded by a quote, a space, a newline or nothing —
    // never by a letter. Checking the byte before each hit is what makes the
    // filter mean something.
    for hint in keyHintData {
        var from = data.startIndex
        while let r = data.range(of: hint, in: from..<data.endIndex) {
            if r.lowerBound == data.startIndex { return true }
            let prev = data[data.index(before: r.lowerBound)]
            let isLetter = (prev >= 65 && prev <= 90) || (prev >= 97 && prev <= 122) || (prev >= 48 && prev <= 57)
            if !isLetter { return true }
            from = data.index(after: r.lowerBound)
        }
    }
    return false
}



public func findKeys(in text: String) -> [String] {
    var possible = false
    for hint in keyHints where text.contains(hint) { possible = true; break }
    guard possible else { return [] }

    var vendors: [String] = []
    let range = NSRange(text.startIndex..., in: text)
    for (vendor, re) in keyShapes {
        for m in re.matches(in: text, range: range) {
            guard let r = Range(m.range, in: text) else { continue }
            var body = String(text[r])
            for prefix in ["sk-ant-", "sk-", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "AIza", "glpat-"] {
                if body.hasPrefix(prefix) { body = String(body.dropFirst(prefix.count)); break }
            }
            if isPlaceholder(body) { continue }
            vendors.append(vendor)
        }
    }
    return vendors
}

/// ⚠️ THE FILE MODE ALONE IS NOT THE ANSWER. A 644 file inside a 700 directory
/// is not reachable by another account, and reporting it as exposed is the false
/// positive that kills trust in a security tool. Checks the whole chain.
public func reachableByOthers(path: String, home: String) -> (Bool, String) {
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: path),
          let fileMode = attrs[.posixPermissions] as? NSNumber else { return (false, "") }
    let mode = fileMode.uint16Value
    var chain = [String(format: "%03o", mode)]
    guard mode & 0o044 != 0 else { return (false, chain.joined(separator: " → ")) }

    var dir = (path as NSString).deletingLastPathComponent
    var traversable = true
    for _ in 0..<12 {
        guard let a = try? fm.attributesOfItem(atPath: dir),
              let m = (a[.posixPermissions] as? NSNumber)?.uint16Value else { break }
        chain.append(String(format: "%03o", m))
        if m & 0o011 == 0 { traversable = false; break }
        if dir == home || dir == "/" { break }
        dir = (dir as NSString).deletingLastPathComponent
    }
    return (traversable, chain.joined(separator: " → "))
}

func looksSensitive(_ contents: String) -> Bool {
    if !findKeys(in: contents).isEmpty { return true }
    let re = try! NSRegularExpression(pattern: #""(access_?token|refresh_?token|api_?key|client_?secret|password|secret)"\s*:"#,
                                      options: .caseInsensitive)
    return re.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)) != nil
}

public func scanAiInstallations(home: String = NSHomeDirectory()) -> ScanResult {
    let fm = FileManager.default
    var findings: [Finding] = []
    var tools: [String] = []
    var filesRead = 0
    let maxRead = 24 * 1024 * 1024

    for ai in aiHomes {
        let root = (home as NSString).appendingPathComponent(ai.dir)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { continue }
        tools.append(ai.tool)

        // ⚠️ SKIP THE SUBTREE, DO NOT FILTER AFTER WALKING IT. The first version
        // enumerated everything and discarded node_modules afterwards — which on
        // this Mac meant walking 143,729 files under ~/.hermes alone, and the
        // packaged app sat on "Scanning" for over twenty seconds. Filtering a
        // path you have already paid to visit saves nothing.
        let rootURL = URL(fileURLWithPath: root)
        guard let walker = fm.enumerator(at: rootURL,
                                         includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                         // Hidden files are the whole point here — .claude, .env
                                         // and .credentials.json are all hidden.
                                         options: []) else { continue }
        while let item = walker.nextObject() as? URL {
            let name = item.lastPathComponent
            if name == "node_modules" || name == ".git" || name == "Cache" || name == "caches" {
                walker.skipDescendants()
                continue
            }
            // ⚠️ A CAP TOO. Agent history nests deeply and nothing worth finding
            // lives twelve directories down inside a package tree.
            if walker.level > 8 { walker.skipDescendants(); continue }
            let path = item.path
            let nr = NSRange(name.startIndex..., in: name)
            let isConfig = configNames.firstMatch(in: name, range: nr) != nil
            let isTranscript = transcriptExt.firstMatch(in: name, range: nr) != nil
            guard isConfig || isTranscript else { continue }

            guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
            guard (attrs[FileAttributeKey.type] as? FileAttributeType) == .typeRegular,
                  let size = (attrs[FileAttributeKey.size] as? NSNumber)?.intValue, size <= maxRead
            else { continue }
            filesRead += 1

            // A transcript only gets decoded if the byte scan found a hint. A
            // config is small and always worth reading — that is where the
            // reachability rule looks, and it does not depend on keys.
            if isTranscript && !mightHoldKey(at: path) { continue }
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            let display = path.replacingOccurrences(of: home, with: "~")
            let (reachable, chain) = reachableByOthers(path: path, home: home)

            if isTranscript {
                let vendors = findKeys(in: text)
                guard !vendors.isEmpty else { continue }
                let unique = Array(Set(vendors)).sorted()
                findings.append(Finding(
                    rule: "secrets-in-transcripts", layer: "harness",
                    severity: reachable ? .critical : .high,
                    title: "Live credentials are sitting in an agent transcript",
                    where_: display,
                    evidence: "\(vendors.count) key-shaped value(s) — \(unique.joined(separator: ", ")) — in a conversation log" + (reachable ? ", in a folder other accounts can read" : ""),
                    remedy: "Rotate those keys, then delete or prune this transcript.",
                    validation: "Re-run the scan; this file should report no key-shaped values.",
                    plain: "A conversation with an AI assistant was saved to disk, and \(vendors.count == 1 ? "a password-like key was" : "\(vendors.count) password-like keys were") left sitting in it in plain text" + (reachable ? " — in a folder other accounts on this Mac can read" : "") + ". Keys usually end up here because somebody pasted one into the chat, or a command printed one. These logs are kept forever and nothing clears them out.",
                    verified: true,
                    fix: FixAction(label: "Delete this transcript",
                                   describes: "Permanently removes \(display). You lose that conversation's history. It does NOT rotate the keys — only the service that issued them can do that.",
                                   kind: .deleteFile, target: display, mode: nil, destructive: true)))
                continue
            }

            guard reachable else { continue }
            let sensitive = looksSensitive(text)
            findings.append(Finding(
                rule: "credential-reachability", layer: "harness",
                severity: sensitive ? .critical : .low,
                title: sensitive ? "Another account on this Mac can read this file, and it holds credentials"
                                 : "Another account on this Mac can read this file",
                where_: display,
                evidence: "file and directory modes \(chain)",
                remedy: "chmod 600 \(display)" + (sensitive ? " — then rotate anything it contained" : ""),
                validation: "stat -f '%Lp' \(display) returns 600",
                plain: sensitive
                    ? "Anyone else who uses this Mac — and any program running under another account — can open this file and read the keys inside it."
                    : "Anyone else who uses this Mac can open this file. It holds no passwords, but it does list what your AI assistant is allowed to do without asking.",
                verified: true,
                fix: FixAction(label: "Make it private",
                               describes: "Sets \(display) so only your account can read it. Nothing is deleted and the file keeps working.",
                               kind: .chmod, target: display, mode: 0o600, destructive: false)))
        }
    }

    findings.sort { a, b in
        a.severity.rank != b.severity.rank ? a.severity.rank < b.severity.rank : a.where_ < b.where_
    }
    return ScanResult(findings: findings, toolsFound: tools, filesRead: filesRead)
}
