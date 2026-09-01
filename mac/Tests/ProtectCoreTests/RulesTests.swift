import XCTest
@testable import ProtectCore

// The Swift rules, pinned where they live (TG-291).
//
// The TypeScript suite in ../tests pins the installations rules it was written
// against, and stays as the cross-check for the engine the CLI used to be. This
// suite is the one that grows: every rule that exists only in Swift gets its
// behavior fixed here, because five false positives in one day proved that
// "verified by reading Probe's output" is a person, not a suite.

final class KeyDetectionTests: XCTestCase {
    func testRealKeysAreFound() {
        XCTAssertEqual(findKeys(in: "sk-proj-9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6u").count, 1)
        XCTAssertEqual(findKeys(in: "ghp_9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6uQ2xZ").count, 1)
        XCTAssertEqual(findKeys(in: "AIzaSyD9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6u").count, 1)
    }

    func testPlaceholdersAreNotKeys() {
        XCTAssertEqual(findKeys(in: "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx").count, 0)
        XCTAssertEqual(findKeys(in: "sk-YOUR-API-KEY-HERE-REPLACE-THIS-NOW").count, 0)
        XCTAssertEqual(findKeys(in: "use sk-EXAMPLE-KEY-PLACEHOLDER-VALUE-X").count, 0)
    }

    /// ⚠️ The TS version's first attempt matched a prefix list containing "abcd"
    /// and silently ate a real key beginning "abcdef…". Pinned on both sides.
    func testKeyStartingLikeAPlaceholderIsStillAKey() {
        XCTAssertEqual(findKeys(in: "sk-abcdefghijklmnopqrstuvwxyz012345").count, 1)
    }

    func testRedactRemovesTheValue() {
        let out = redact("found sk-proj-9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6u in the log")
        XCTAssertFalse(out.contains("9fKq2mZx7RtY4wLpN8vBcD3eHjA1sG6u"))
        XCTAssertTrue(out.contains("[redacted]"))
    }
}

final class RedactKeysTests: XCTestCase {
    func testReplacesKeysAndNamesTheVendor() {
        let text = "key sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345 and ghp_AbCdEfGh1jKlMn0pQrStUvWxYz01234567"
        let (out, removed) = redactKeys(text)
        XCTAssertEqual(removed, 2)
        XCTAssertTrue(out.contains("[OpenAI key removed by Templeton Protect]"))
        XCTAssertTrue(out.contains("[GitHub key removed by Templeton Protect]"))
        XCTAssertTrue(findKeys(in: out).isEmpty)
    }

    func testPlaceholderAndUnicodeSurvive() {
        let text = "sk-YOUR-KEY-HERE-REPLACE-THIS-NOW stays; café ✓ 日本語 — em dash"
        let (out, removed) = redactKeys(text)
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(out, text)
    }

    func testLineCountIsUnchanged() {
        let text = "a\nsk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345\nc\n"
        let (out, _) = redactKeys(text)
        XCTAssertEqual(out.filter { $0 == "\n" }.count, text.filter { $0 == "\n" }.count)
    }
}

final class PEMTests: XCTestCase {
    /// ⚠️ The header alone matched prose — this project's own NOTES.md was
    /// reported as a critical credential leak. The body is what makes it a key.
    func testProseAboutPEMIsNotAKey() {
        XCTAssertFalse(holdsPrivateKey("A `-----BEGIN PRIVATE KEY-----` match is one line of a block."))
    }

    func testARealPEMBlockIsAKey() {
        let pem = "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDLxYz012345abcd\n-----END PRIVATE KEY-----"
        XCTAssertTrue(holdsPrivateKey(pem))
    }
}

