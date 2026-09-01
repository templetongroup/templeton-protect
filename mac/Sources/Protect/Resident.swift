import AppKit
import ProtectCore
import UserNotifications

// The resident layer — Protect+.
//
// A scan you run is a snapshot; this is the part that keeps watch. A menu bar
// presence, a schedule that re-runs the scans and says what changed, and a
// watcher on the agents' transcript folders that notices a key the moment one
// is written — instead of whenever somebody next thinks to press the button.
//
// ⚠️ RESIDENT MEANS QUIET. The bar item never animates, notifications fire for
// NEW findings only, and a scheduled scan that finds nothing new reports by
// updating the menu line, not by interrupting anyone. An always-on security
// tool that keeps proving it is on gets switched off.

@MainActor
final class Resident: NSObject {
    private weak var model: Model?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var watcher: TranscriptWatcher?
    private let history = HistoryStore()

    enum Cadence: String, CaseIterable {
        case off, daily, weekly
        var seconds: TimeInterval? {
            switch self {
            case .off: return nil
            case .daily: return 24 * 3600
            case .weekly: return 7 * 24 * 3600
            }
        }
        var label: String {
            switch self {
            case .off: return "Off"
            case .daily: return "Every day"
            case .weekly: return "Every week"
            }
        }
    }

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "keepWatch") }
        set { UserDefaults.standard.set(newValue, forKey: "keepWatch"); apply() }
    }
    var cadence: Cadence {
        get { Cadence(rawValue: UserDefaults.standard.string(forKey: "scanEvery") ?? "") ?? .weekly }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "scanEvery"); apply() }
    }

    init(model: Model) {
        self.model = model
        super.init()
        apply()
    }

    // ── the switch ─────────────────────────────────────────────────────
    func apply() {
        guard enabled, Plan.current.includesResident else { teardown(); return }
        if statusItem == nil { install() }
        rebuildMenu()
        scheduleTimer()
        startWatching()
        requestNotificationLeave()
    }

    private func teardown() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
        timer?.invalidate(); timer = nil
        watcher?.stop(); watcher = nil
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let swirl = Bundle.main.image(forResource: "swirl-mark") {
            let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                swirl.draw(in: rect)
                return true
            }
            // ⚠️ A TEMPLATE, so the bar tints it for light and dark menu bars.
            icon.isTemplate = true
            item.button?.image = icon
        } else {
            item.button?.title = "TP"
        }
        statusItem = item
    }

    // ── the menu ───────────────────────────────────────────────────────
    func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()

        let title = NSMenuItem(title: history.lastRunLine() ?? "No scan recorded yet",
                               action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let scanNow = NSMenuItem(title: "Scan now", action: #selector(scanNowClicked), keyEquivalent: "")
        scanNow.target = self
        menu.addItem(scanNow)

        let schedule = NSMenuItem(title: "Scan on a schedule", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for c in Cadence.allCases {
            let entry = NSMenuItem(title: c.label, action: #selector(cadenceClicked(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = c.rawValue
            entry.state = c == cadence ? .on : .off
            sub.addItem(entry)
        }
        schedule.submenu = sub
        menu.addItem(schedule)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Templeton Protect", action: #selector(openClicked), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let quit = NSMenuItem(title: "Quit Templeton Protect", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func openClicked() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func cadenceClicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let c = Cadence(rawValue: raw) else { return }
        cadence = c
    }

    @objc private func scanNowClicked() { backgroundScan(reason: "requested from the menu bar") }

    // ── the schedule ───────────────────────────────────────────────────
    private func scheduleTimer() {
        timer?.invalidate(); timer = nil
        guard cadence.seconds != nil else { return }
        // ⚠️ AN HOURLY CHECK AGAINST A DUE DATE, NOT A LONG TIMER. A Mac that
        // sleeps through a 7-day timer never fires it; an hourly check runs the
        // scan on the first wake past due, which is what "weekly" means to a
        // laptop that closes at night.
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runIfDue() }
        }
        runIfDue()
    }

    private func runIfDue() {
        guard let interval = cadence.seconds else { return }
        let last = UserDefaults.standard.object(forKey: "lastScheduledScan") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= interval else { return }
        backgroundScan(reason: "scheduled")
    }

    /// Machine + installations (+ code, if a folder is chosen), off the main
    /// thread, recorded to history — and a notification only for what is NEW.
    private func backgroundScan(reason: String) {
        UserDefaults.standard.set(Date(), forKey: "lastScheduledScan")
        let codeFolder = UserDefaults.standard.string(forKey: "codeFolder")
        let history = self.history
        Task.detached(priority: .utility) {
            var newFindings: [Finding] = []
            var openCount = 0
            for (kind, result) in [("machine", scanMachine()),
                                   ("installations", scanAiInstallations())] {
                let delta = history.record(kind: kind, result: result)
                newFindings += delta?.new ?? []
                openCount += result.findings.count
            }
            if let folder = codeFolder, FileManager.default.fileExists(atPath: folder) {
                let result = scanCode(at: folder)
                let delta = history.record(kind: "code", result: result)
                newFindings += delta?.new ?? []
                openCount += result.findings.count
            }
            let toReport = newFindings
            let open = openCount
            await MainActor.run { [weak self] in
                self?.rebuildMenu()
                self?.model?.refreshFromHistory()
                if !toReport.isEmpty { self?.notify(new: toReport, open: open) }
            }
        }
    }

    // ── the watcher ────────────────────────────────────────────────────
    private func startWatching() {
        guard watcher == nil else { return }
        let home = NSHomeDirectory()
        let roots = aiHomes.map { (home as NSString).appendingPathComponent($0.dir) }
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard !roots.isEmpty else { return }
        watcher = TranscriptWatcher(roots: roots) { [weak self] path, vendors in
            Task { @MainActor in
                self?.notifyLiveKey(path: path, vendors: vendors)
                self?.rebuildMenu()
            }
        }
        watcher?.start()
    }

    // ── notifications ──────────────────────────────────────────────────
    private func requestNotificationLeave() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in
            // Denied is a fine answer; the menu line still reports.
        }
    }

    private func notify(new: [Finding], open: Int) {
        let content = UNMutableNotificationContent()
        let worst = new.min { $0.severity.rank < $1.severity.rank }
        content.title = new.count == 1
            ? "One new finding on this Mac"
            : "\(new.count) new findings on this Mac"
        content.body = (worst.map { redact($0.title) } ?? "")
            + (open > new.count ? " — \(open) open in total" : "")
        deliver(content, id: "scan-\(Date().timeIntervalSince1970)")
    }

    private func notifyLiveKey(path: String, vendors: [String]) {
        let content = UNMutableNotificationContent()
        let unique = Array(Set(vendors)).sorted()
        content.title = "A key was just written to a conversation log"
        // ⚠️ THE VENDOR AND THE FILE NAME, NEVER THE KEY. And the path's last
        // component only — a notification banner is the most public pixel on
        // the screen.
        content.body = "\(unique.joined(separator: " and ")) key\(vendors.count == 1 ? "" : "s") in \((path as NSString).lastPathComponent). Open Templeton Protect to remove it and rotate."
        deliver(content, id: "live-\(path.hashValue)")
    }

    private func deliver(_ content: UNMutableNotificationContent, id: String) {
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
