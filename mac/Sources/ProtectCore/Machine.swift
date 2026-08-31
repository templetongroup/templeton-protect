import Foundation

// Scan your hardware.
//
// What this Mac is, and everything about how it is configured that makes leaving
// an AI agent running on it more dangerous than it needs to be.
//
// ⚠️ READ-ONLY, AND WITHOUT ROOT. Every check here is a query a normal account
// can answer. Nothing prompts for a password, because a scanner that opens an
// admin prompt on launch is a scanner nobody runs twice — and because the fix
// for these is a System Settings pane, not something this app should be typing
// into `sudo` on somebody's behalf.
//
// ⚠️ NOTHING HERE SHELLS OUT TO osascript. It blocks on an accessibility prompt
// and hangs the process — that cost a session once already, see NOTES.md.

// ── running a command without hanging ──────────────────────────────────

/// Run a command and return its output, or nil.
///
/// ⚠️ READ THE PIPE BEFORE WAITING ON THE PROCESS. A pipe holds about 64 KB; a
/// command that writes more than that blocks writing while the parent blocks
/// waiting, and neither ever moves again. `netstat -an` on a working machine is
/// comfortably past that, so the naive order deadlocks the scan on exactly the
/// machines this app is for.
///
/// ⚠️ AND A DEADLINE ON TOP. Everything here is a system binary that answers in
/// milliseconds, but a scanner is not allowed to hang on a Mac in a state its
/// author did not imagine. A check that times out reports nothing rather than
/// stopping the scan.
func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 6) -> String? {
    guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = args
    let out = Pipe()
    task.standardOutput = out
    task.standardError = Pipe()
    // No stdin. A command that decides to prompt gets EOF instead of the user.
    task.standardInput = FileHandle.nullDevice
    do { try task.run() } catch { return nil }

    let deadline = DispatchWorkItem { if task.isRunning { task.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
    let data = out.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    deadline.cancel()
    return String(data: data, encoding: .utf8)
}

/// Is this launchd job loaded? The honest way to ask whether Remote Login or
/// Screen Sharing is actually on without being root.
///
/// ⚠️ NOT `launchctl print-disabled`. That reports the *override* — whether
/// somebody has explicitly switched the job off — so a service that has never
/// been touched reads back "enabled" whether it is running or not. Every early
/// version of this said SSH was on for every Mac it ran on.
func launchdJobLoaded(_ label: String) -> Bool {
    guard let path = ["/bin/launchctl", "/usr/bin/launchctl"].first(where: {
        FileManager.default.isExecutableFile(atPath: $0)
    }) else { return false }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = ["print", "system/" + label]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    task.standardInput = FileHandle.nullDevice
    do { try task.run() } catch { return false }
    let deadline = DispatchWorkItem { if task.isRunning { task.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: deadline)
    task.waitUntilExit()
    deadline.cancel()
    return task.terminationStatus == 0
}

// ── what this Mac is ───────────────────────────────────────────────────

/// The specification, in the words on the box.
public struct MachineSpec: Sendable {
    public let model: String
    public let chip: String
    public let cores: String
    public let memory: String
    public let system: String
    /// "96 GB free of 926 GB" — the full sentence, for the report.
    public let storage: String
    /// "96 GB free" — the short one, for a card that has to fit on one line.
    public let free: String
    /// One line for the idle card, before anything has been scanned.
    public var headline: String { "\(model) · \(chip) · macOS \(systemShort)" }
    public var systemShort: String { system.split(separator: " ").first.map(String.init) ?? system }
}

/// ⚠️ AN ALLOWLIST, NOT A DENYLIST. `system_profiler SPHardwareDataType` prints
/// the serial number, the hardware UUID and the provisioning UDID next to the
/// things we want. This app shows its screen to a room and writes PDFs people
/// email; a parser that takes every line and strips the bad ones leaks the day
/// somebody adds a field. This one only ever copies out the four keys named here.
private let wantedHardwareKeys = ["Model Name", "Chip", "Total Number of Cores", "Memory"]

public func describeMachine() -> MachineSpec {
    var found: [String: String] = [:]
    if let text = run("/usr/sbin/system_profiler", ["SPHardwareDataType"], timeout: 8) {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, wantedHardwareKeys.contains(parts[0]) else { continue }
            found[parts[0]] = parts[1]
        }
    }

    // Fallbacks, so the card still says something true if system_profiler is
    // slow, missing or changes its wording.
    let model = found["Model Name"] ?? sysctlString("hw.model") ?? "This Mac"
    let chip = found["Chip"] ?? sysctlString("machdep.cpu.brand_string") ?? "Unknown processor"
    let cores = found["Total Number of Cores"] ?? "\(ProcessInfo.processInfo.processorCount)"
    let memory = found["Memory"] ?? {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return "\(bytes / 1_073_741_824) GB"
    }()

    let v = ProcessInfo.processInfo.operatingSystemVersion
    var system = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    if let build = sysctlString("kern.osversion") { system += " (\(build))" }

    var storage = "Unknown"
    var free = "Unknown"
    if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
       let bytesFree = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue,
       let total = (attrs[.systemSize] as? NSNumber)?.doubleValue {
        let gb = 1_073_741_824.0
        free = "\(Int(bytesFree / gb)) GB free"
        storage = "\(free) of \(Int(total / gb)) GB"
    }

    return MachineSpec(model: model, chip: chip, cores: cores,
                       memory: memory, system: system, storage: storage, free: free)
}

private func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
}

// ── the checks ─────────────────────────────────────────────────────────

/// The groups, in the order they run. These are the stage tiles on the scanning
/// screen, so they are named for what a person would call them.
public let machineStages = ["Disk and system", "Sharing", "Open ports",
                            "Accounts", "Updates", "Unattended work"]

public func scanMachine() -> ScanResult {
    scanMachine(isCancelled: { false }, progress: { _ in })
}

public func scanMachine(isCancelled: () -> Bool,
                        progress: (ScanProgress) -> Void) -> ScanResult {
    var findings: [Finding] = []
    var checksRun = 0
    var stage = ""
    var stageStart = 0

    func begin(_ name: String) {
        if !stage.isEmpty {
            progress(ScanProgress(tool: stage, path: "", filesRead: checksRun,
                                  findingsSoFar: findings.count,
                                  finishedTool: stage,
                                  finishedFindings: findings.count - stageStart))
        }
        stage = name
        stageStart = findings.count
    }
    func check(_ name: String) {
        checksRun += 1
        progress(ScanProgress(tool: stage, path: name, filesRead: checksRun,
                              findingsSoFar: findings.count,
                              finishedTool: nil, finishedFindings: nil))
    }

    // ── Disk and system ────────────────────────────────────────────────
    begin("Disk and system")

    check("FileVault")
    let fileVault = run("/usr/bin/fdesetup", ["status"]) ?? ""
    if fileVault.contains("FileVault is Off") {
        findings.append(Finding(
            rule: "filevault-off", layer: "machine", severity: .critical,
            title: "The disk is not encrypted",
            where_: "FileVault",
            evidence: "fdesetup status → FileVault is Off",
            remedy: "Turn on FileVault in System Settings → Privacy & Security.",
            validation: "fdesetup status reports \"FileVault is On\".",
            plain: "Everything on this Mac is stored in plain form. Anyone who takes the machine — or takes the drive out of it — can read your files, your AI conversation logs and any keys inside them without knowing your password. Encrypting the disk is the single change that makes a lost laptop a lost laptop rather than a breach.",
            verified: true,
            fix: FixAction(label: "Open FileVault settings",
                           describes: "Opens the Privacy & Security pane. Turning FileVault on needs your password and takes a while in the background; nothing is switched on for you.",
                           kind: .openSettings, target: SettingsPane.fileVault,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    check("System Integrity Protection")
    let sip = run("/usr/bin/csrutil", ["status"]) ?? ""
    if sip.lowercased().contains("disabled") {
        findings.append(Finding(
            rule: "sip-disabled", layer: "machine", severity: .critical,
            title: "System Integrity Protection is switched off",
            where_: "System Integrity Protection",
            evidence: "csrutil status → \(sip.trimmingCharacters(in: .whitespacesAndNewlines))",
            remedy: "Restart into Recovery, open Terminal and run csrutil enable, then restart.",
            validation: "csrutil status reports enabled.",
            plain: "macOS normally protects its own files from being modified, even by you. That protection is off on this Mac. It is switched off deliberately, usually to make some tool work, and it is easy to forget — but with it off, any program you run, including anything an AI agent runs on your behalf, can change the operating system itself.",
            verified: true,
            // ⚠️ NO BUTTON, ON PURPOSE. Re-enabling SIP only works from Recovery,
            // which means a restart. A button that cannot do the thing it names
            // is worse than the sentence that tells you what to do.
            fix: nil, guidance: nil))
    }

    check("Gatekeeper")
    let gatekeeper = run("/usr/sbin/spctl", ["--status"]) ?? ""
    if gatekeeper.contains("assessments disabled") {
        findings.append(Finding(
            rule: "gatekeeper-off", layer: "machine", severity: .high,
            title: "Downloaded apps are not checked before they run",
            where_: "Gatekeeper",
            evidence: "spctl --status → assessments disabled",
            remedy: "Run sudo spctl --master-enable, or set Privacy & Security → Allow apps from → App Store and identified developers.",
            validation: "spctl --status reports assessments enabled.",
            plain: "macOS normally refuses to open a downloaded app unless Apple recognizes who signed it. That check is off, so anything that arrives on this Mac will run without a word — including something an agent downloaded because a web page told it to.",
            verified: true,
            fix: FixAction(label: "Open security settings",
                           describes: "Opens Privacy & Security. Nothing is changed for you.",
                           kind: .openSettings, target: SettingsPane.security,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    // ── Sharing ────────────────────────────────────────────────────────
    begin("Sharing")

    let sharing: [(String, String, String, Severity, String)] = [
        ("com.openssh.sshd", "Remote Login", "remote-login-on", .high,
         "Anyone who can reach this Mac over the network and has an account on it can open a shell here. That is a full command line on the machine your AI assistants are logged into, with all of their keys."),
        ("com.apple.screensharing", "Screen Sharing", "screen-sharing-on", .high,
         "Someone on the network can watch this screen and use the mouse and keyboard. If an agent is running unattended, they are sharing it."),
        ("com.apple.smbd", "File Sharing", "file-sharing-on", .medium,
         "Folders on this Mac are being offered to other computers on the network. Which folders depends on what was shared, and it is rarely reviewed after the day it was switched on."),
        ("com.apple.RemoteDesktop.PrivilegeProxy", "Remote Management", "remote-management-on", .high,
         "Apple Remote Desktop can control this Mac. It is a stronger permission than Screen Sharing and it is usually on because an IT department switched it on once."),
    ]
    for (label, name, rule, severity, plain) in sharing {
        if isCancelled() { return ScanResult(findings: sortedBySeverity(findings), toolsFound: ["This Mac"], filesRead: checksRun) }
        check(name)
        guard launchdJobLoaded(label) else { continue }
        findings.append(Finding(
            rule: rule, layer: "machine", severity: severity,
            title: "\(name) is switched on",
            where_: "Sharing → \(name)",
            evidence: "launchctl print system/\(label) → loaded",
            remedy: "Turn \(name) off in System Settings → General → Sharing if you are not using it.",
            validation: "launchctl print system/\(label) reports no such service.",
            plain: plain + " Turn it off if you are not using it today; it is easy to switch back on.",
            verified: true,
            fix: FixAction(label: "Open Sharing settings",
                           describes: "Opens the Sharing pane so you can switch \(name) off. Nothing is changed for you.",
                           kind: .openSettings, target: SettingsPane.sharing,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    check("Firewall")
    let firewallState = run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]) ?? ""
    let firewallOff = firewallState.contains("State = 0") || firewallState.lowercased().contains("disabled")
    if firewallOff {
        findings.append(Finding(
            rule: "firewall-off", layer: "machine", severity: .high,
            title: "The firewall is off",
            where_: "Network → Firewall",
            evidence: "socketfilterfw --getglobalstate → \(firewallState.trimmingCharacters(in: .whitespacesAndNewlines))",
            remedy: "Turn the firewall on in System Settings → Network → Firewall.",
            validation: "socketfilterfw --getglobalstate reports State = 1.",
            plain: "Nothing is standing between this Mac and the rest of whatever network it joins. Every program listening for connections — and the list below is longer than most people expect — is reachable from the coffee shop Wi-Fi as well as from your desk.",
            verified: true,
            fix: FixAction(label: "Open firewall settings",
                           describes: "Opens the Network pane. Turning the firewall on almost never breaks anything, but it is your switch to flip.",
                           kind: .openSettings, target: SettingsPane.firewall,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    // ── Open ports ─────────────────────────────────────────────────────
    begin("Open ports")
    check("Listening ports")
    let exposed = listeningOnAllInterfaces()
    // ⚠️ DO NOT SAY THE SAME THING TWICE. Remote Login is port 22, Screen Sharing
    // is 5900, Remote Management is 3283 — each already has its own finding above,
    // with its own button. Listing them again under "programs listening" turns one
    // problem into two cards and makes the list look padded.
    let alreadyNamed: Set<Int> = [22, 88, 445, 3283, 5900]
    let unexplained = exposed.filter { !alreadyNamed.contains($0.port) }
    if !unexplained.isEmpty {
        // ⚠️ ONE FINDING, NOT ONE PER PORT. A working Mac listens on dozens of
        // sockets and a card each buries everything else on the screen. The
        // ports are the evidence; the finding is that they face the network.
        let list = unexplained.map(\.label).joined(separator: ", ")
        findings.append(Finding(
            rule: "ports-on-all-interfaces", layer: "machine",
            severity: firewallOff ? .high : .medium,
            title: "\(unexplained.count) \(unexplained.count == 1 ? "program is" : "programs are") listening to the whole network",
            where_: "Open ports",
            evidence: list,
            remedy: "Bind these to 127.0.0.1 instead of 0.0.0.0, or turn the firewall on so they are not reachable from outside.",
            validation: "netstat -an -p tcp | grep LISTEN shows only 127.0.0.1 and ::1 addresses.",
            plain: "These programs accept connections from any machine that can reach this one, not just from this Mac. A local development server or a local model API usually means to listen only to itself — the difference is one address in a config file, and nothing warns you when it is wrong."
                + (firewallOff ? " The firewall is off as well, so there is nothing else in the way." : ""),
            verified: true, fix: nil, guidance: nil))
    }

    // The one that is this product's actual subject.
    let aiPorts = exposed.filter { $0.aiService != nil }
    for port in aiPorts {
        findings.append(Finding(
            rule: "ai-service-exposed", layer: "machine", severity: .critical,
            title: "\(port.aiService!) is answering the whole network",
            where_: "Port \(port.port)",
            evidence: "listening on \(port.address):\(port.port)",
            remedy: "Bind it to 127.0.0.1. For Ollama that is OLLAMA_HOST=127.0.0.1:11434; most others take a --host flag.",
            validation: "netstat -an -p tcp | grep \(port.port) shows 127.0.0.1 rather than *.",
            plain: "\(port.aiService!) normally has no password at all, because it expects to be talking only to this Mac. Listening on every network address means anyone on the same Wi-Fi can send it prompts, read what it has loaded, and use your hardware. This is the one on this list worth fixing today.",
            verified: true, fix: nil,
            guidance: NextSteps(title: "Make it listen to this Mac only",
                steps: [
                    "Find what started it. If it was Ollama's app, quit and relaunch it after the next step; if it was a terminal, the setting goes wherever that command lives.",
                    "Set the address to 127.0.0.1. For Ollama: `launchctl setenv OLLAMA_HOST 127.0.0.1:11434`, then restart it. Most other servers take a `--host 127.0.0.1` flag.",
                    "Check it took: `netstat -an -p tcp | grep \(port.port)` should now show 127.0.0.1 rather than a `*`.",
                    "If you genuinely need it reachable from another machine, put it behind something that asks for a password — a reverse proxy or an SSH tunnel — because it has none of its own.",
                ])))
    }

    // ── Accounts ───────────────────────────────────────────────────────
    begin("Accounts")

    check("Guest account")
    if readDefault("/Library/Preferences/com.apple.loginwindow", "GuestEnabled") == "1" {
        findings.append(Finding(
            rule: "guest-account-on", layer: "machine", severity: .medium,
            title: "The guest account is switched on",
            where_: "Users & Groups → Guest User",
            evidence: "com.apple.loginwindow GuestEnabled = 1",
            remedy: "Turn the guest user off in System Settings → Users & Groups.",
            validation: "defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled returns 0.",
            plain: "Anyone who opens this Mac can log in without a password. A guest cannot read your files directly, but they are on the machine, and every file this scan reports as readable by other accounts is readable by them.",
            verified: true,
            fix: FixAction(label: "Open Users & Groups",
                           describes: "Opens the pane where the guest user is switched off. Nothing is changed for you.",
                           kind: .openSettings, target: SettingsPane.users,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    check("Automatic login")
    if let user = readDefault("/Library/Preferences/com.apple.loginwindow", "autoLoginUser"), !user.isEmpty {
        findings.append(Finding(
            rule: "automatic-login-on", layer: "machine", severity: .high,
            title: "This Mac logs itself in when it starts",
            where_: "Login options",
            // ⚠️ THE ACCOUNT NAME IS NOT EVIDENCE. It is the one thing on this
            // screen somebody standing behind you does not already know.
            evidence: "com.apple.loginwindow autoLoginUser is set",
            remedy: "Turn automatic login off in System Settings → Users & Groups → Login Options.",
            validation: "defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser does not exist.",
            plain: "Restarting this Mac lands on a working desktop with no password asked for. That undoes most of what encrypting the disk buys you, because the machine unlocks itself for whoever pressed the power button.",
            verified: true,
            fix: FixAction(label: "Open Users & Groups",
                           describes: "Opens the pane with Login Options. Nothing is changed for you.",
                           kind: .openSettings, target: SettingsPane.users,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    check("Password after sleep")
    let askForPassword = readDefault(nil, "askForPassword", domain: "com.apple.screensaver")
    let askDelay = Int(readDefault(nil, "askForPasswordDelay", domain: "com.apple.screensaver") ?? "") ?? 0
    if askForPassword == "0" {
        findings.append(Finding(
            rule: "no-password-on-wake", layer: "machine", severity: .high,
            title: "Waking this Mac does not ask for a password",
            where_: "Lock Screen",
            evidence: "com.apple.screensaver askForPassword = 0",
            remedy: "System Settings → Lock Screen → Require password after screen saver begins.",
            validation: "defaults -currentHost read com.apple.screensaver askForPassword returns 1.",
            plain: "The screen locks and then opens again for anybody who touches it. On a machine that runs AI agents while you are away from it, the lock screen is the only thing separating your keys from the room.",
            verified: true,
            fix: FixAction(label: "Open Lock Screen settings",
                           describes: "Opens the Lock Screen pane. Nothing is changed for you.",
                           kind: .openSettings, target: SettingsPane.lockScreen,
                           mode: nil, destructive: false),
            guidance: nil))
    } else if askDelay >= 900 {
        findings.append(Finding(
            rule: "slow-password-on-wake", layer: "machine", severity: .low,
            title: "The screen stays unlocked for \(askDelay / 60) minutes after it sleeps",
            where_: "Lock Screen",
            evidence: "com.apple.screensaver askForPasswordDelay = \(askDelay)",
            remedy: "Shorten the delay in System Settings → Lock Screen.",
            validation: "askForPasswordDelay is 300 or less.",
            plain: "The password is asked for eventually, but not for a while. Anyone who sits down at this Mac inside that window is simply on it.",
            verified: true,
            fix: FixAction(label: "Open Lock Screen settings",
                           describes: "Opens the Lock Screen pane. Nothing is changed for you.",
                           kind: .openSettings, target: SettingsPane.lockScreen,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    // ── Updates ────────────────────────────────────────────────────────
    begin("Updates")
    check("Automatic updates")
    let updates = "/Library/Preferences/com.apple.SoftwareUpdate"
    var updatesOff: [String] = []
    if readDefault(updates, "AutomaticCheckEnabled") == "0" { updatesOff.append("checking for updates") }
    if readDefault(updates, "ConfigDataInstall") == "0" { updatesOff.append("security data files") }
    if readDefault(updates, "CriticalUpdateInstall") == "0" { updatesOff.append("critical security fixes") }
    if !updatesOff.isEmpty {
        findings.append(Finding(
            rule: "automatic-updates-off", layer: "machine", severity: .medium,
            title: "Automatic security updates are off",
            where_: "Software Update",
            evidence: "switched off: " + updatesOff.joined(separator: ", "),
            remedy: "System Settings → General → Software Update → the ⓘ beside Automatic Updates.",
            validation: "ConfigDataInstall and CriticalUpdateInstall both read 1.",
            plain: "Apple ships small security fixes separately from the big macOS updates, and those are the ones that close a hole the week it becomes public. This Mac is not taking them on its own, so it gets them whenever somebody remembers.",
            verified: true,
            fix: FixAction(label: "Open Software Update",
                           describes: "Opens the Software Update pane. Nothing is installed for you.",
                           kind: .openSettings, target: SettingsPane.softwareUpdate,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    // ── Unattended work ────────────────────────────────────────────────
    //
    // The part of this scan that exists because of what this app is for. An
    // agent that runs for an hour needs the Mac awake for an hour, so people
    // switch sleep off and never switch it back — and an awake Mac that never
    // locks is a different machine from the one they think they have.
    begin("Unattended work")

    check("Sleep")
    let power = run("/usr/bin/pmset", ["-g"]) ?? ""
    let sleepLine = power.split(separator: "\n").first { $0.contains(" sleep ") && !$0.contains("displaysleep") && !$0.contains("disksleep") }
    let sleepMinutes = sleepLine.flatMap { line -> Int? in
        let parts = line.split(separator: " ").filter { !$0.isEmpty }
        guard let i = parts.firstIndex(of: "sleep"), i + 1 < parts.count else { return nil }
        return Int(parts[i + 1])
    }
    let preventedBy = sleepLine.flatMap { line -> String? in
        guard let r = line.range(of: "sleep prevented by ") else { return nil }
        return String(line[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ") "))
    }
    if sleepMinutes == 0 {
        findings.append(Finding(
            rule: "never-sleeps", layer: "machine", severity: .medium,
            title: "This Mac is set never to sleep",
            where_: "Power settings",
            evidence: "pmset -g → sleep 0" + (preventedBy.map { ", currently held awake by \($0)" } ?? ""),
            remedy: "Set a sleep timer in System Settings → Battery, or let the app that needs the Mac awake ask for it with caffeinate rather than changing the machine's setting.",
            validation: "pmset -g reports a non-zero sleep value.",
            plain: "The Mac stays on and logged in indefinitely. That is usually set once so a long job can finish, and then it is simply how the machine behaves — awake on a desk, in a hotel, in an office after hours, with every AI assistant on it signed in."
                + (preventedBy.map { " Right now these are keeping it awake: \($0)." } ?? ""),
            verified: true,
            fix: FixAction(label: "Open Battery settings",
                           describes: "Opens the pane with the sleep timers. Nothing is changed for you.",
                           kind: .openSettings, target: SettingsPane.battery,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    check("Screen lock")
    let displaySleep = power.split(separator: "\n").first { $0.contains("displaysleep") }.flatMap { line -> Int? in
        let parts = line.split(separator: " ").filter { !$0.isEmpty }
        guard let i = parts.firstIndex(of: "displaysleep"), i + 1 < parts.count else { return nil }
        return Int(parts[i + 1])
    }
    if displaySleep == 0 {
        findings.append(Finding(
            rule: "screen-never-sleeps", layer: "machine", severity: .medium,
            title: "The screen is set never to turn off",
            where_: "Power settings",
            evidence: "pmset -g → displaysleep 0",
            remedy: "Set a display sleep timer in System Settings → Battery, or lock the screen by hand with Control-Command-Q.",
            validation: "pmset -g reports a non-zero displaysleep value.",
            plain: "The screen never blanks, so the lock that follows it never happens either. Whatever an agent is doing stays on display, and the Mac stays unlocked, for as long as nobody touches it.",
            verified: true,
            fix: FixAction(label: "Open Battery settings",
                           describes: "Opens the pane with the display timers. Nothing is changed for you.",
                           kind: .openSettings, target: SettingsPane.battery,
                           mode: nil, destructive: false),
            guidance: nil))
    }

    // Close the last stage.
    begin("")
    return ScanResult(findings: sortedBySeverity(findings),
                      toolsFound: ["This Mac"], filesRead: checksRun)
}

// ── open ports ─────────────────────────────────────────────────────────

public struct OpenPort: Sendable {
    public let address: String
    public let port: Int
    /// The program holding the socket, when this account can see it.
    public let process: String?
    /// Set when this is a local model server, which is the case this app is for.
    public let aiService: String?
    var label: String {
        (process.map { "\($0) on " } ?? "") + "\(address):\(port)"
            + (aiService.map { _ in "" } ?? "")
    }
}

/// ⚠️ THE PROCESS NAME IS THE DIFFERENCE BETWEEN A FACT AND A FINDING, and the
/// first version had only the port number. Port 5000 was reported as "a local
/// model server" on this Mac; it is AirPlay Receiver, which macOS itself turns
/// on. Port 3000 and port 8080 are whatever somebody started this morning.
/// Guessing a service from a number invents findings, which is the one thing
/// docs/PRODUCT.md says this product may never do.
///
/// So the port list is only ever used to *confirm* a process name, never to
/// stand in for one, and it holds nothing generic.
private let aiServicePorts: [Int: String] = [
    11434: "Ollama",
    1234: "LM Studio",
    7860: "a Gradio or Stable Diffusion interface",
    8188: "ComfyUI",
]

/// Process names that are a local model server whatever port they picked.
private let aiProcessNames = ["ollama", "lm-studio", "lmstudio", "llama-server",
                              "llama.cpp", "llamafile", "comfyui", "vllm",
                              "localai", "text-generation", "jan", "koboldcpp"]

private func aiService(process: String?, port: Int) -> String? {
    if let p = process?.lowercased(), let hit = aiProcessNames.first(where: { p.contains($0) }) {
        return aiServicePorts[port] ?? hit
    }
    // A port from the list only counts when nothing contradicts it: either the
    // process is unknown to this account, or its name is consistent.
    guard let named = aiServicePorts[port] else { return nil }
    if let p = process?.lowercased(), !aiProcessNames.contains(where: { p.contains($0) }),
       !p.contains("python") && !p.contains("node") { return nil }
    return named
}

/// Ports accepting connections from outside this Mac.
///
/// ⚠️ LOOPBACK IS NOT EXPOSURE. `127.0.0.1` and `::1` cannot be reached from
/// another machine, and the overwhelming majority of what a developer's Mac is
/// listening on is loopback. Reporting those would bury the handful that matter
/// under thirty that do not.
///
/// ⚠️ BOTH COMMANDS, BECAUSE NEITHER ALONE IS ENOUGH. `lsof` names the program
/// but without root it only sees this account's processes; `netstat` sees every
/// listener but names none of them. netstat decides the list, lsof labels it.
public func listeningOnAllInterfaces() -> [OpenPort] {
    var names: [Int: String] = [:]
    if let text = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"], timeout: 12) {
        for line in text.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ").filter { !$0.isEmpty }
            guard let command = parts.first, let socket = parts.last(where: { $0.contains(":") })
            else { continue }
            guard let colon = socket.lastIndex(of: ":"),
                  let port = Int(socket[socket.index(after: colon)...]) else { continue }
            // lsof escapes spaces as \x20; "Plex\x20Media" reads badly on screen.
            names[port] = command.replacingOccurrences(of: "\\x20", with: " ")
        }
    }

    guard let text = run("/usr/sbin/netstat", ["-an", "-p", "tcp"], timeout: 10) else { return [] }
    var seen = Set<Int>()
    var out: [OpenPort] = []
    for line in text.split(separator: "\n") where line.contains("LISTEN") {
        let parts = line.split(separator: " ").filter { !$0.isEmpty }
        guard parts.count >= 4 else { continue }
        let local = String(parts[3])
        // netstat writes "*.443", "127.0.0.1.8080", "::1.5877", "fe80::1%lo0.5000".
        guard let dot = local.lastIndex(of: "."), let port = Int(local[local.index(after: dot)...])
        else { continue }
        let address = String(local[..<dot])
        guard address == "*" || address == "0.0.0.0" || address == "::" else { continue }
        guard seen.insert(port).inserted else { continue }
        let process = names[port]
        out.append(OpenPort(address: address, port: port, process: process,
                            aiService: aiService(process: process, port: port)))
    }
    return out.sorted { $0.port < $1.port }
}

// ── reading a preference ───────────────────────────────────────────────

/// ⚠️ `defaults`, NOT UserDefaults. The interesting keys live in
/// /Library/Preferences, which belongs to root and is not in this app's own
/// preference search path — UserDefaults reads back nil for every one of them
/// and the scan cheerfully reports a hardened machine.
func readDefault(_ plist: String?, _ key: String, domain: String? = nil) -> String? {
    var args: [String] = []
    // -currentHost matters for com.apple.screensaver: the screen-lock settings
    // are per-machine, and reading the plain domain misses them entirely.
    if let domain { args = ["-currentHost", "read", domain, key] }
    else if let plist { args = ["read", plist, key] }
    else { return nil }
    guard let out = run("/usr/bin/defaults", args) else { return nil }
    let value = out.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty || value.contains("does not exist") { return nil }
    return value
}

/// The System Settings panes each finding sends you to.
///
/// ⚠️ THESE URLS ARE VERSION-SPECIFIC AND THEY DO MOVE. Ventura renamed every
/// pane; a URL that no longer resolves opens nothing at all, which is the "a
/// button that does nothing" failure this project has a rule against. Each entry
/// is a list, tried in order, and `openSettings` falls back to launching System
/// Settings itself so the button always does something.
enum SettingsPane {
    static let fileVault = "com.apple.settings.PrivacySecurity.extension?FileVault|com.apple.preference.security?FileVault"
    static let security = "com.apple.settings.PrivacySecurity.extension?Security|com.apple.preference.security?General"
    static let firewall = "com.apple.Network-Settings.extension?Firewall|com.apple.preference.security?Firewall"
    static let sharing = "com.apple.Sharing-Settings.extension|com.apple.preferences.sharing"
    static let users = "com.apple.Users-Groups-Settings.extension|com.apple.preferences.users"
    static let lockScreen = "com.apple.Lock-Screen-Settings.extension|com.apple.preference.desktopscreeneffect"
    static let softwareUpdate = "com.apple.Software-Update-Settings.extension|com.apple.preferences.softwareupdate"
    static let battery = "com.apple.Battery-Settings.extension|com.apple.preference.energysaver"
}
