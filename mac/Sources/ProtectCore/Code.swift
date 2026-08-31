import Foundation

// Scan your code.
//
// The other half of the tagline. Point it at a folder you own and it reports the
// things in a codebase that turn a mistake into a breach: keys committed to the
// repository, secrets sitting where anything on the Mac can read them, and the
// handful of code shapes that are wrong every time they appear.
//
// ⚠️ EVERY RULE HERE IS ANCHORED TO SOMETHING DETERMINISTIC — a byte pattern, a
// file mode, an answer from git. That is the spine in docs/PRODUCT.md: a model
// may rank a finding and write its explanation, and may not be the only reason
// the finding exists. An AI security tool that invents a vulnerability costs a
// client a day of engineering time and is never trusted again, and unlike most
// bad output nobody can tell it is wrong by looking.
//
// ⚠️ AND SO THE CHEAP-BUT-NOISY RULES ARE NOT HERE. Entropy scoring finds every
// base64 blob in a test fixture; "password" as a substring finds every form
// label in the codebase. A scanner whose first page is wrong is one somebody
// closes, and then the four real findings underneath go unread too.

// ── what gets read ─────────────────────────────────────────────────────

/// ⚠️ SKIP THE SUBTREE, DO NOT FILTER AFTER WALKING IT. This is the same lesson
/// the installations scan already paid for: `node_modules` in one repo on this
/// Mac is 143,000 files, and filtering a path you have already paid to visit
/// saves nothing at all.
private let skipDirectories: Set<String> = [
    "node_modules", ".git", ".svn", ".hg", "vendor", "Pods", "Carthage",
    "dist", "build", "out", "target", ".next", ".nuxt", ".turbo", ".parcel-cache",
    ".venv", "venv", "env", "__pycache__", ".mypy_cache", ".pytest_cache",
    ".gradle", ".idea", ".vscode", "DerivedData", ".terraform", ".serverless",
    "coverage", ".cache", "Cache", "caches", ".DS_Store",
]

/// Extensions worth decoding. Everything else in a repository is an image, a
/// binary or a lockfile, and none of those hold a key in a form worth reporting.
private let sourceExtensions: Set<String> = [
    "js", "jsx", "ts", "tsx", "mjs", "cjs", "py", "rb", "go", "rs", "java", "kt",
    "swift", "m", "mm", "c", "h", "cc", "cpp", "hpp", "cs", "php", "pl", "sh",
    "bash", "zsh", "fish", "sql", "graphql", "vue", "svelte", "astro",
    "json", "yaml", "yml", "toml", "ini", "cfg", "conf", "properties",
    "xml", "plist", "tf", "tfvars", "gradle", "podspec", "md", "txt", "env",
]

/// Files whose *name* is the finding, whatever is inside them.
private let secretFileNames: Set<String> = [
    "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".npmrc", ".pypirc",
    ".netrc", "credentials", "service-account.json", "serviceAccountKey.json",
]
private let secretFileExtensions: Set<String> = ["pem", "p12", "pfx", "key", "keystore", "jks"]

private let maxFileSize = 4 * 1024 * 1024

// ── the extra key shapes a codebase brings ─────────────────────────────