final class CodeScanFixtureTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("protect-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ name: String, _ contents: String) throws {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func rules(_ r: ScanResult) -> [String] { r.findings.map(\.rule) }

    /// ⚠️ Markdown does not execute. The scanner reported its own NOTES.md.
    func testProseAboutEvalIsNotAFinding() throws {
        try write("NOTES.md", "A bundle contains eval(str) because a library does.")
        XCTAssertFalse(rules(scanCode(at: dir.path)).contains("eval-on-a-variable"))
    }

    func testEvalOnAVariableInScriptIsAFinding() throws {
        try write("app.js", "const r = eval(userInput)\n")
        XCTAssertTrue(rules(scanCode(at: dir.path)).contains("eval-on-a-variable"))
    }

    func testSQLStatementShapeIsRequired() throws {
        // An error message with the word "delete" is not SQL — this exact string
        // was reported as injection on the first run.
        try write("fix.ts", #"const m = `Could not delete it: ${err}`;"#)
        XCTAssertFalse(rules(scanCode(at: dir.path)).contains("sql-string-concatenation"))
        try write("db.ts", #"const q = `SELECT id FROM users WHERE name = '${name}'`;"#)
        XCTAssertTrue(rules(scanCode(at: dir.path)).contains("sql-string-concatenation"))
    }

    func testInsecureFlagNeedsItsCommand() throws {
        try write("doc.sh", "echo 'never pass --insecure to anything'\n")
        XCTAssertFalse(rules(scanCode(at: dir.path)).contains("tls-verification-disabled"))
        try write("get.sh", "curl https://x.example --insecure -o out\n")
        XCTAssertTrue(rules(scanCode(at: dir.path)).contains("tls-verification-disabled"))
    }

    /// ⚠️ .env.example is meant to be committed; only a real key in it is wrong.
    func testEnvTemplateIsQuietUnlessItHoldsKeys() throws {
        try write(".env.example", "OPENAI_API_KEY=\n")
        XCTAssertFalse(rules(scanCode(at: dir.path)).contains("env-not-ignored"))
        try write(".env.example", "OPENAI_API_KEY=sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345\n")
        XCTAssertTrue(rules(scanCode(at: dir.path)).contains("secret-in-env-template"))
    }

    func testEnvWithoutGitignoreIsAFinding() throws {
        try write(".env", "OPENAI_API_KEY=sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345\n")
        let found = scanCode(at: dir.path).findings.first { $0.rule == "env-not-ignored" }
        XCTAssertEqual(found?.severity, .critical)
    }

    func testGitignoredEnvIsNotAFinding() throws {
        try write(".gitignore", ".env\n")
        try write(".env", "X=1\n")
        XCTAssertFalse(rules(scanCode(at: dir.path)).contains("env-not-ignored"))
    }

    /// ⚠️ Reported quietly, never suppressed — tests/ is where nobody looks.
    func testKeysInTestFilesAreLowSeverity() throws {
        try write("tests/rules.test.mjs", "const k = 'sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345'\n")
        let f = scanCode(at: dir.path).findings.first { $0.rule == "secrets-in-source" }
        XCTAssertEqual(f?.severity, .low)
    }

    func testKeysInSourceAreCritical() throws {
        try write("config.js", "const k = 'sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345'\n")
        let f = scanCode(at: dir.path).findings.first { $0.rule == "secrets-in-source" }
        XCTAssertEqual(f?.severity, .critical)
    }

    func testGeneratedBundlesAreSkippedForPatterns() throws {
        let minified = "var a=1;" + String(repeating: "f(eval(str));", count: 4000)
        try write("dist2/app.bundle.js", minified)
        XCTAssertFalse(rules(scanCode(at: dir.path)).contains("eval-on-a-variable"))
    }
}

final class ExportTests: XCTestCase {
    func testCSVCellsAreRFC4180Quoted() {
        XCTAssertEqual(csvCell("a,b"), "\"a,b\"")
        XCTAssertEqual(csvCell("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(csvCell("plain"), "plain")
    }

    /// ⚠️ A report carrying the key it found has copied it somewhere new.
    func testExportsNeverCarryAKey() {
        let f = Finding(rule: "secrets-in-source", layer: "code", severity: .critical,
                        title: "t", where_: "x.js",
                        evidence: "found sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345",
                        remedy: "r", validation: "v", plain: "p", verified: true,
                        fix: nil, guidance: nil)
        let r = ScanResult(findings: [f], toolsFound: ["x"], filesRead: 1)
        XCTAssertFalse(exportMarkdown(r).contains("Ab3dEfGh1jKlMn0pQrStUvWxYz012345"))
        XCTAssertFalse(exportCSV(r).contains("Ab3dEfGh1jKlMn0pQrStUvWxYz012345"))
    }
}

final class FixTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("protect-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testRedactInFileRemovesOnlyTheKeys() throws {
        let file = home.appendingPathComponent(".claude/s.jsonl")
        try "line sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345 end\nplain line\n"
            .write(to: file, atomically: true, encoding: .utf8)
        let fix = FixAction(label: "", describes: "", kind: .redactInFile,
                            target: "~/.claude/s.jsonl", mode: nil, destructive: false)
        let out = applyFix(fix, home: home.path)
        XCTAssertTrue(out.ok, out.message)
        let after = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(findKeys(in: after).isEmpty)
        XCTAssertTrue(after.contains("plain line"))
    }

    /// ⚠️ "~/.claude/../../etc/passwd" must fail loudly, not resolve quietly.
    func testPathEscapeIsRefused() {
        let fix = FixAction(label: "", describes: "", kind: .chmod,
                            target: "~/.claude/../../etc/hosts", mode: 0o600, destructive: false)
        XCTAssertFalse(applyFix(fix, home: home.path).ok)
    }

    func testChmodConfirmsItTook() throws {
        let file = home.appendingPathComponent(".claude/c.json")
        try "{}".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        let fix = FixAction(label: "", describes: "", kind: .chmod,
                            target: "~/.claude/c.json", mode: 0o600, destructive: false)
        XCTAssertTrue(applyFix(fix, home: home.path).ok)
        let mode = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(mode, 0o600)
    }
}

final class InstallationsFixtureTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("protect-inst-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testAKeyInATranscriptIsFoundAndTheFixIsNotDestructive() throws {
        let f = home.appendingPathComponent(".claude/session.jsonl")
        try #"{"text":"key sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345"}"#
            .write(to: f, atomically: true, encoding: .utf8)
        let r = scanAiInstallations(home: home.path)
        let finding = r.findings.first { $0.rule == "secrets-in-transcripts" }
        XCTAssertNotNil(finding)
        // ⚠️ The fix is redaction. "Delete this transcript" shipped once and
        // it was the destructive option Tony vetoed.
        XCTAssertEqual(finding?.fix?.kind, .redactInFile)
        XCTAssertEqual(finding?.fix?.destructive, false)
    }

    func testReachabilityChecksTheWholeChain() throws {
        // A 644 file inside a 700 directory is NOT reachable.
        let sub = home.appendingPathComponent(".claude/private")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sub.path)
        let f = sub.appendingPathComponent("x.json").path
        try "{}".write(toFile: f, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f)
        XCTAssertFalse(reachableByOthers(path: f, home: home.path).0)
    }
}

final class AgentAuditTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("protect-agents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func write(_ name: String, _ contents: String) throws {
        let url = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func rules() -> [String] { auditAgents(home: home.path).map(\.rule) }

    func testUnpinnedNpxServerIsFlagged() throws {
        try write(".claude.json", #"{"mcpServers":{"files":{"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem","/tmp"]}}}"#)
        XCTAssertTrue(rules().contains("mcp-unpinned-package"))
    }

    func testPinnedServerIsNot() throws {
        try write(".claude.json", #"{"mcpServers":{"files":{"command":"npx","args":["@scope/server@1.2.3"]}}}"#)
        XCTAssertFalse(rules().contains("mcp-unpinned-package"))
    }

    func testCredentialInEnvIsFlaggedByNameNotValue() throws {
        try write(".claude.json", #"{"mcpServers":{"api":{"command":"/usr/local/bin/x","env":{"SERVICE_API_KEY":"sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345"}}}}"#)
        let f = auditAgents(home: home.path).first { $0.rule == "mcp-credential-in-config" }
        XCTAssertNotNil(f)
        // ⚠️ The evidence names the variable, never the value.
        XCTAssertFalse(f!.evidence.contains("Ab3dEfGh"))
        XCTAssertTrue(f!.evidence.contains("SERVICE_API_KEY"))
    }

    func testPlaceholderEnvValueIsNot() throws {
        try write(".claude.json", #"{"mcpServers":{"api":{"command":"/x","env":{"API_KEY":"YOUR-KEY-HERE-PLEASE"}}}}"#)
        XCTAssertFalse(rules().contains("mcp-credential-in-config"))
    }

    func testEnvPassthroughIsNot() throws {
        try write(".claude.json", #"{"mcpServers":{"api":{"command":"/x","env":{"API_KEY":"${OPENAI_API_KEY}"}}}}"#)
        XCTAssertFalse(rules().contains("mcp-credential-in-config"))
    }

    func testBareShellGrantIsFlaggedAndScopedGrantIsNot() throws {
        try write(".claude/settings.local.json", #"{"permissions":{"allow":["Bash(git status)","WebSearch"]}}"#)
        XCTAssertFalse(rules().contains("broad-shell-permission"))
        try write(".claude/settings.local.json", #"{"permissions":{"allow":["Bash(*)"]}}"#)
        XCTAssertTrue(rules().contains("broad-shell-permission"))
    }

    func testCodexNeverAskIsFlagged() throws {
        try write(".codex/config.toml", "model = \"gpt-x\"\napproval_policy = \"never\"\n")
        XCTAssertTrue(rules().contains("agent-approval-never"))
        try write(".codex/config.toml", "approval_policy = \"on-request\"\n")
        XCTAssertFalse(rules().contains("agent-approval-never"))
    }

    func testWritableHookScriptIsCritical() throws {
        try write("hook.sh", "#!/bin/sh\necho ok\n")
        let script = home.appendingPathComponent("hook.sh").path
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: script)
        try write(".claude/settings.json",
                  "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"sh \(script)\"}]}]}}")
        let f = auditAgents(home: home.path).first { $0.rule == "hook-script-writable" }
        XCTAssertEqual(f?.severity, .critical)
    }

    func testPrivateHookScriptIsNot() throws {
        try write("hook.sh", "#!/bin/sh\necho ok\n")
        let script = home.appendingPathComponent("hook.sh").path
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
        try write(".claude/settings.json",
                  "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"sh \(script)\"}]}]}}")
        XCTAssertFalse(rules().contains("hook-script-writable"))
    }

    /// ⚠️ Blast radius only fires when an unfenced grant exists — an agent being
    /// able to read what the account reads is how computers work, not a finding.
    func testBlastRadiusNeedsAnUnfencedGrant() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".ssh"),
                                                withIntermediateDirectories: true)
        XCTAssertFalse(rules().contains("unfenced-agent-reach"))
        try write(".claude/settings.local.json", #"{"permissions":{"allow":["Bash(*)"]}}"#)
        XCTAssertTrue(rules().contains("unfenced-agent-reach"))
    }
}

final class NewDetectionTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("protect-det-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ name: String, _ contents: String) throws {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func rules() -> [String] { scanCode(at: dir.path).findings.map(\.rule) }

    /// ⚠️ The password segment decides, not the URL shape — every ORM README
    /// carries postgres://user:password@localhost and must stay quiet.
    func testTutorialConnectionStringIsNotALeak() {
        XCTAssertFalse(hasConnectionStringLeak("db = 'postgres://user:password@localhost/app'"))
        XCTAssertFalse(hasConnectionStringLeak("postgres://app:${DB_PASSWORD}@db:5432/app"))
        XCTAssertFalse(hasConnectionStringLeak("mysql://root:changeme@127.0.0.1"))
    }

    func testARealConnectionStringIs() {
        XCTAssertTrue(hasConnectionStringLeak("DATABASE_URL=postgres://app:vX9$kQ2mZlp0@db.internal:5432/prod"))
        XCTAssertTrue(hasConnectionStringLeak("mongodb+srv://svc:9fKq2mZx7RtY@cluster0.example.net"))
    }

    func testComposePasswordsAreFoundAndPlaceholdersAreNot() throws {
        try write("docker-compose.yml", "services:\n  db:\n    environment:\n      MYSQL_ROOT_PASSWORD: example\n")
        XCTAssertFalse(rules().contains("compose-inline-password"))
        try write("docker-compose.yml", "services:\n  db:\n    environment:\n      MYSQL_ROOT_PASSWORD: vX9kQ2mZlp0w\n")
        XCTAssertTrue(rules().contains("compose-inline-password"))
    }

    func testComposeVariableReferencesAreQuiet() throws {
        try write("docker-compose.yml", "services:\n  db:\n    environment:\n      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}\n")
        XCTAssertFalse(rules().contains("compose-inline-password"))
    }

    func testTerraformStateIsASecretsFile() throws {
        try write("infra/terraform.tfstate", "{\"resources\":[]}")
        XCTAssertTrue(rules().contains("private-key-in-tree"))
    }

    func testGitUrlDependencyIsFlagged() throws {
        try write("package.json", #"{"dependencies":{"left-pad":"github:someone/left-pad"}}"#)
        XCTAssertTrue(rules().contains("git-url-dependency"))
        try write("package.json", #"{"dependencies":{"left-pad":"^1.3.0"}}"#)
        XCTAssertFalse(rules().contains("git-url-dependency"))
    }

    func testCurlPipeShellIsFlagged() throws {
        try write("install.sh", "curl -fsSL https://example.com/install.sh | sudo bash\n")
        XCTAssertTrue(rules().contains("curl-pipe-shell"))
        try write("install.sh", "curl -fsSL https://example.com/install.sh -o i.sh\n")
        XCTAssertFalse(rules().contains("curl-pipe-shell"))
    }

    func testDigitalOceanShape() {
        let key = "dop_v1_" + String(repeating: "9f", count: 32)
        XCTAssertTrue(findCodeKeys(in: "token = '\(key)'").contains("DigitalOcean"))
    }
}

final class HistoryScanTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("protect-hist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try git("init", "-q")
        try git("config", "user.email", "t@example.com")
        try git("config", "user.name", "t")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult func git(_ args: String...) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// ⚠️ The leak a scan of today's files cannot see: committed, then deleted.
    func testADeletedSecretsFileIsStillFound() throws {
        try "OPENAI_API_KEY=sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345\n"
            .write(to: dir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try git("add", "-f", ".env"); try git("commit", "-qm", "oops")
        try git("rm", "-q", ".env"); try git("commit", "-qm", "remove it")
        let found = scanGitHistory(at: dir.path)
        XCTAssertTrue(found.map(\.rule).contains("secrets-in-history"))
        XCTAssertTrue(found.map(\.rule).contains("keys-in-history"))
        // And nothing in the report carries the key itself.
        for f in found { XCTAssertFalse(f.evidence.contains("Ab3dEfGh")) }
    }

    func testACleanHistoryIsQuiet() throws {
        try "readme\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git("add", "."); try git("commit", "-qm", "start")
        XCTAssertTrue(scanGitHistory(at: dir.path).isEmpty)
    }
}

final class HistoryTests: XCTestCase {
    var store: HistoryStore!
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("protect-hist-store-\(UUID().uuidString)")
        store = HistoryStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func finding(_ rule: String, _ where_: String) -> Finding {
        Finding(rule: rule, layer: "machine", severity: .high, title: rule,
                where_: where_, evidence: "e", remedy: "r", validation: "v",
                plain: "p", verified: true, fix: nil, guidance: nil)
    }

    func testFirstScanHasNoDelta() {
        let r = ScanResult(findings: [finding("a", "x")], toolsFound: ["t"], filesRead: 1)
        XCTAssertNil(store.record(kind: "machine", result: r))
    }

    func testDeltaSeesNewAndFixed() {
        let first = ScanResult(findings: [finding("a", "x"), finding("b", "y")],
                               toolsFound: ["t"], filesRead: 1)
        store.record(kind: "machine", result: first)
        let second = ScanResult(findings: [finding("a", "x"), finding("c", "z")],
                                toolsFound: ["t"], filesRead: 1)
        let delta = store.record(kind: "machine", result: second)
        XCTAssertEqual(delta?.new.map(\.rule), ["c"])
        XCTAssertEqual(delta?.fixed.map(\.rule), ["b"])
    }

    /// ⚠️ Compare first, save second — the reverse diffs a scan against itself.
    func testARepeatScanIsQuietNotEmpty() {
        let r = ScanResult(findings: [finding("a", "x")], toolsFound: ["t"], filesRead: 1)
        store.record(kind: "machine", result: r)
        let delta = store.record(kind: "machine", result: r)
        XCTAssertNotNil(delta)
        XCTAssertTrue(delta!.isQuiet)
    }

    func testRecordsAreClosedToOtherAccounts() throws {
        let r = ScanResult(findings: [], toolsFound: [], filesRead: 0)
        store.record(kind: "machine", result: r)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        for f in files {
            let mode = (try FileManager.default.attributesOfItem(atPath: f.path)[.posixPermissions] as? NSNumber)?.uint16Value
            XCTAssertEqual(mode, 0o600)
        }
    }
}

final class WatcherTests: XCTestCase {
    /// A UserDefaults nobody else shares, so a test cannot inherit or leave
    /// state in the real preferences.
    func freshDefaults() -> UserDefaults {
        let suite = "protect.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        addTeardownBlock { d.removePersistentDomain(forName: suite) }
        return d
    }

    func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("protect-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    let key = #"{"text":"key sk-proj-Ab3dEfGh1jKlMn0pQrStUvWxYz012345"}"#

    /// The resident claim in one test: a key written to a transcript is
    /// noticed without anyone pressing anything.
    func testAKeyWrittenToATranscriptIsNoticed() throws {
        let dir = try tempDir()
        let noticed = expectation(description: "key noticed")
        var got: [String] = []
        let watcher = TranscriptWatcher(roots: [dir.path], defaults: freshDefaults(), coalesce: 0.3) { hits in
            got = hits.flatMap(\.vendors)
            noticed.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)
        try key.write(to: dir.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        wait(for: [noticed], timeout: 10)
        XCTAssertEqual(got, ["OpenAI"])
    }

    func testAKeylessWriteIsIgnored() throws {
        let dir = try tempDir()
        let fired = expectation(description: "no callback")
        fired.isInverted = true
        let watcher = TranscriptWatcher(roots: [dir.path], defaults: freshDefaults(), coalesce: 0.3) { _ in fired.fulfill() }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)
        try "just words\n".write(to: dir.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        wait(for: [fired], timeout: 4)
    }

    /**
     ⚠️ THE STORM TEST. The same key in the same file must be announced once and
     then never again — including after a restart, which is why the memory is in
     UserDefaults and why this test hands a second watcher the same store.
     */
    func testTheSameKeyIsNotAnnouncedTwice() throws {
        let dir = try tempDir()
        let defaults = freshDefaults()
        let file = dir.appendingPathComponent("session.jsonl")

        let first = expectation(description: "announced once")
        let w1 = TranscriptWatcher(roots: [dir.path], defaults: defaults, coalesce: 0.3) { _ in first.fulfill() }
        w1.start()
        Thread.sleep(forTimeInterval: 0.5)
        try key.write(to: file, atomically: true, encoding: .utf8)
        wait(for: [first], timeout: 10)
        w1.stop()

        // A second watcher over the same store is a relaunch of the app.
        let again = expectation(description: "must not announce again")
        again.isInverted = true
        let w2 = TranscriptWatcher(roots: [dir.path], defaults: defaults, coalesce: 0.3) { _ in again.fulfill() }
        w2.start()
        defer { w2.stop() }
        Thread.sleep(forTimeInterval: 0.5)
        // The session is appended to, as a live transcript constantly is.
        try (key + "\n{\"text\":\"more conversation\"}\n")
            .write(to: file, atomically: true, encoding: .utf8)
        wait(for: [again], timeout: 5)
    }

    /// But a genuinely new key still speaks up.
    func testANewKeyInTheSameFileIsAnnounced() throws {
        let dir = try tempDir()
        let defaults = freshDefaults()
        let file = dir.appendingPathComponent("session.jsonl")

        let first = expectation(description: "first")
        let w1 = TranscriptWatcher(roots: [dir.path], defaults: defaults, coalesce: 0.3) { _ in first.fulfill() }
        w1.start()
        Thread.sleep(forTimeInterval: 0.5)
        try key.write(to: file, atomically: true, encoding: .utf8)
        wait(for: [first], timeout: 10)
        w1.stop()

        let second = expectation(description: "a different vendor is new news")
        var got: [String] = []
        let w2 = TranscriptWatcher(roots: [dir.path], defaults: defaults, coalesce: 0.3) { hits in
            got = Array(Set(hits.flatMap(\.vendors))).sorted()
            second.fulfill()
        }
        w2.start()
        defer { w2.stop() }
        Thread.sleep(forTimeInterval: 0.5)
        try (key + "\n{\"t\":\"ghp_AbCdEfGh1jKlMn0pQrStUvWxYz01234567\"}\n")
            .write(to: file, atomically: true, encoding: .utf8)
        wait(for: [second], timeout: 10)
        XCTAssertEqual(got, ["GitHub", "OpenAI"])
    }

    /// A burst of files is one announcement, not one each.
    func testABurstIsOneBatch() throws {
        let dir = try tempDir()
        let batched = expectation(description: "one callback with three files")
        var count = 0
        let watcher = TranscriptWatcher(roots: [dir.path], defaults: freshDefaults(), coalesce: 1.0) { hits in
            count = hits.count
            batched.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)
        for i in 0..<3 {
            try key.write(to: dir.appendingPathComponent("s\(i).jsonl"), atomically: true, encoding: .utf8)
        }
        wait(for: [batched], timeout: 10)
        XCTAssertEqual(count, 3)
    }

    func testFingerprintChangesOnlyWhenTheKeysDo() {
        XCTAssertEqual(TranscriptWatcher.fingerprint(["OpenAI"]),
                       TranscriptWatcher.fingerprint(["OpenAI"]))
        XCTAssertNotEqual(TranscriptWatcher.fingerprint(["OpenAI"]),
                          TranscriptWatcher.fingerprint(["OpenAI", "GitHub"]))
        XCTAssertNotEqual(TranscriptWatcher.fingerprint(["OpenAI"]),
                          TranscriptWatcher.fingerprint(["OpenAI", "OpenAI"]))
    }

    /// ⚠️ The bookkeeping must not become a list of where secrets live.
    func testTheStoredKeyIsAHashNotAPath() {
        let tag = TranscriptWatcher.tag("/Users/someone/.claude/private.jsonl")
        XCTAssertFalse(tag.contains("someone"))
        XCTAssertFalse(tag.contains("claude"))
        XCTAssertEqual(tag.count, 16)
    }
}

final class AgentNamingTests: XCTestCase {
    /// ⚠️ "1a183aae-…-c49ed7c7c117.jsonl" is not a place a person can act on.
    func testTheAssistantIsNamedRatherThanTheUUID() {
        let home = "/Users/x"
        XCTAssertEqual(
            TranscriptWatcher.agent(forPath: "/Users/x/.claude/projects/a/1a183aae-5627.jsonl", home: home),
            "Claude Code")
        XCTAssertEqual(
            TranscriptWatcher.agent(forPath: "/Users/x/.codex/sessions/2026/s.jsonl", home: home),
            "Codex")
        XCTAssertNil(TranscriptWatcher.agent(forPath: "/Users/x/Documents/notes.md", home: home))
    }
}
