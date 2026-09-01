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
    // ⚠️ terraform.tfstate EMBEDS the secrets of everything it manages —
    // database passwords, generated keys — in plain JSON. People commit it
    // because it looks like configuration. kubeconfig is a cluster login.
    "terraform.tfstate", "kubeconfig",
]
private let secretFileExtensions: Set<String> = ["pem", "p12", "pfx", "key", "keystore", "jks",
                                                 "tfstate", "kubeconfig"]

private let maxFileSize = 4 * 1024 * 1024

// ── the extra key shapes a codebase brings ─────────────────────────────

/// ⚠️ VENDOR-SHAPED ONLY, LIKE THE TRANSCRIPT RULE. Each of these identifies its
/// issuer from the value alone, which is what makes a match worth waking
/// somebody for and what makes the remedy — go to that vendor and rotate — a
/// sentence rather than an investigation.
private let codeKeyShapes: [(String, NSRegularExpression)] = [
    ("AWS", try! NSRegularExpression(pattern: #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#)),
    ("DigitalOcean", try! NSRegularExpression(pattern: #"\bdop_v1_[a-f0-9]{64}\b"#)),
    ("Stripe", try! NSRegularExpression(pattern: #"\bsk_live_[0-9A-Za-z]{20,}\b"#)),
    ("SendGrid", try! NSRegularExpression(pattern: #"\bSG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b"#)),
    ("Twilio", try! NSRegularExpression(pattern: #"\bSK[0-9a-fA-F]{32}\b"#)),
    ("npm", try! NSRegularExpression(pattern: #"\bnpm_[A-Za-z0-9]{36}\b"#)),
]

/**
 A PEM private key, header **and** body.

 ⚠️ NOT IN THE VENDOR LIST, AND NOT THE HEADER ALONE. It was both, and it cost
 two things at once. The header on its own matches prose: this project's own
 `NOTES.md` explains the PEM handling, and the scanner reported that sentence as
 a **critical** credential leak — the exact class of false positive the rest of
 this file exists to avoid, at the top of the report.

 It also read wrong even when it was right. Sitting in the vendor list, its name
 was substituted into a title built for issuers, producing "a private key file
 credential written into the code". A key with no issuer needs its own sentence.

 Requiring forty characters of base64 after the header is what separates a key
 from a sentence about keys.
 */
private let pemPrivateKey = try! NSRegularExpression(
    pattern: #"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----[\r\n\s]*(?:[A-Za-z-]+:.*[\r\n]+)*[A-Za-z0-9+/=]{40,}"#)

func holdsPrivateKey(_ text: String) -> Bool {
    pemPrivateKey.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

private let codeKeyHints = ["AKIA", "ASIA", "sk_live_", "SG.", "npm_", "SK", "eyJ"]

/**
 A JSON Web Token, decoded rather than pattern-matched.

 ⚠️ THE DECODE IS WHAT MAKES THIS SAFE TO SHIP. `eyJ…` three-part strings are
 everywhere — in test fixtures, in documentation, in expired session logs — and a
 regex alone would be the noisiest rule in the product. This one base64-decodes
 the payload, requires it to parse as JSON with real claims, and then **drops
 anything already expired**: a token whose `exp` has passed is not a credential,
 it is a string. What survives is a live token, which is worth waking somebody for.

 ⚠️ AND `service_role` IS ITS OWN CATEGORY. A Supabase service-role key bypasses
 every row-level security policy on the database — it is not "a key", it is the
 whole database. Naming it separately is the difference between a finding
 somebody triages next week and one they fix now.
 */
private let jwtShape = try! NSRegularExpression(
    pattern: #"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#)

private func base64urlDecode(_ s: String) -> Data? {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)
}

/// The vendors named by any live JWTs in this text.
func liveJWTs(in text: String) -> [String] {
    guard text.contains("eyJ") else { return [] }
    var out: [String] = []
    let range = NSRange(text.startIndex..., in: text)
    for m in jwtShape.matches(in: text, range: range) {
        guard let r = Range(m.range, in: text) else { continue }
        let parts = String(text[r]).split(separator: ".")
        guard parts.count == 3,
              let payload = base64urlDecode(String(parts[1])),
              let claims = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
        else { continue }
        // ⚠️ EXPIRED IS NOT LEAKED. Reporting a token that stopped working months
        // ago is the kind of finding that teaches somebody to skim the list.
        if let exp = claims["exp"] as? Double, exp < Date().timeIntervalSince1970 { continue }
        if let role = claims["role"] as? String, role == "service_role" {
            out.append("a Supabase service-role key")
        } else if claims["iss"] != nil || claims["sub"] != nil || claims["role"] != nil {
            out.append("a signed token")
        }
    }
    return out
}

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

/**
 A password inside a database URL — `postgres://user:PASSWORD@host`.

 The most common real leak in small-business code is not a vendor API key, it is
 the database connection string, because frameworks ask for it as one value and
 one value is what gets pasted.

 ⚠️ THE PASSWORD SEGMENT DECIDES, NOT THE URL SHAPE. Documentation is full of
 `postgres://user:password@localhost` — literally the word "password" — and every
 ORM's README has one. The captured segment goes through the placeholder test
 plus its own list of the words tutorials use, so only a value somebody actually
 chose gets reported.
 */
private let connectionString = try! NSRegularExpression(
    pattern: #"\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqps?|mssql)://([^:/\s'"]{1,64}):([^@/\s'"]{4,128})@"#)

private let tutorialPasswords: Set<String> = ["password", "pass", "pwd", "secret", "changeme",
                                              "postgres", "mysql", "root", "admin", "example",
                                              "test", "user", "username", "mypassword", "s3cret"]

func hasConnectionStringLeak(_ text: String) -> Bool {
    let range = NSRange(text.startIndex..., in: text)
    for m in connectionString.matches(in: text, range: range) {
        guard let r = Range(m.range(at: 2), in: text) else { continue }
        let pw = String(text[r])
        if pw.hasPrefix("$") || pw.hasPrefix("%") || pw.hasPrefix("{") { continue }
        if tutorialPasswords.contains(pw.lowercased()) || isPlaceholder(pw) { continue }
        return true
    }
    return false
}

/// Which issuers this file leaks, transcript rules and code rules together.
func findCodeKeys(in text: String) -> [String] {
    var vendors = findKeys(in: text)
    if hasConnectionStringLeak(text) { vendors.append("Database") }
    vendors += liveJWTs(in: text)
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
    /**
     File extensions this rule means anything in.

     ⚠️ WITHOUT THIS, THE SCANNER READS ITS OWN DOCUMENTATION AND REPORTS IT.
     Three false positives in a row came from the same place and only this fixes
     the class: `NOTES.md` explaining that a bundle contains `eval(str)`, this
     file's own comment saying the same, and a paragraph about PEM handling
     reported as a critical credential leak. Prose about code is not code —
     Markdown does not execute, and Swift has no `eval`.

     Keys are still read out of every file type, because a key pasted into a
     README is a leaked key. It is only the *pattern* rules that need to know
     which language they are looking at.
     */
    let plain: String
    let remedy: String
    let languages: Set<String>
}

/// The scripting languages where turning a string into code, or into a shell
/// command, is a thing that happens.
private let scripting: Set<String> = ["js", "jsx", "ts", "tsx", "mjs", "cjs",
                                      "vue", "svelte", "astro", "py", "rb", "php"]
/// Anywhere a query gets assembled.
private let queryHosts: Set<String> = scripting.union(["java", "kt", "go", "cs", "swift", "scala", "sql"])
/// Anywhere a request gets configured, including shell scripts and CI files.
private let requestHosts: Set<String> = queryHosts.union(
    ["sh", "bash", "zsh", "fish", "yaml", "yml", "toml", "json", "conf", "cfg", "ini", "tf"])

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
        remedy: "Remove the flag. If a self-signed certificate is genuinely needed, trust that one certificate rather than turning the check off.",
        languages: requestHosts),
    CodeSmell(
        rule: "shell-injection-shape",
        title: "A shell command built out of a variable",
        severity: .high,
        pattern: try! NSRegularExpression(pattern: #"(exec(Sync)?\s*\(\s*[`"'][^`"')]*\$\{|os\.system\s*\(\s*f?["'][^"')]*[\{%]|subprocess\.[A-Za-z_]+\([^)]*shell\s*=\s*True)"#),
        hint: "",
        plain: "A command line is being assembled by pasting a value into a string, then handed to a shell. If that value ever comes from outside — a form, a filename, an API response, or an AI assistant's output — whoever supplies it can append their own command and it runs with this program's permissions.",
        remedy: "Pass the arguments as a list instead of a string, so the shell never parses them. In Node that is execFile or spawn; in Python it is subprocess.run([...]) without shell=True.",
        languages: scripting),
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
        remedy: "Use a parameterized query: leave a placeholder in the SQL and pass the value separately, so the database never treats it as instructions.",
        languages: queryHosts),
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
        remedy: "Parse the value instead of executing it. JSON.parse for data; a lookup table for a choice between known behaviors.",
        languages: scripting),
    CodeSmell(
        rule: "curl-pipe-shell",
        title: "A script downloads code and runs it in one motion",
        severity: .high,
        pattern: try! NSRegularExpression(pattern: #"\b(?:curl|wget)\b[^\n|]{0,120}\|\s*(?:sudo\s+)?(?:ba|z)?sh\b"#),
        hint: "|",
        plain: "curl-pipe-to-shell runs whatever the server sends, the moment it arrives — there is no file to inspect, no checksum, and if the download is interrupted, half a script runs. With sudo in the pipe, it does all of that as root. Install scripts ship this pattern because it makes a nice one-liner; that is the whole case for it.",
        remedy: "Download to a file, read it, then run the file. If the vendor publishes a checksum, check it.",
        languages: requestHosts),
    CodeSmell(
        rule: "git-remote-with-token",
        title: "A password is embedded in a git remote",
        severity: .critical,
        pattern: try! NSRegularExpression(pattern: #"https?://[A-Za-z0-9._%-]+:[A-Za-z0-9._%+-]{8,}@"#),
        hint: "@",
        plain: "A URL in this repository carries a username and a password or token in the address itself. URLs end up in logs, in error messages, in shell history and in anything that prints what it is about to fetch, so this credential has almost certainly been copied somewhere nobody is tracking.",
        remedy: "Take the credential out of the URL and rotate it — assume it is already known. Use a credential helper or an SSH key instead.",
        languages: requestHosts),
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

        // ── a private key written inside another file ──────────────────
        if !isSecretFile, holdsPrivateKey(text) {
            findings.append(Finding(
                rule: "private-key-in-file", layer: "code",
                severity: reachable ? .critical : .high,
                title: "A private key is written into this file",
                where_: display(path),
                evidence: "a PEM private key block, modes \(chain)"
                    + (reachable ? " — readable by other accounts" : ""),
                remedy: "Replace the key at whatever issued it, then load it from a file outside the project or from the environment.",
                validation: "Re-run the scan; this file should hold no PEM block.",
                plain: "A private key is pasted into this file rather than kept in one of its own. Whatever it unlocks is available to everyone with a copy of this project, and a key in a source file travels into every clone and every backup of it."
                    + (reachable ? " Another account on this Mac can open it as well." : ""),
                verified: true, fix: nil,
                guidance: NextSteps(title: "Replace it, then keep the next one out of the tree",
                    steps: [
                        "Assume this key is known and issue a replacement wherever it came from.",
                        "Revoke the old one. A key that is replaced but not revoked still opens the door.",
                        "Keep the new key in a file of its own outside the project, and read its path from an environment variable.",
                        "If this file has been committed, the key is in the history — see whether `git log -p` reaches it before deciding it is handled.",
                    ])))
        }

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

        // ── inline passwords in a compose file ─────────────────────────
        if base.hasPrefix("docker-compose") || base.hasPrefix("compose."),
           ext == "yml" || ext == "yaml" {
            let re = try! NSRegularExpression(
                pattern: ##"(?im)^\s*[A-Z0-9_]*(?:PASSWORD|SECRET|TOKEN)[A-Z0-9_]*\s*[:=]\s*['"]?([^\s'"#${%]{4,})"##)
            let hits = re.matches(in: text, range: NSRange(text.startIndex..., in: text)).filter { m in
                guard let r = Range(m.range(at: 1), in: text) else { return false }
                let v = String(text[r])
                return !tutorialPasswords.contains(v.lowercased()) && !isPlaceholder(v)
            }
            if !hits.isEmpty {
                findings.append(Finding(
                    rule: "compose-inline-password", layer: "code", severity: .high,
                    title: "Passwords written into a compose file",
                    where_: display(path),
                    evidence: "\(hits.count) inline credential value(s) under PASSWORD/SECRET/TOKEN keys",
                    remedy: "Move the values to an env file that .gitignore covers, and reference them: ${VAR}. Compose reads .env automatically.",
                    validation: "The compose file carries ${VAR} references, not values.",
                    plain: "This file describes how your services start, and the passwords they start with are typed straight into it. Compose files are committed almost by definition — they are the setup instructions — so these values travel with every copy of the project.",
                    verified: true, fix: nil,
                    guidance: NextSteps(title: "Reference the secrets instead of writing them",
                        steps: [
                            "Create a .env file next to the compose file and move each value into it.",
                            "Replace each value in the compose file with ${THE_VAR_NAME} — compose fills them in automatically.",
                            "Add .env to .gitignore, and check the compose file's history: if it was ever committed with the values in it, rotate them.",
                        ])))
            }
        }

        // ── install scripts that run on npm install ────────────────────
        //
        // ⚠️ A postinstall RUNS WITHOUT ANYONE ASKING, on every `npm install`,
        // with the developer's permissions — which is exactly why it is the
        // supply-chain attacker's favourite door. Flagged only when it fetches
        // or evaluates something, because a postinstall that runs `tsc` is
        // ordinary and reporting it would be noise.
        if base == "package.json", walker.level <= 2 {
            let re = try! NSRegularExpression(
                pattern: #""(?:pre|post)?install"\s*:\s*"([^"]*(?:curl|wget|\bnode\s+-e|\beval\b|base64\s+-d|\|\s*(?:ba|z)?sh)[^"]*)""#)
            if let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(m.range(at: 1), in: text) {
                findings.append(Finding(
                    rule: "install-script-fetches", layer: "code", severity: .high,
                    title: "An install script downloads and runs code",
                    where_: display(path),
                    evidence: redact(String(text[r]).prefix(90).description),
                    remedy: "Move the work into a build step somebody runs deliberately, or vendor what it fetches and check it in.",
                    validation: "No install script in package.json fetches or evaluates code.",
                    plain: "This runs by itself every time anyone installs the project's dependencies — on your machine, on your colleagues', and in CI — with whatever permissions that person has. It fetches code from the network and runs it, so what executes is whatever that server returns on the day, and nobody reviews it.",
                    verified: true, fix: nil,
                    guidance: NextSteps(title: "Take the automatic execution out of it",
                        steps: [
                            "Read what the script fetches, and from where. If you cannot say who controls that address, that is the finding.",
                            "Move it to an explicit script somebody runs on purpose — `npm run setup` rather than a postinstall.",
                            "If it must stay automatic, vendor the file into the repository and check its checksum instead of fetching it.",
                        ])))
            }
        }

        // ── dependencies fetched outside the registry ──────────────────
        if base == "package.json", walker.level <= 2 {
            let re = try! NSRegularExpression(
                pattern: #""[^"]+"\s*:\s*"(?:git\+|github:|git://|https?://(?!registry\.))[^"]*""#)
            let n = re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if n > 0, text.contains("\"dependencies\"") || text.contains("\"devDependencies\"") {
                findings.append(Finding(
                    rule: "git-url-dependency", layer: "code", severity: .low,
                    title: "\(n == 1 ? "A dependency comes" : "\(n) dependencies come") straight from a URL",
                    where_: display(path),
                    evidence: "\(n) dependency value(s) point at git or http URLs rather than the registry",
                    remedy: "Prefer registry versions, or pin the URL to a full commit hash so the code cannot change under you.",
                    validation: "Dependency values are registry versions or hash-pinned URLs.",
                    plain: "Packages from the registry are what everyone else installs and are integrity-checked against the lockfile. A dependency pointing at a URL is whatever that URL serves at install time — if the branch moves or the account is taken over, the next install is different code and looks identical.",
                    verified: true, fix: nil, guidance: nil))
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
        // ⚠️ A DANGEROUS SHAPE IN A TEST IS USUALLY THE TEST OF THE SHAPE.
        // Every fixture in this project's own suite is a real curl-pipe or SQL
        // concatenation on purpose. Reported, so a genuinely dangerous test
        // still surfaces, but a notch quieter — the same call the key rule makes.
        let inTest = looksLikeTestFile(path)
        for smell in codeSmells {
            guard smell.languages.contains(ext) else { continue }
            if !smell.hint.isEmpty && !text.contains(smell.hint) { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let m = smell.pattern.firstMatch(in: text, range: range),
                  let r = Range(m.range, in: text) else { continue }
            let line = text[text.startIndex..<r.lowerBound].filter { $0 == "\n" }.count + 1
            let total = smell.pattern.numberOfMatches(in: text, range: range)
            findings.append(Finding(
                rule: smell.rule, layer: "code",
                severity: inTest ? .low : smell.severity,
                title: inTest ? "\(smell.title) — in a test file" : smell.title,
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

// ── the repository's history, on request ───────────────────────────────

/**
 Search history for secrets that a scan of today's files cannot see.

 ⚠️ A BUTTON, NOT A DEFAULT. `git log` over every commit of a real repository is
 seconds to minutes of work, and the everyday scan has to stay something people
 run without thinking about it. This runs when the deep-scan toggle is on.

 Two questions, both answered by git itself rather than by walking blobs:
 - was a secrets-shaped FILE ever added, even if deleted since? (`--diff-filter=A
   --name-only` over all history — one command, fast)
 - did key-shaped TEXT ever appear in a diff? (pickaxe, one pass per hint, with
   hints specific enough that "task-" does not light up "sk-")
 */
public func scanGitHistory(at root: String, isCancelled: () -> Bool = { false }) -> [Finding] {
    guard FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent(".git"))
    else { return [] }
    var findings: [Finding] = []
    let name = (root as NSString).lastPathComponent

    // Files ever added whose name is the finding.
    if let out = run("/usr/bin/git", ["-C", root, "log", "--all", "--diff-filter=A",
                                      "--name-only", "--format="], timeout: 60) {
        let everAdded = Set(out.split(separator: "\n").map(String.init)).filter { line in
            let base = (line as NSString).lastPathComponent
            let ext = (base as NSString).pathExtension.lowercased()
            return base == ".env" || base.hasPrefix(".env.") && !envIsTemplate(base)
                || secretFileNames.contains(base) || secretFileExtensions.contains(ext)
        }
        // What ls-files already reports today is covered by secrets-committed;
        // history-only entries are the ones nothing else can see.
        let trackedNow = Set((run("/usr/bin/git", ["-C", root, "ls-files"], timeout: 30) ?? "")
            .split(separator: "\n").map(String.init))
        let historyOnly = everAdded.subtracting(trackedNow).sorted()
        if !historyOnly.isEmpty {
            findings.append(Finding(
                rule: "secrets-in-history", layer: "code", severity: .critical,
                title: "\(historyOnly.count) secrets \(historyOnly.count == 1 ? "file was" : "files were") committed and later deleted",
                where_: name,
                evidence: historyOnly.prefix(6).joined(separator: ", ")
                    + (historyOnly.count > 6 ? ", and \(historyOnly.count - 6) more" : ""),
                remedy: "Rotate everything they held, then remove them from history with git filter-repo and force-push. The deleting commit did not remove them.",
                validation: "git log --all --diff-filter=A --name-only lists no secrets files.",
                plain: "These files are gone from the folder and still in the repository — deleting a file adds a commit on top; it does not take the file out of the ones underneath. Anyone with a clone can check out the commit before the deletion and read them. This is the leak a scan of today's files cannot see, which is what the deep scan is for.",
                verified: true, fix: nil,
                guidance: NextSteps(title: "History is append-only, so the keys are the fix",
                    steps: [
                        "Rotate every credential those files held, at whatever issued it — do this first, because everything after it is cleanup.",
                        "Remove the files from history: `git filter-repo --invert-paths --path <file>` and force-push.",
                        "Tell anyone with a clone to re-clone; their copy keeps the old history until they do.",
                    ])))
        }
    }

    // Key-shaped text anywhere in the diffs.
    if !isCancelled() {
        let pickaxeHints = ["sk-ant-", "sk-proj-", "ghp_", "AKIA", "glpat-", "sk_live_", "dop_v1_"]
        var hit: [String] = []
        for hint in pickaxeHints {
            if isCancelled() { break }
            guard let out = run("/usr/bin/git", ["-C", root, "log", "--all", "-S", hint,
                                                 "--format=%H"], timeout: 60),
                  !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            hit.append(hint)
        }
        if !hit.isEmpty {
            findings.append(Finding(
                rule: "keys-in-history", layer: "code", severity: .high,
                title: "Key-shaped values appear in this repository's history",
                where_: name,
                evidence: "commits touch text beginning " + hit.joined(separator: ", "),
                remedy: "Find them with `git log --all -S <prefix> -p`, rotate what is live, then decide whether the history is worth rewriting.",
                validation: "The pickaxe search returns no commits after a rewrite.",
                plain: "At some point, text shaped like an API key was added to or removed from a file in this repository. Even if no current file holds it, the commits do, and commits travel with every clone. Worth ten minutes with the command in the remedy to see which keys, and whether they still work.",
                verified: true, fix: nil, guidance: nil))
        }
    }

    return findings
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