/// ⚠️ VENDOR-SHAPED ONLY, LIKE THE TRANSCRIPT RULE. Each of these identifies its
/// issuer from the value alone, which is what makes a match worth waking
/// somebody for and what makes the remedy — go to that vendor and rotate — a
/// sentence rather than an investigation.
private let codeKeyShapes: [(String, NSRegularExpression)] = [
    ("AWS", try! NSRegularExpression(pattern: #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#)),
    ("Stripe", try! NSRegularExpression(pattern: #"\bsk_live_[0-9A-Za-z]{20,}\b"#)),
    ("SendGrid", try! NSRegularExpression(pattern: #"\bSG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b"#)),
    ("Twilio", try! NSRegularExpression(pattern: #"\bSK[0-9a-fA-F]{32}\b"#)),
    ("npm", try! NSRegularExpression(pattern: #"\bnpm_[A-Za-z0-9]{36}\b"#)),
    ("a private key file", try! NSRegularExpression(pattern: #"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----"#)),
]

private let codeKeyHints = ["AKIA", "ASIA", "sk_live_", "SG.", "npm_", "BEGIN", "SK"]

/**
 The shapes `redactKeys` will rewrite in place.

 ⚠️ NOT EVERY SHAPE THE FINDER KNOWS. A `-----BEGIN PRIVATE KEY-----` match is
 one line of a multi-line block, so replacing it leaves the body of the key
 behind and produces a file that lies about being clean. Twilio's shape is two
 letters and 32 hex digits, which a commit hash also satisfies — safe enough to
 report, not safe enough to edit somebody's file over. Redaction is the only
 thing here that writes, so it gets the narrower list.
 */
let keyShapesForRedaction: [(String, NSRegularExpression)] = keyShapes + [
    ("AWS", try! NSRegularExpression(pattern: #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#)),
    ("Stripe", try! NSRegularExpression(pattern: #"\bsk_live_[0-9A-Za-z]{20,}\b"#)),
    ("SendGrid", try! NSRegularExpression(pattern: #"\bSG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b"#)),
    ("npm", try! NSRegularExpression(pattern: #"\bnpm_[A-Za-z0-9]{36}\b"#)),
]

/// Which issuers this file leaks, transcript rules and code rules together.
func findCodeKeys(in text: String) -> [String] {
    var vendors = findKeys(in: text)
    let range = NSRange(text.startIndex..., in: text)
    for (vendor, re) in codeKeyShapes {
        guard re.firstMatch(in: text, range: range) != nil else { continue }
        // Twilio's shape is two letters and 32 hex digits, which a git commit
        // hash written as SK<sha> would also satisfy. Only claim it inside
        // something that looks like an assignment.
        if vendor == "Twilio", !text.contains("twilio") && !text.contains("TWILIO") { continue }
        vendors.append(vendor)
    }
    return vendors
}

// ── dangerous shapes ───────────────────────────────────────────────────

/// A code pattern that is wrong more or less every time it appears.
struct CodeSmell {
    let rule: String
    let title: String
    let severity: Severity
    let pattern: NSRegularExpression
    /// Cheap substring that decides whether the regex runs at all.
    let hint: String
    let plain: String
    let remedy: String
}

/// ⚠️ SHORT, AND EVERY ENTRY EARNS ITS PLACE. The temptation with this list is
/// to grow it to a hundred patterns so the product looks thorough; what that
/// actually produces is four hundred findings on a real repository, of which
/// three matter, which is precisely the wall of scanner output this product
/// exists to not be. Each of these is a construct with no legitimate use in
/// shipped code, so a hit is a finding rather than a conversation.
private let codeSmells: [CodeSmell] = [
    CodeSmell(
        rule: "tls-verification-disabled",
        title: "Certificate checking is switched off",
        severity: .high,
        // ⚠️ `--insecure` NEEDS THE COMMAND BESIDE IT. On its own the word appears
        // in documentation, in comments, in this file's own rule list — the first
        // version of this scanner reported itself. Requiring curl or wget on the
        // same line is what turns the string into evidence.
        pattern: try! NSRegularExpression(pattern: #"(rejectUnauthorized\s*:\s*false|NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*['"]?0|verify\s*=\s*False|InsecureSkipVerify\s*:\s*true|\b(?:curl|wget)\b[^\n]{0,80}\s(?:-k|--insecure|--no-check-certificate)\b)"#),
        hint: "",
        plain: "This code connects over HTTPS and then tells it not to check who is on the other end. Anyone positioned between this program and the server it is calling can read and change everything that passes — which is the entire thing HTTPS was there to prevent. It is almost always added to get past a certificate error on a developer's machine and then never taken out.",
        remedy: "Remove the flag. If a self-signed certificate is genuinely needed, trust that one certificate rather than turning the check off."),
    CodeSmell(
        rule: "shell-injection-shape",
        title: "A shell command built out of a variable",
        severity: .high,
        pattern: try! NSRegularExpression(pattern: #"(exec(Sync)?\s*\(\s*[`"'][^`"')]*\$\{|os\.system\s*\(\s*f?["'][^"')]*[\{%]|subprocess\.[A-Za-z_]+\([^)]*shell\s*=\s*True)"#),
        hint: "",
        plain: "A command line is being assembled by pasting a value into a string, then handed to a shell. If that value ever comes from outside — a form, a filename, an API response, or an AI assistant's output — whoever supplies it can append their own command and it runs with this program's permissions.",
        remedy: "Pass the arguments as a list instead of a string, so the shell never parses them. In Node that is execFile or spawn; in Python it is subprocess.run([...]) without shell=True."),
    CodeSmell(
        rule: "sql-string-concatenation",
        title: "A SQL query built by joining strings",
        severity: .high,
        // ⚠️ THE STATEMENT, NOT THE VERB. Matching on `select|insert|update|delete`
        // followed by an interpolation reported `\`Could not delete it: ${err}\`` as
        // SQL injection — an error message. A query is recognizable by its shape:
        // SELECT … FROM, INSERT INTO, UPDATE … SET, DELETE FROM. Anything looser
        // finds every template string in the codebase that contains a verb.
        pattern: try! NSRegularExpression(pattern: #"(?i)\b(?:select\s+[^;\n]{1,100}?\sfrom\s|insert\s+into\s|update\s+[A-Za-z_][\w.]*\s+set\s|delete\s+from\s)[^;\n]{0,120}?(\+\s*[A-Za-z_$][A-Za-z0-9_$.]*|\$\{[^}]+\}|%\s*\([A-Za-z_]|"\s*\.\s*\$)"#),
        hint: "",
        plain: "Part of this query is a value pasted into the text of the SQL. A value containing a quote mark ends the string early and the rest of it is read as more query — which is how a login form becomes a way to read every row in the database.",
        remedy: "Use a parameterized query: leave a placeholder in the SQL and pass the value separately, so the database never treats it as instructions."),
    CodeSmell(
        rule: "eval-on-a-variable",
        title: "Code is being built and then run",
        severity: .medium,
        // ⚠️ NO BARE `exec(`. It matched `exec(Sync)` in this file's own rule
        // list, and in real code `exec` is a method name on half the libraries
        // that exist. Building a shell command out of a variable is already the
        // rule above; this one is only about turning text into code.
        pattern: try! NSRegularExpression(pattern: #"(\beval\s*\(\s*[A-Za-z_$][A-Za-z0-9_$.]*\s*\)|new\s+Function\s*\(\s*[A-Za-z_$])"#),
        hint: "",
        plain: "A string is turned into running code. Whatever that string contains, this program will do — so anything that can influence the string can make this program run its own code.",
        remedy: "Parse the value instead of executing it. JSON.parse for data; a lookup table for a choice between known behaviors."),
    CodeSmell(
        rule: "git-remote-with-token",
        title: "A password is embedded in a git remote",
        severity: .critical,
        pattern: try! NSRegularExpression(pattern: #"https?://[A-Za-z0-9._%-]+:[A-Za-z0-9._%+-]{8,}@"#),
        hint: "@",
        plain: "A URL in this repository carries a username and a password or token in the address itself. URLs end up in logs, in error messages, in shell history and in anything that prints what it is about to fetch, so this credential has almost certainly been copied somewhere nobody is tracking.",
        remedy: "Take the credential out of the URL and rotate it — assume it is already known. Use a credential helper or an SSH key instead."),
]

/**
 Is this a test, a fixture or a sample?

 ⚠️ REPORTED QUIETLY, NOT SUPPRESSED. Test suites are full of realistic fake
 keys — this project's own suite has ten of them, and the first run of this
 scanner called them a critical credential leak. But suppressing the rule inside
 `tests/` would be worse: a real key pasted into a test is committed exactly like
 a real key pasted into a controller, and `tests/` is where nobody looks. So the
 finding survives, at the bottom of the list, saying what it actually knows.
 */
func looksLikeTestFile(_ path: String) -> Bool {
    let lower = path.lowercased()
    let base = ((lower as NSString).lastPathComponent)
    let segments = Set(lower.split(separator: "/").map(String.init))
    if !segments.isDisjoint(with: ["test", "tests", "spec", "specs", "__tests__",
                                   "fixtures", "fixture", "testdata", "examples",
                                   "example", "samples", "mocks", "__mocks__"]) { return true }
    return base.contains(".test.") || base.contains(".spec.")
        || base.contains("fixture") || base.contains("_test.") || base.hasPrefix("test_")
}

/// `.env.example` and its relatives are meant to be committed.
func envIsTemplate(_ base: String) -> Bool {
    let lower = base.lowercased()
    for suffix in ["example", "sample", "template", "dist", "defaults", "schema"] {
        if lower.hasSuffix("." + suffix) || lower.hasSuffix("-" + suffix) { return true }
    }
    return false
}

/// Machine-written, so a pattern found inside it names the wrong file.
///
/// ⚠️ BY SHAPE, NOT BY FOLDER NAME. The skip list has `.next` in it and this Mac
/// had a `.next-verify` beside it; a build directory can be called anything, and
/// one more name on a list only closes the case somebody already hit. What every
/// generated bundle has in common is that it has almost no lines.
func looksGenerated(_ base: String, _ text: String) -> Bool {
    let lower = base.lowercased()
    if lower.contains(".min.") || lower.contains("-min.") || lower.contains(".bundle.")
        || lower.hasSuffix(".map") { return true }
    guard text.utf8.count > 20_000 else { return false }
    let lines = text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    return text.utf8.count / lines > 400
}

// ── what the folder is, before anything is scanned ─────────────────────

/// A quick look at a chosen folder, for the card on the opening screen.
///
/// ⚠️ INSTANT, LIKE `detectInstallations`. This runs while somebody is still
/// deciding whether to press the button, so it counts entries under a cap and
/// never opens a file.
public struct CodeTarget: Sendable {
    public let path: String
    public let display: String
    public let isRepository: Bool
    public let files: Int
    public let atLeast: Bool
    public var headline: String {
        "\(display) · \(atLeast ? "\(files)+" : "\(files)") files\(isRepository ? " · git repository" : "")"
    }
}

private let previewCap = 3000

public func describeCodeTarget(_ path: String, home: String = NSHomeDirectory()) -> CodeTarget {
    let fm = FileManager.default
    var n = 0
    if let walk = fm.enumerator(at: URL(fileURLWithPath: path),
                                includingPropertiesForKeys: nil,
                                options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
        while let item = walk.nextObject() as? URL {
            if skipDirectories.contains(item.lastPathComponent) { walk.skipDescendants(); continue }
            n += 1
            if n >= previewCap { break }
        }
    }
    return CodeTarget(path: path,
                      display: path.replacingOccurrences(of: home, with: "~"),
                      isRepository: fm.fileExists(atPath: (path as NSString).appendingPathComponent(".git")),
                      files: n, atLeast: n >= previewCap)
}

// ── the scan ───────────────────────────────────────────────────────────

public func scanCode(at root: String, home: String = NSHomeDirectory()) -> ScanResult {
    scanCode(at: root, home: home, isCancelled: { false }, progress: { _ in })
}

public func scanCode(at root: String,
                     home: String = NSHomeDirectory(),
                     isCancelled: () -> Bool,
                     progress: (ScanProgress) -> Void) -> ScanResult {
    let fm = FileManager.default
    let name = (root as NSString).lastPathComponent
    var findings: [Finding] = []
    var filesRead = 0

    func display(_ path: String) -> String {
        var p = path.replacingOccurrences(of: home, with: "~")
        // Inside a chosen folder the repository-relative path is what a person
        // recognizes; the folder itself is already named at the top of the screen.
        if let r = p.range(of: "/\(name)/") { p = String(p[r.upperBound...]) }
        return p
    }

    // ── the tree ───────────────────────────────────────────────────────
    let ignored = gitIgnoredNames(root: root)
    guard let walker = fm.enumerator(at: URL(fileURLWithPath: root),
                                     includingPropertiesForKeys: [.isDirectoryKey],
                                     options: []) else {
        return ScanResult(findings: [], toolsFound: [name], filesRead: 0)
    }

    while let item = walker.nextObject() as? URL {
        if isCancelled() {
            return ScanResult(findings: sortedBySeverity(findings), toolsFound: [name], filesRead: filesRead)
        }
        let base = item.lastPathComponent
        if skipDirectories.contains(base) { walker.skipDescendants(); continue }
        if walker.level > 12 { walker.skipDescendants(); continue }

        let path = item.path
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              (attrs[.type] as? FileAttributeType) == .typeRegular else { continue }

        let ext = (base as NSString).pathExtension.lowercased()
        let isSecretFile = secretFileNames.contains(base) || secretFileExtensions.contains(ext)
        let isEnv = base == ".env" || base.hasPrefix(".env.")
        let isSource = sourceExtensions.contains(ext) || isEnv || base.hasPrefix(".")

        guard isSource || isSecretFile else { continue }
        guard let size = (attrs[.size] as? NSNumber)?.intValue, size <= maxFileSize else { continue }

        filesRead += 1
        progress(ScanProgress(tool: name, path: display(path), filesRead: filesRead,
                              findingsSoFar: findings.count,
                              finishedTool: nil, finishedFindings: nil))

        let (reachable, chain) = reachableByOthers(path: path, home: home)

        // ── a key file, by its name ────────────────────────────────────
        if isSecretFile {
            findings.append(Finding(
                rule: "private-key-in-tree", layer: "code",
                severity: reachable ? .critical : .high,
                title: "A private key is sitting in this folder",
                where_: display(path),
                evidence: "\(base), modes \(chain)" + (reachable ? " — readable by other accounts" : ""),
                remedy: "Move it out of the folder, add its name to .gitignore, and replace it with a path read from the environment.",
                validation: "Re-run the scan; this file should not be under the project folder.",
                plain: "This is the kind of file that unlocks something else — a server, a signing identity, a package registry. Anything with read access to this folder has it, and that includes every AI assistant you have pointed at this project."
                    + (reachable ? " Another account on this Mac can open it as well." : ""),
                verified: true,
                fix: reachable ? FixAction(label: "Make it private",
                                           describes: "Sets this file so only your account can read it. Nothing is moved or deleted.",
                                           kind: .chmod, target: path, mode: 0o600, destructive: false) : nil,
                guidance: NextSteps(title: "Get the key out of the project folder",
                    steps: [
                        "Move the file somewhere outside this project — `~/.ssh` for an SSH key, your password manager for anything else.",
                        "Point the code at the new location through an environment variable, so the path is configuration rather than a file in the tree.",
                        "Add its name to .gitignore, so a copy landing here again is not committed.",
                        "If this key was ever committed, replace it at whatever issued it. Removing a file from a repository does not remove it from the history.",
                    ])))
        }

        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

        // ── environment files ──────────────────────────────────────────
        if isEnv {
            let vendors = Array(Set(findCodeKeys(in: text))).sorted()

            if envIsTemplate(base) {
                // ⚠️ `.env.example` IS SUPPOSED TO BE COMMITTED. It is the
                // template, and reporting every project's template as a
                // gitignore mistake is a finding on every repository that does
                // this correctly. The only thing wrong with a template is a real
                // key in it — and that one is worth waking somebody for, because
                // a template is committed on purpose.
                if !vendors.isEmpty {
                    findings.append(Finding(
                        rule: "secret-in-env-template", layer: "code", severity: .critical,
                        title: "\(base) is a committed template and it holds real keys",
                        where_: display(path),
                        evidence: "contains \(vendors.joined(separator: ", ")) key-shaped values",
                        remedy: "Rotate these at the issuer, then replace the values in the template with obvious placeholders.",
                        validation: "Re-run the scan; this file should report no key-shaped values.",
                        plain: "This file exists to show other people which settings a project needs, so it is committed deliberately and everyone with the repository has read it. Somebody filled in their own working values instead of placeholders, which means those keys are in the history and in every clone.",
                        verified: true, fix: nil,
                        guidance: rotationSteps(vendors, found: "a file that is committed to the repository")))
                }
            } else if !ignored.contains(base) {
                findings.append(Finding(
                    rule: "env-not-ignored", layer: "code",
                    severity: vendors.isEmpty ? .high : .critical,
                    title: vendors.isEmpty
                        ? "\(base) is not in .gitignore"
                        : "\(base) holds live keys and is not in .gitignore",
                    where_: display(path),
                    evidence: ".gitignore does not cover \(base)"
                        + (vendors.isEmpty ? "" : "; contains \(vendors.joined(separator: ", ")) key-shaped values"),
                    remedy: "Add \(base) to .gitignore" + (vendors.isEmpty ? "." : ", rotate those keys, then remove the file from git history."),
                    validation: "git check-ignore \(base) prints the file.",
                    plain: "This is the file a project keeps its passwords in, and nothing is stopping it from being committed. One `git add .` and it is in the repository — and once it is in the history, deleting the file later does not take it back out."
                        + (vendors.isEmpty ? "" : " It currently holds keys for \(vendors.joined(separator: ", "))."),
                    verified: true, fix: nil,
                    guidance: NextSteps(title: "Stop this file reaching the repository",
                        steps: [
                            "Add a line to .gitignore with the file's name on it: `\(base)`.",
                            "Check it worked: `git check-ignore \(base)` should print the name back.",
                            "Ask git whether it is already tracking the file: `git ls-files \(base)`. If it prints anything, the file is in the history and the keys inside it have to be replaced.",
                            "Keep a `\(base).example` beside it with the setting names and no values, so the next person knows what to fill in.",
                        ])))
            }

            // ⚠️ GITIGNORED IS NOT PRIVATE. A .env that git will never commit is
            // still a plain file on a shared Mac, and this is the gap the
            // installations scan already covers for AI configuration — the same
            // rule has to hold for a project's own secrets file.
            if reachable, !vendors.isEmpty {
                findings.append(Finding(
                    rule: "env-reachable", layer: "code", severity: .critical,
                    title: "Another account on this Mac can read \(base)",
                    where_: display(path),
                    evidence: "file and directory modes \(chain); contains \(vendors.joined(separator: ", ")) key-shaped values",
                    remedy: "chmod 600 \(display(path))",
                    validation: "stat -f '%Lp' returns 600.",
                    plain: "Keeping this file out of git protects the repository. It does not protect the Mac: anyone else with an account here, and any program running under one, can open it and read the keys inside.",
                    verified: true,
                    fix: FixAction(label: "Make it private",
                                   describes: "Sets this file so only your account can read it. Nothing is deleted and the file keeps working.",
                                   kind: .chmod, target: path, mode: 0o600, destructive: false),
                    guidance: NextSteps(title: "Close it to the other accounts on this Mac",
                        steps: [
                            "Use the button above — it sets the file so only your account can open it, and changes nothing else.",
                            "Check the folders above it too. A private file inside a folder anyone can list still tells people it exists.",
                            "Anything that was in this file while it was readable should be treated as seen. If that is a live key, replace it.",
                        ])))
            }
        }

        // ── keys in a source file ──────────────────────────────────────
        if !isEnv {
            let vendors = findCodeKeys(in: text)
            if !vendors.isEmpty {
                let unique = Array(Set(vendors)).sorted()
                let fixture = looksLikeTestFile(path)
                findings.append(Finding(
                    rule: "secrets-in-source", layer: "code",
                    severity: fixture ? .low : .critical,
                    title: fixture
                        ? "Key-shaped values in a test file"
                        : "\(unique.joined(separator: " and ")) \(unique.count == 1 ? "credential" : "credentials") written into the code",
                    where_: display(path),
                    evidence: "\(vendors.count) key-shaped value(s) — \(unique.joined(separator: ", "))",
                    remedy: fixture
                        ? "Check these are fabricated. If any is a real key, rotate it at the issuer — a test file is committed like any other."
                        : "Rotate these at the issuer, then read them from the environment instead of writing them in the file.",
                    validation: "Re-run the scan; this file should report no key-shaped values.",
                    plain: fixture
                        ? "This file is a test, so these are probably invented keys that exist to prove the checker works. They are reported anyway and quietly, because a real key pasted into a test is committed exactly like a real key pasted anywhere else — and it is the one place people assume nobody is looking."
                        : "A live credential is typed into a source file. Everyone with the repository has it, every fork keeps it, and every AI assistant that has read this project has already seen it. Taking it out of the file does not make it safe — it has to be replaced at the service that issued it.",
                    verified: true, fix: nil,
                    guidance: fixture ? nil
                        : rotationSteps(unique, found: "a source file")))
            }
        }

        // ── the dangerous shapes ───────────────────────────────────────
        //
        // ⚠️ NOT IN GENERATED CODE. A minified bundle contains `eval(str)`
        // because a library three levels down does, and the fix is not in that
        // file — it is in a source file that is scanned anyway, or in a
        // dependency nobody here controls. Reporting the bundle points somebody
        // at 400 KB on one line. Keys are still read out of these, because a
        // credential baked into a bundle has shipped to every browser that
        // loaded it, which makes it worse rather than less interesting.
        if looksGenerated(base, text) { continue }
        for smell in codeSmells {
            if !smell.hint.isEmpty && !text.contains(smell.hint) { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let m = smell.pattern.firstMatch(in: text, range: range),
                  let r = Range(m.range, in: text) else { continue }
            let line = text[text.startIndex..<r.lowerBound].filter { $0 == "\n" }.count + 1
            let total = smell.pattern.numberOfMatches(in: text, range: range)
            findings.append(Finding(
                rule: smell.rule, layer: "code", severity: smell.severity,
                title: smell.title,
                where_: "\(display(path)):\(line)",
                // ⚠️ REDACTED, LIKE EVERYTHING ELSE THIS APP PRINTS. A git remote
                // with a token in it is both the finding and the secret, and
                // quoting the line verbatim would copy it onto the screen and
                // into every export.
                evidence: redact(String(text[r]).trimmingCharacters(in: .whitespaces).prefix(90).description)
                    + (total > 1 ? " — and \(total - 1) more in this file" : ""),
                remedy: smell.remedy,
                validation: "Re-run the scan; this file should no longer match.",
                plain: smell.plain,
                verified: true, fix: nil, guidance: nil))
        }
    }

    progress(ScanProgress(tool: name, path: "", filesRead: filesRead,
                          findingsSoFar: findings.count,
                          finishedTool: name, finishedFindings: findings.count))

    // ── what git is already carrying ───────────────────────────────────
    if fm.fileExists(atPath: (root as NSString).appendingPathComponent(".git")) {
        findings.append(contentsOf: gitFindings(root: root, name: name))
    }

    return ScanResult(findings: sortedBySeverity(findings), toolsFound: [name], filesRead: filesRead)
}

// ── git ────────────────────────────────────────────────────────────────

/// Names `.gitignore` covers, read literally.
///
/// ⚠️ NOT A GITIGNORE IMPLEMENTATION. Matching git's pattern rules properly is a
/// small project of its own — negations, directory anchoring, `**`, the ordering
/// between files — and getting it subtly wrong means telling somebody their
/// secrets file is safe when it is not. This reads the plain names, and anything
/// it cannot be sure about it treats as *not* ignored, so the failure lands on
/// the side of asking a question rather than granting a clean bill of health.
func gitIgnoredNames(root: String) -> Set<String> {
    var names = Set<String>()
    let path = (root as NSString).appendingPathComponent(".gitignore")
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return names }
    for raw in text.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("!") else { continue }
        let bare = line.hasSuffix("/") ? String(line.dropLast()) : line
        names.insert(bare)
        // ".env*" and "*.env" both cover ".env" and ".env.local".
        if bare == ".env*" || bare == "*.env" || bare == ".env.*" {
            names.formUnion([".env", ".env.local", ".env.production", ".env.development"])
        }
    }
    return names
}

/// What the repository is already carrying, asked of git rather than guessed.
private func gitFindings(root: String, name: String) -> [Finding] {
    var findings: [Finding] = []

    // ⚠️ THE TRACKED LIST, NOT THE WORKING TREE. A secrets file that was
    // committed once and deleted afterwards is still in the history and still
    // reachable by anybody with a clone; the file being absent today proves
    // nothing. This asks git what it is tracking right now, which is the part
    // that can be answered without walking every commit.
    if let tracked = run("/usr/bin/git", ["-C", root, "ls-files"], timeout: 20) {
        let committed = tracked.split(separator: "\n").map(String.init).filter { line in
            let base = (line as NSString).lastPathComponent
            let ext = (base as NSString).pathExtension.lowercased()
            return base == ".env" || base.hasPrefix(".env.")
                || secretFileNames.contains(base) || secretFileExtensions.contains(ext)
        }
        if !committed.isEmpty {
            findings.append(Finding(
                rule: "secrets-committed", layer: "code", severity: .critical,
                title: "\(committed.count) secrets \(committed.count == 1 ? "file is" : "files are") committed to this repository",
                where_: name,
                evidence: committed.prefix(6).joined(separator: ", ")
                    + (committed.count > 6 ? ", and \(committed.count - 6) more" : ""),
                remedy: "Rotate everything these hold, then remove them from the history with git filter-repo and force-push. Deleting the file in a new commit does not remove it.",
                validation: "git ls-files lists no .env or key files.",
                plain: "These files are in the repository's history, so they travel with every clone, every fork and every backup — and history is not something you can quietly edit, because everyone who already pulled has their own copy. Treat what is inside them as public and replace it at the issuer.",
                verified: true, fix: nil,
                guidance: NextSteps(title: "It is in the history, so the keys are the fix",
                    steps: [
                        "Replace every credential these files hold, at whatever issued it. This is the part that matters and it is the part people skip.",
                        "Add the names to .gitignore so it does not happen again.",
                        "Remove them from the history with `git filter-repo`, then force-push. A later commit that deletes the file does not remove it from earlier commits.",
                        "Tell anyone with a clone to re-clone. Their copy still has the old history in it.",
                    ])))
        }
    }

    // A remote with a credential in the URL. `git remote -v` prints it, which is
    // itself part of why this is bad.
    if let remotes = run("/usr/bin/git", ["-C", root, "remote", "-v"], timeout: 10) {
        let re = try! NSRegularExpression(pattern: #"https?://[A-Za-z0-9._%-]+:[A-Za-z0-9._%+-]{8,}@"#)
        for line in remotes.split(separator: "\n") {
            let s = String(line)
            guard re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil else { continue }
            let remoteName = s.split(separator: "\t").first.map(String.init) ?? "origin"
            findings.append(Finding(
                rule: "git-remote-credential", layer: "code", severity: .critical,
                title: "The \(remoteName) remote has a token in its address",
                where_: "\(name) → git remote \(remoteName)",
                evidence: "the remote URL carries a username and password",
                remedy: "Rotate the token, then set the remote to the plain https or ssh address: git remote set-url \(remoteName) <address>.",
                validation: "git remote -v shows no @ before the host.",
                plain: "Every git command that talks to this remote passes the token, and it is printed by anything that shows the remote — error messages, build logs, a screen share. Assume it is already somewhere it should not be and replace it.",
                verified: true, fix: nil,
                guidance: NextSteps(title: "Replace the token, then take it out of the URL",
                    steps: [
                        "Assume the token is known. It has been printed by every command that touched this remote.",
                        "Issue a replacement wherever it came from, and revoke the old one.",
                        "Set the remote to the plain address: `git remote set-url \(remoteName) https://github.com/owner/repo.git` — or the ssh form.",
                        "Let a credential helper hold the new token, so it never goes back into a URL.",
                    ])))
            break
        }
    }

    return findings
}
