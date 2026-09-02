import Foundation

// What your agents are allowed to do.
//
// The installations scan finds credentials already spilled. This half asks the
// question that comes before that one: what could an agent on this Mac do right
// now, without asking? It reads the same configuration the agents read — MCP
// server lists, permission allowlists, hooks, approval policies — and reports
// the grants that make an unattended agent a bigger machine than its owner
// remembers building.
//
// ⚠️ EVERY FINDING HERE IS A FACT FROM A CONFIG FILE, never an opinion about
// one. "This server is fetched unpinned" is read out of the args; "this could
// be dangerous" on its own is not a finding, it is a mood.
//
// ⚠️ EVIDENCE NAMES KEYS, NEVER VALUES. An env block in an MCP config is
// exactly the kind of place a live credential sits, and quoting it would copy
// it onto the screen and into every export — the failure this app exists to
// catch. The evidence is the variable's NAME.

// ── reading the configs ────────────────────────────────────────────────

struct McpServer {
    let owner: String       // which app's config declared it
    let name: String
    let command: String?
    let args: [String]
    let url: String?
    let envKeys: [String]   // names only
    let envLeaks: [String]  // names whose values look like live credentials
    let configPath: String  // display form
}

private func json(at path: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// A value that looks like a live credential rather than a placeholder.
///
/// ⚠️ THE NAME ALONE IS NOT ENOUGH. Every MCP env block is full of variables
/// *named* like secrets whose values are "", "changeme" or "${VAR}" passthroughs.
/// Only a value that is actually key-shaped — or long, opaque and under a
/// secret-shaped name — counts, and the placeholder test runs either way.
func looksLikeLiveCredential(name: String, value: String) -> Bool {
    if value.isEmpty || value.hasPrefix("${") || value.hasPrefix("$") { return false }
    if isPlaceholder(value) { return false }
    if !findKeys(in: value).isEmpty || holdsPrivateKey(value) { return true }
    let secretName = ["key", "token", "secret", "password", "credential"]
        .contains { name.lowercased().contains($0) }
    return secretName && value.count >= 16 && !value.contains(" ")
}

func mcpServers(fromJSON path: String, owner: String, display: String) -> [McpServer] {
    guard let root = json(at: path),
          let servers = root["mcpServers"] as? [String: Any] else { return [] }
    return servers.compactMap { name, raw in
        guard let cfg = raw as? [String: Any] else { return nil }
        let env = cfg["env"] as? [String: Any] ?? [:]
        let leaks = env.compactMap { k, v -> String? in
            guard let s = v as? String, looksLikeLiveCredential(name: k, value: s) else { return nil }
            return k
        }
        return McpServer(owner: owner, name: name,
                         command: cfg["command"] as? String,
                         args: (cfg["args"] as? [String]) ?? [],
                         url: cfg["url"] as? String,
                         envKeys: Array(env.keys).sorted(),
                         envLeaks: leaks.sorted(),
                         configPath: display)
    }
}

/// Where MCP servers get declared, per app, relative to home.
func mcpConfigSources(home: String) -> [(path: String, owner: String)] {
    [(".claude.json", "Claude Code"),
     ("Library/Application Support/Claude/claude_desktop_config.json", "Claude Desktop"),
     (".cursor/mcp.json", "Cursor")].map {
        ((home as NSString).appendingPathComponent($0.0), $0.1)
    }
}

// ── the audit ──────────────────────────────────────────────────────────


/**
 Offensive-security agent harnesses, by the name they are launched under.

 ⚠️ THIS IS NOT A LIST OF BAD SOFTWARE. These are legitimate tools — a
 penetration tester running one on their own machine is doing their job, and
 reporting that as a vulnerability would be exactly the kind of false alarm that
 teaches somebody to stop reading the list. What makes it worth saying is the
 *combination*: a framework whose whole design is "point the assistant you are
 already signed into at a target and let the kill chain run" sitting on a machine
 where that same assistant has a standing grant to run anything. The tool did not
 create the exposure; it is a very capable thing to hand it.

 ⚠️ EVERY ENTRY MUST BE DISTINCTIVE ENOUGH THAT A MATCH IS A FACT. A generic word
 here — "agent", "exploit", "scan" — would fire on half the npm registry. Short,
 specific, and easy to extend is the correct shape; long and fuzzy is not.
 */
let offensiveHarnesses = ["t3mp3st", "pentestgpt", "hackingbuddygpt", "cai-fx", "nebula-ai"]

/// Which of them a command line mentions.
func offensiveHarness(in text: String) -> String? {
    let lowered = text.lowercased()
    return offensiveHarnesses.first { lowered.contains($0) }
}

public func auditAgents(home: String = NSHomeDirectory()) -> [Finding] {
    var findings: [Finding] = []
    let fm = FileManager.default
    func display(_ path: String) -> String { path.replacingOccurrences(of: home, with: "~") }

    // ── MCP servers ────────────────────────────────────────────────────
    var servers: [McpServer] = []
    for (path, owner) in mcpConfigSources(home: home) where fm.fileExists(atPath: path) {
        servers += mcpServers(fromJSON: path, owner: owner, display: display(path))
    }

    for s in servers {
        // A credential pasted into the server's env block.
        if !s.envLeaks.isEmpty {
            let (reachable, chain) = reachableByOthers(
                path: (home as NSString).appendingPathComponent(String(s.configPath.dropFirst(2))),
                home: home)
            findings.append(Finding(
                rule: "mcp-credential-in-config", layer: "harness",
                severity: reachable ? .critical : .high,
                title: "The \(s.name) server's config holds \(s.envLeaks.count == 1 ? "a live credential" : "live credentials")",
                where_: "\(s.configPath) → \(s.name)",
                evidence: "env value(s) under \(s.envLeaks.joined(separator: ", ")) look like live credentials"
                    + (reachable ? "; file modes \(chain) — readable by other accounts" : ""),
                remedy: "Move the value into the keychain or an environment variable the config references, then rotate it — a config file is copied, synced and backed up.",
                validation: "Re-run the scan; this server should report no credential-shaped env values.",
                plain: "MCP servers are helpers your AI assistant starts, and this one is handed \(s.envLeaks.count == 1 ? "a password-like value" : "password-like values") written directly into its configuration file. Config files get committed, synced and pasted into bug reports — none of which anyone thinks of as sharing a password.",
                verified: true, fix: nil,
                guidance: NextSteps(title: "Get the credential out of the config file",
                    steps: [
                        "Replace the written-in value with a reference to an environment variable, and put the real value where your account keeps secrets.",
                        "Rotate the credential at whatever issued it. It has been sitting in a plain file; treat it as copied.",
                        "Check the file has not been committed anywhere: run the code scan on any repository that might carry it.",
                    ])))
        }

        // Fetched from the package registry at whatever version answers today.
        let fetchTools = ["npx", "uvx", "bunx", "pnpm dlx"]
        let isFetcher = fetchTools.contains { s.command?.hasSuffix($0) == true || s.command == $0 }
        if isFetcher {
            let pkg = s.args.first { !$0.hasPrefix("-") } ?? ""
            let pinned = pkg.dropFirst().contains("@")  // scope @ doesn't count
            if !pinned && !pkg.isEmpty {
                findings.append(Finding(
                    rule: "mcp-unpinned-package", layer: "harness", severity: .medium,
                    title: "The \(s.name) server installs itself fresh, at any version",
                    where_: "\(s.configPath) → \(s.name)",
                    evidence: "\(s.command ?? "npx") \(pkg) — no version pinned",
                    remedy: "Pin the version: \(pkg)@<version>. Then updates are a decision, not a surprise.",
                    validation: "The args name an exact version.",
                    plain: "Every time your assistant starts this helper, it downloads whatever the newest version is and runs it with your files. If that package is ever hijacked — which happens to real packages — the hijacked version runs here the same day, with nothing to notice.",
                    verified: true, fix: nil,
                    guidance: NextSteps(title: "Pin it to a version you chose",
                        steps: [
                            "Edit \(s.configPath) and change \(pkg) to \(pkg)@<the current version>.",
                            "When you want the newer version, change the number — that is the whole cost.",
                        ])))
            }
        }

        // Talking over plain HTTP to something that is not this Mac.
        if let url = s.url, url.hasPrefix("http://"),
           !url.contains("localhost"), !url.contains("127.0.0.1") {
            findings.append(Finding(
                rule: "mcp-plain-http", layer: "harness", severity: .high,
                title: "The \(s.name) server talks over an unencrypted connection",
                where_: "\(s.configPath) → \(s.name)",
                evidence: "url begins http:// and is not local",
                remedy: "Use the https address, or tunnel it. Everything the agent sends — including your prompts and files — crosses the network readable.",
                validation: "The url begins https:// or points at this Mac.",
                plain: "Your assistant exchanges messages with this server over a connection anyone on the same network can read and alter. Whatever the agent sends it — prompts, file contents, results — travels in the open.",
                verified: true, fix: nil, guidance: nil))
        }

        // A filesystem server rooted at the whole home folder or wider.
        let looksFs = (s.args + [s.command ?? ""]).contains { $0.contains("filesystem") }
        if looksFs {
            let roots = s.args.filter { $0.hasPrefix("/") || $0.hasPrefix("~") }
            let broad = roots.contains { r in
                let full = r.hasPrefix("~") ? (home as NSString).appendingPathComponent(String(r.dropFirst(1))) : r
                return full == "/" || (full as NSString).standardizingPath == home
            }
            if broad {
                findings.append(Finding(
                    rule: "mcp-broad-filesystem", layer: "harness", severity: .medium,
                    title: "The \(s.name) server can read your whole home folder",
                    where_: "\(s.configPath) → \(s.name)",
                    evidence: "filesystem root: \(roots.joined(separator: ", "))",
                    remedy: "Root it at the folders you actually work in, not at ~ or /.",
                    validation: "The roots name specific project folders.",
                    plain: "This helper exists to give your assistant file access, and it has been pointed at everything you own — documents, mail archives, browser data, every project. Scoping it to your working folders costs nothing and removes most of what a prompt-injection attack could reach through it.",
                    verified: true, fix: nil, guidance: nil))
            }
        }
    }

    // ── permission allowlists ──────────────────────────────────────────
    var broadGrants: [(file: String, grant: String)] = []
    for name in [".claude/settings.json", ".claude/settings.local.json"] {
        let path = (home as NSString).appendingPathComponent(name)
        guard let root = json(at: path),
              let perms = root["permissions"] as? [String: Any],
              let allow = perms["allow"] as? [String] else { continue }
        for grant in allow {
            // ⚠️ TIGHT ON PURPOSE. "Bash(git status)" is somebody making their
            // day quieter and is none of our business. What gets flagged is the
            // shell with no fence at all, and wildcards on the commands that
            // delete, elevate or fetch-and-run.
            let bare = grant == "Bash" || grant == "Bash(*)" || grant == "Bash(*:*)"
            let dangerousWildcard = ["sudo", "rm ", "rm:", "curl", "wget", "chmod 777"]
                .contains { grant.hasPrefix("Bash(\($0)") && grant.contains("*") }
            if bare || dangerousWildcard { broadGrants.append((display(path), grant)) }
        }
        if (root["skipDangerousModePermissionPrompt"] as? Bool) == true {
            findings.append(Finding(
                rule: "dangerous-mode-unprompted", layer: "harness", severity: .high,
                title: "Claude Code can enter dangerous mode without asking you",
                where_: display(path),
                evidence: "skipDangerousModePermissionPrompt = true",
                remedy: "Remove the setting. The prompt is one keypress, and it is the only moment you find out a session is about to run unfenced.",
                validation: "The key is absent from \(name).",
                plain: "Dangerous mode lets a session run commands without asking permission for each one. This setting removes the confirmation that normally stands in front of that — so entering it becomes something that happens, rather than something you approved.",
                verified: true, fix: nil, guidance: nil))
        }
    }
    if !broadGrants.isEmpty {
        findings.append(Finding(
            rule: "broad-shell-permission", layer: "harness", severity: .high,
            title: "\(broadGrants.count == 1 ? "An agent has" : "Agents have") standing permission to run any command",
            where_: broadGrants.map(\.file).uniqued().joined(separator: ", "),
            evidence: broadGrants.map(\.grant).uniqued().joined(separator: "; "),
            remedy: "Replace the wildcard with the commands you actually approve. Permission prompts return only for what falls outside the list.",
            validation: "No bare Bash or dangerous-wildcard grant remains in the allowlist.",
            plain: "A standing grant like this means the agent never asks before running a shell command — any command, in any session, from now on. It is the difference between an assistant and an account with your name on it. Most people added it during one annoying afternoon and forgot it.",
            verified: true, fix: nil,
            guidance: NextSteps(title: "Narrow it without living in permission prompts",
                steps: [
                    "Open the settings file and delete the wildcard grant.",
                    "Work normally for a day; approve prompts with 'always allow' as they come. The list rebuilds itself out of what you actually use.",
                    "Keep sudo, rm and curl out of any wildcard — those three are how a bad instruction becomes a bad day.",
                ])))
    }

    // ── Codex approval policy ──────────────────────────────────────────
    let codexConfig = (home as NSString).appendingPathComponent(".codex/config.toml")
    if let toml = try? String(contentsOfFile: codexConfig, encoding: .utf8) {
        // ⚠️ A REGEX, NOT A TOML PARSER, and scoped to the one key it wants:
        // the top-level approval_policy line. Swallowing a full TOML parser to
        // read one key would be the heaviest dependency in the product.
        if toml.range(of: #"^\s*approval_policy\s*=\s*"never""#,
                      options: [.regularExpression, .anchored]) != nil
            || toml.range(of: #"(?m)^approval_policy\s*=\s*"never""#, options: .regularExpression) != nil {
            findings.append(Finding(
                rule: "agent-approval-never", layer: "harness", severity: .high,
                title: "Codex is set to never ask before acting",
                where_: display(codexConfig),
                evidence: "approval_policy = \"never\"",
                remedy: "Set approval_policy to \"on-request\" or \"untrusted\" so consequential commands come back to you.",
                validation: "approval_policy is not \"never\".",
                plain: "Codex runs whatever it decides to run, without showing you first. Combined with a working shell that is not a safety setting dialed low — it is the absence of one. Fine for a sandboxed machine; on the Mac that holds your keys and your email, it deserves a deliberate yes.",
                verified: true, fix: nil, guidance: nil))
        }
    }

    // ── hooks ──────────────────────────────────────────────────────────
    //
    // A hook is a shell command every session runs automatically. Anything that
    // can edit the script a hook points at is inside every future session —
    // which makes a hook script's file permissions a privilege boundary.
    if let root = json(at: (home as NSString).appendingPathComponent(".claude/settings.json")),
       let hooks = root["hooks"] as? [String: Any] {
        var writable = Set<String>()
        for (_, entries) in hooks {
            guard let list = entries as? [[String: Any]] else { continue }
            for entry in list {
                for hook in (entry["hooks"] as? [[String: Any]]) ?? [] {
                    guard let command = hook["command"] as? String else { continue }
                    for path in scriptPaths(in: command, home: home) {
                        guard let attrs = try? fm.attributesOfItem(atPath: path),
                              let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value,
                              mode & 0o022 != 0 else { continue }
                        writable.insert(display(path))
                    }
                }
            }
        }
        if !writable.isEmpty {
            findings.append(Finding(
                rule: "hook-script-writable", layer: "harness", severity: .critical,
                title: "A script your agent runs automatically is writable by other accounts",
                where_: writable.sorted().joined(separator: ", "),
                evidence: "group- or world-writable hook script(s) referenced from .claude/settings.json",
                remedy: "chmod 755 the script and its folder. A hook runs in every session; whoever can edit it is inside every session.",
                validation: "stat -f '%Lp' on each script shows no group/world write bit.",
                plain: "Hooks are commands your assistant runs by itself at set moments — every session, without asking. One of those scripts can be modified by other accounts on this Mac, which means anyone who can log in here can put their own commands into every conversation you have from then on.",
                verified: true, fix: nil,
                guidance: NextSteps(title: "Close the script, then read it once",
                    steps: [
                        "Make the script writable only by you: `chmod 755` on the file, and check the folder above it too.",
                        "Read the script top to bottom once. If it was writable, assume it may have been written to.",
                        "Keep hook scripts inside your own home folder, never in /tmp or a shared location.",
                    ])))
        }
    }

    // ── instruction files ──────────────────────────────────────────────
    //
    // CLAUDE.md and AGENTS.md are standing instructions the agent obeys.
    // Writable by others, they are a prompt-injection vector with a filename.
    var looseInstructions: [String] = []
    for candidate in [".claude/CLAUDE.md", "CLAUDE.md", "AGENTS.md"] {
        let path = (home as NSString).appendingPathComponent(candidate)
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value,
              mode & 0o022 != 0 else { continue }
        looseInstructions.append(display(path))
    }
    if !looseInstructions.isEmpty {
        findings.append(Finding(
            rule: "instructions-writable", layer: "harness", severity: .high,
            title: "Your agent's standing instructions are writable by other accounts",
            where_: looseInstructions.joined(separator: ", "),
            evidence: "group- or world-writable instruction file(s)",
            remedy: "chmod 644 the file. Instructions the agent obeys should change only when you change them.",
            validation: "stat -f '%Lp' shows no group/world write bit.",
            plain: "These files are read at the start of every session and the agent treats what they say as your standing orders. If another account can edit them, another account can give your assistant orders — and nothing about the session would look different.",
            verified: true, fix: nil, guidance: nil))
    }

    // ── an offensive harness wired to an assistant ─────────────────────
    //
    // Read out of the same configuration already parsed above: an MCP server,
    // a hook, or an allowlist entry that launches one of these by name.
    var harnessSightings: [(String, String)] = []   // (tool, where)
    for srv in servers {
        let line = ([srv.command ?? ""] + srv.args).joined(separator: " ")
        if let tool = offensiveHarness(in: line) {
            harnessSightings.append((tool, "\(srv.configPath) → \(srv.name)"))
        }
    }
    for name in [".claude/settings.json", ".claude/settings.local.json"] {
        let path = (home as NSString).appendingPathComponent(name)
        guard let root = json(at: path) else { continue }
        if let perms = root["permissions"] as? [String: Any],
           let allow = perms["allow"] as? [String] {
            for grant in allow {
                if let tool = offensiveHarness(in: grant) {
                    harnessSightings.append((tool, display(path)))
                }
            }
        }
        if let hooks = root["hooks"] as? [String: Any] {
            for (_, entries) in hooks {
                guard let list = entries as? [[String: Any]] else { continue }
                for entry in list {
                    for hook in (entry["hooks"] as? [[String: Any]]) ?? [] {
                        guard let command = hook["command"] as? String,
                              let tool = offensiveHarness(in: command) else { continue }
                        harnessSightings.append((tool, display(path)))
                    }
                }
            }
        }
    }

    // ⚠️ SEVERITY FOLLOWS THE FENCE, NOT THE TOOL. Wired to an agent that still
    // asks before it acts, this is context worth knowing and nothing more. Wired
    // to one that never asks, it is the difference between an assistant that
    // could read your files and one that arrives with an exploit chain attached.
    let unfencedGrant = !broadGrants.isEmpty
        || findings.contains { $0.rule == "agent-approval-never" }
    if !harnessSightings.isEmpty {
        let tools = Set(harnessSightings.map(\.0)).sorted()
        findings.append(Finding(
            rule: "offensive-harness-wired", layer: "harness",
            severity: unfencedGrant ? .high : .low,
            title: unfencedGrant
                ? "An offensive-security harness is wired to an agent that never asks"
                : "An offensive-security harness is wired to an assistant",
            where_: Set(harnessSightings.map(\.1)).sorted().joined(separator: ", "),
            evidence: "configuration launches: " + tools.joined(separator: ", "),
            remedy: unfencedGrant
                ? "Narrow the standing grant first — the findings above name it. Keep this harness on a machine, or an account, that is not also signed into your everyday credentials."
                : "Nothing to fix if this is your own tooling. Keep the approval prompts on while it is configured.",
            validation: "Re-run after narrowing the grants; the severity follows them down.",
            plain: unfencedGrant
                ? "This is a legitimate red-teaming tool, and on its own it is not a problem — somebody testing systems they are authorised to test needs one. What makes it worth saying here is the pairing: it is built to take the assistant you are already signed into and drive it through recon, exploitation and reporting, and on this Mac that assistant has standing permission to run commands without asking. The tool did not create that exposure, but it is a very capable thing to have handed it."
                : "A red-teaming harness is configured against your assistant. That is ordinary if it is your own tooling — it is noted because it is built to drive your assistant through an attack chain, so it belongs on the list of things that agent can reach for. Your approval prompts are still on, which is what keeps it deliberate.",
            verified: true, fix: nil,
            guidance: unfencedGrant
                ? NextSteps(title: "Put a fence between the two",
                    steps: [
                        "Narrow the standing shell grant — that is the finding that actually changes the blast radius, and it is listed above.",
                        "Run offensive tooling from an account or a machine that is not signed into your production credentials, cloud keys or password manager.",
                        "Keep approval prompts on for the assistant the harness drives. A tool designed to chain steps together is the last one to hand a blanket yes.",
                    ])
                : nil))
    }

    // ── blast radius ───────────────────────────────────────────────────
    //
    // ⚠️ ONLY WHEN AN UNFENCED GRANT EXISTS. Every agent can read what your
    // account can read; that is not a finding, it is how computers work. The
    // finding is the combination: an agent that never asks, on an account whose
    // sensitive stores are sitting where a shell can reach them.
    if unfencedGrant {
        let stores: [(String, String)] = [
            (".ssh", "SSH keys — every server they open"),
            (".aws", "AWS credentials"),
            (".config/gh", "GitHub login"),
            (".netrc", "stored passwords for command-line tools"),
            (".gnupg", "signing keys"),
        ]
        let present = stores.filter { fm.fileExists(atPath: (home as NSString).appendingPathComponent($0.0)) }
        if !present.isEmpty {
            findings.append(Finding(
                rule: "unfenced-agent-reach", layer: "harness", severity: .high,
                title: "An agent that never asks can reach \(present.count) credential store\(present.count == 1 ? "" : "s")",
                where_: present.map { "~/" + $0.0 }.joined(separator: ", "),
                evidence: "an always-allow shell grant or a never-ask policy exists, and these stores are on disk: "
                    + present.map(\.0).joined(separator: ", "),
                remedy: "Narrow the grant (the findings above), or accept that a prompt-injected session can read: "
                    + present.map(\.1).joined(separator: "; ") + ".",
                validation: "Re-run after narrowing the grants; this finding follows them out.",
                plain: "This puts the two findings above in one sentence: an assistant on this Mac can run commands without asking, and the commands it could run can read your SSH keys, cloud credentials and stored logins. A malicious web page or poisoned document that successfully instructs the agent gets the same reach. Fixing the grants above removes this finding with them.",
                verified: true, fix: nil, guidance: nil))
        }
    }

    return findings
}

/// Paths that look like scripts inside a hook command string.
func scriptPaths(in command: String, home: String) -> [String] {
    // Matches /abs/path.sh and ~/rel/path.sh tokens, quoted or bare.
    let re = try! NSRegularExpression(pattern: #"[~/][^\s'"]*\.(sh|bash|zsh|py|js|mjs|rb)"#)
    let range = NSRange(command.startIndex..., in: command)
    return re.matches(in: command, range: range).compactMap { m in
        guard let r = Range(m.range, in: command) else { return nil }
        let raw = String(command[r])
        return raw.hasPrefix("~") ? (home as NSString).appendingPathComponent(String(raw.dropFirst(1))) : raw
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
