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
final class Resident: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private weak var model: Model?
    /// Asks the app delegate to bring its window back. A closure, so the
    /// Resident never has to know how the window is built or find it by guessing.
    private let showWindow: () -> Void
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

    init(model: Model, showWindow: @escaping () -> Void) {
        self.model = model
        self.showWindow = showWindow
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

        // ⚠️ THE MENU BAR IS WHERE A SUBSCRIBER LIVES, so it is where a lapse
        // has to be visible. Somebody who never opens the window would otherwise
        // find out that watching stopped by not being told about something.
        let ent = Licensing.entitlement()
        let state = NSMenuItem(title: ent.summary, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        if !ent.allowsResident {
            let buy = NSMenuItem(title: "Subscribe to Protect+…",
                                 action: #selector(subscribeClicked), keyEquivalent: "")
            buy.target = self
            menu.addItem(buy)
        }
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

        // Somebody living in the menu bar may go weeks without opening the
        // window; the update check has to be reachable from here too.
        let updates = NSMenuItem(title: "Check for Updates…",
                                 action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = Updater.shared
        menu.addItem(updates)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Templeton Protect", action: #selector(openClicked), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let quit = NSMenuItem(title: "Quit Templeton Protect", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func openClicked() { showWindow() }

    @objc private func subscribeClicked() {
        if let url = URL(string: Store.checkout) { NSWorkspace.shared.open(url) }
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
        watcher = TranscriptWatcher(roots: roots) { [weak self] hits in
            Task { @MainActor in
                self?.notifyLiveKeys(hits)
                self?.rebuildMenu()
            }
        }
        watcher?.start()
    }

    // ── notifications ──────────────────────────────────────────────────
    private func requestNotificationLeave() {
        // ⚠️ THE DELEGATE IS SET BEFORE THE PERMISSION IS ASKED FOR, and both
        // happen at launch. A tap is delivered to whatever is the delegate at
        // the moment macOS hands it over; setting it lazily — when the first
        // notification is posted, say — loses every tap on a notification that
        // was already sitting in Notification Center.
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            // ⚠️ NEVER SWALLOW THIS. The first version was `{ _, _ in }` with a
            // comment saying denial was fine — and it hid the fact that the
            // request was failing outright, so keep-watch promised a live alert
            // that could never arrive. Denial IS fine; not knowing is not.
            Task { @MainActor in
                self.notificationsAllowed = granted
                self.notificationProblem = error?.localizedDescription
                /*
                 ⚠️ AN AD-HOC BUILD LOSES THIS EVERY TIME IT IS REBUILT. macOS ties
                 notification authorization to the app's code signature, and
                 `build.sh` signs ad-hoc — a fresh signature each build, so the
                 system sees a different app and denies it. Two runs of the same
                 code minutes apart logged `didGrant: 1` and then `didGrant: 0`
                 for exactly this reason. Notification behavior is only ever true
                 when measured on the signed, notarized build; the local loop
                 cannot tell you anything about it.
                 */
                if let error { FileHandle.standardError.write("notifications: \(error)\n".data(using: .utf8)!) }
                self.model?.notificationsBlocked = !granted
            }
        }
    }

    /// Whether macOS will actually deliver what this posts.
    @Published private(set) var notificationsAllowed = true
    private(set) var notificationProblem: String?

    // ── what a tap does ────────────────────────────────────────────────
    //
    // ⚠️ A NOTIFICATION THAT GOES NOWHERE IS WORSE THAN NO NOTIFICATION. Tony:
    // "the notfications that pop up go nowhere when you click them." They told
    // somebody a key had just been written and then dropped them on the floor —
    // an alert whose entire content is "go and look at this" has to be the thing
    // that takes you there. Without a delegate a tap does nothing at all, which
    // is the same silent-no-op family as the menu bar's Open item.

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completion: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            self.act(on: info)
            completion()
        }
    }

    /// ⚠️ macOS SUPPRESSES A BANNER WHILE THE APP IS FRONTMOST unless this says
    /// otherwise. The window being open does not mean somebody is looking at it,
    /// and a key landing in a transcript is worth saying out loud either way.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        // No sound: resident means quiet.
        completion([.banner, .list])
    }

    /// The tap handler proper, separated so it can be exercised without
    /// synthesising a UNNotificationResponse — which cannot be constructed.
    func act(on info: [AnyHashable: Any]) {
        showWindow()
        switch info["action"] as? String {
        case "live":
            // A key was written moments ago, so the recorded results predate it.
            // Re-scan the installations: the finding arrives real, with its
            // "Remove the key from this transcript" button attached.
            model?.scan(.installations)
        default:
            // A scheduled scan already did the work in the background; show what
            // it found rather than making somebody run it again.
            model?.presentHistory()
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
        content.userInfo = ["action": "results"]
        deliver(content, id: "scan-\(Date().timeIntervalSince1970)")
    }

    /// ⚠️ ONE BANNER FOR A BURST, NOT ONE PER FILE. Saving work can touch
    /// several transcripts at once, and a stack of identical banners is how a
    /// useful alert becomes noise somebody turns off.
    private func notifyLiveKeys(_ hits: [TranscriptWatcher.Hit]) {
        guard let first = hits.first else { return }
        let content = UNMutableNotificationContent()
        let unique = Array(Set(hits.flatMap(\.vendors))).sorted()
        content.title = hits.count == 1
            ? "A key was just written to a conversation log"
            : "Keys were just written to \(hits.count) conversation logs"
        // ⚠️ THE VENDOR AND THE FILE NAME, NEVER THE KEY. And the path's last
        // component only — a notification banner is the most public pixel on
        // the screen.
        let where_: String
        if hits.count == 1 {
            where_ = TranscriptWatcher.agent(forPath: first.path).map { "a \($0) conversation" }
                ?? (first.path as NSString).lastPathComponent
        } else {
            let agents = Set(hits.compactMap { TranscriptWatcher.agent(forPath: $0.path) }).sorted()
            where_ = agents.isEmpty ? "\(hits.count) conversation logs"
                : "\(hits.count) \(agents.joined(separator: " and ")) conversations"
        }
        content.body = "\(unique.joined(separator: " and ")) key\(unique.count == 1 ? "" : "s") in \(where_). Click to open Templeton Protect and remove it."
        // ⚠️ THE PATH DOES NOT TRAVEL IN userInfo. A notification's payload is
        // stored by the system and survives in Notification Center; the tap only
        // needs to know which scan to run.
        content.userInfo = ["action": "live"]
        deliver(content, id: "live-\(hits.map(\.path).sorted().joined().hashValue)")
    }

    private func deliver(_ content: UNMutableNotificationContent, id: String) {
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
