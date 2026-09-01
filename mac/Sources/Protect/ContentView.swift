import SwiftUI
import ProtectCore

// The interface. Three states, and the layout is the state.

enum Phase { case idle, scanning, done }

@MainActor final class Model: ObservableObject {
    @Published var phase: Phase = .idle
    /**
     ⚠️ ONE RESULTS SCREEN FOR THREE SCANS, AND THE RESULTS ACCUMULATE. Somebody
     with a key in a transcript, a firewall that is off and an `.env` committed to
     a repository has one problem — this Mac — and making them run three scans and
     read three separate reports is asking them to do the joining up. Running a
     second scan adds to the list; it does not replace it.
     */
    @Published var results: [ScanKind: ScanResult] = [:]
    /// Which scan is running, or the one whose results are on screen.
    @Published var active: ScanKind = .installations
    @Published var elapsed = 0
    @Published var outcomes: [String: FixOutcome] = [:]
    @Published var armed: Set<String> = []
    /// What is on this Mac, found without scanning. Populated on appear.
    @Published var installed: [Installed] = []
    /// What this Mac is. Read once, on appear, for the hardware card.
    @Published var spec: MachineSpec?
    /// The folder the code scan points at. Nil until somebody chooses one.
    @Published var codeTarget: CodeTarget?
    /// Also walk the repository's history — slower, so it is a choice.
    @Published var deepCode = UserDefaults.standard.bool(forKey: deepCodeKey) {
        didSet { UserDefaults.standard.set(deepCode, forKey: deepCodeKey) }
    }
    @Published var stages: [Stage] = []
    @Published var currentFile = ""
    @Published var currentFolder = ""
    @Published var filesRead = 0
    @Published var foundSoFar = 0
    @Published var stageHeadline = "Reading your AI installations…"
    @Published var exportedTo: URL?
    @Published var exportError: String?
    /// What changed since the previous scan of the active kind. Nil on a first
    /// scan, .isQuiet when nothing moved.
    @Published var lastDelta: ScanDelta?
    let history = HistoryStore()
    /// Reaches the Resident controller owned by the app delegate; a closure so
    /// the Model does not own the lifecycle.
    var resident: (() -> Resident?)?
    /// Mirrors Resident.enabled so SwiftUI sees the change; the Resident owns
    /// the machinery, this owns the pixels.
    /// macOS refused to let this app post notifications. Keep watch still runs
    /// and the menu bar line still reports; the live alert cannot arrive.
    @Published var notificationsBlocked = false
    @Published var keepWatch = UserDefaults.standard.bool(forKey: "keepWatch") {
        didSet { resident?()?.enabled = keepWatch }
    }
    private var timer: Timer?

    /**
     Show what the background scans already found.

     Used when a notification is tapped: the work happened in the background, so
     making somebody press Scan again to see it would be asking them to redo it.
     Unlike `refreshFromHistory`, this deliberately moves the screen to the
     results — it is a response to a click, not a quiet catch-up.
     */
    func presentHistory() {
        guard phase != .scanning else { return }
        var any = false
        for kind in ScanKind.allCases {
            guard let record = history.previous(kind: kind.rawValue) else { continue }
            results[kind] = record.result
            any = true
        }
        if any { phase = .done }
    }

    /// A background (menu bar) scan finished; pick up its results so the window
    /// agrees with the notification that just fired.
    func refreshFromHistory() {
        guard phase != .scanning else { return }
        for kind in ScanKind.allCases {
            if let record = history.previous(kind: kind.rawValue) {
                // Only kinds that have genuinely run — never invent a result.
                if results[kind] != nil || phase == .done { results[kind] = record.result }
            }
        }
    }

    /// Every finding from every scan that has been run, worst first.
    var combined: ScanResult? {
        guard !results.isEmpty else { return nil }
        let all = results.values.flatMap(\.findings)
        return ScanResult(findings: sortedForDisplay(all),
                          toolsFound: results.values.flatMap(\.toolsFound),
                          filesRead: results.values.reduce(0) { $0 + $1.filesRead })
    }

    func has(_ kind: ScanKind) -> Bool { results[kind] != nil }

    func detect() {
        guard installed.isEmpty else { return }
        // ⚠️ OFF THE MAIN THREAD. Measured at 283ms on a working machine — not
        // enough to notice in a terminal, plenty to drop frames on launch.
        Task.detached(priority: .userInitiated) {
            let found = detectInstallations()
            await MainActor.run { self.installed = found }
        }
        // ⚠️ ALSO OFF IT, AND FOR THE SAME REASON. describeMachine shells out to
        // system_profiler, which is 155ms on this Mac and unbounded on one that
        // is busy. The card says "Reading…" until it lands rather than holding
        // the launch.
        Task.detached(priority: .userInitiated) {
            let spec = describeMachine()
            await MainActor.run { self.spec = spec }
        }
        // A folder chosen in an earlier session, if there was one.
        if let remembered = UserDefaults.standard.string(forKey: codeFolderKey),
           FileManager.default.fileExists(atPath: remembered) {
            Task.detached(priority: .userInitiated) {
                let t = describeCodeTarget(remembered)
                await MainActor.run { self.codeTarget = t }
            }
        }
    }

    /**
     ⚠️ THE OPEN PANEL IS THE PERMISSION, exactly as the save panel is for
     exports. This app reads a folder full of somebody's source code; the one
     honest way to decide which folder that is, is to have them point at it. It
     is also what authorizes a fix inside that tree — see `insideScannedTree`.
     */
    func chooseCodeFolder(thenScan: Bool = true) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a folder to scan"
        panel.prompt = "Choose"
        panel.message = "Pick the top of a project. Everything inside it is read, and nothing is changed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: codeFolderKey)
        Task.detached(priority: .userInitiated) {
            let t = describeCodeTarget(url.path)
            await MainActor.run {
                self.codeTarget = t
                if thenScan { self.scan(.code) }
            }
        }
    }

    /// ⚠️ NOT AN ACTOR-ISOLATED FLAG. The scan runs on a detached task and polls
    /// this between files; hopping to the main actor 8,000 times to read a Bool
    /// would cost more than the scan.
    private let cancelled = Cancellation()

    func scan(_ kind: ScanKind) {
        guard phase != .scanning else { return }
        // The code scan cannot start without somewhere to point it.
        if kind == .code, codeTarget == nil { chooseCodeFolder(); return }

        active = kind
        phase = .scanning
        elapsed = 0
        armed = []
        filesRead = 0
        foundSoFar = 0
        currentFile = ""
        currentFolder = ""
        cancelled.reset()

        switch kind {
        case .machine:
            stages = machineStages.map { Stage(tool: $0, dir: $0, state: .waiting) }
            stageHeadline = "Reading this Mac…"
        case .installations:
            stages = installed.map { Stage(tool: $0.tool, dir: $0.dir, state: .waiting) }
                + [Stage(tool: "Agent permissions", dir: "what your agents may do", state: .waiting)]
            stageHeadline = "Reading your AI installations…"
        case .code:
            let name = codeTarget.map { ($0.path as NSString).lastPathComponent } ?? "your code"
            stages = [Stage(tool: name, dir: name, state: .waiting)]
            if deepCode { stages.append(Stage(tool: "History", dir: "every commit", state: .waiting)) }
            stageHeadline = "Reading \(name)…"
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
        let folder = codeTarget?.path
        let deep = deepCode
        // Captured before the hop: HistoryStore is not actor-isolated, and its
        // writes are distinct timestamped files, so concurrent records cannot
        // clobber each other.
        let history = self.history
        Task.detached(priority: .userInitiated) { [cancelled] in
            // ⚠️ THROTTLED, AND ON PURPOSE. The callback fires once per file
            // read — thousands of times — and publishing every one of them
            // repaints the window faster than it can draw and starves the scan
            // of the very CPU it is asking for. Twelve a second is past what
            // anyone can read anyway.
            let throttle = Throttle(interval: 1.0 / 12.0)
            let report: (ScanProgress) -> Void = { p in
                let finished = p.finishedTool
                if finished == nil && !throttle.ready() { return }
                Task { @MainActor [weak self] in self?.absorb(p) }
            }
            let r: ScanResult
            switch kind {
            case .machine:
                r = scanMachine(isCancelled: { cancelled.isSet }, progress: report)
            case .installations:
                r = scanAiInstallations(isCancelled: { cancelled.isSet }, progress: report)
            case .code:
                if let folder {
                    var result = scanCode(at: folder, isCancelled: { cancelled.isSet }, progress: report)
                    if deep && !cancelled.isSet {
                        // The history pass reports as its own stage so the wait
                        // has a name — pickaxe over a real repository is seconds.
                        report(ScanProgress(tool: "History", path: "searching every commit",
                                            filesRead: result.filesRead,
                                            findingsSoFar: result.findings.count,
                                            finishedTool: nil, finishedFindings: nil))
                        let hist = scanGitHistory(at: folder, isCancelled: { cancelled.isSet })
                        result = ScanResult(findings: sortedForDisplay(result.findings + hist),
                                            toolsFound: result.toolsFound,
                                            filesRead: result.filesRead)
                        report(ScanProgress(tool: "History", path: "",
                                            filesRead: result.filesRead,
                                            findingsSoFar: result.findings.count,
                                            finishedTool: "History", finishedFindings: hist.count))
                    }
                    r = result
                } else {
                    r = ScanResult(findings: [], toolsFound: [], filesRead: 0)
                }
            }
            let delta = history.record(kind: kind.rawValue, result: r)
            await MainActor.run {
                self.timer?.invalidate()
                // A stopped scan keeps what it had found by then; throwing it
                // away would make Stop feel like a punishment.
                self.results[kind] = r
                self.lastDelta = delta
                self.phase = .done
            }
        }
    }

    func cancel() {
        cancelled.set()
        stageHeadline = "Stopping…"
    }

    @MainActor private func absorb(_ p: ScanProgress) {
        filesRead = p.filesRead
        foundSoFar = p.findingsSoFar
        if let finished = p.finishedTool, let n = p.finishedFindings {
            if let i = stages.firstIndex(where: { $0.tool == finished }) {
                withAnimation(.easeInOut(duration: 0.28)) { stages[i].state = .done(n) }
            }
            return
        }
        // ⚠️ THE TILES CAN ARRIVE LATE. Stages are seeded from the pre-scan
        // detection, and a scan started before that finished — or straight from
        // the menu — would otherwise run with no tiles at all. Any tool the
        // progress mentions and the list does not have gets added here.
        if let i = stages.firstIndex(where: { $0.tool == p.tool }) {
            if case .waiting = stages[i].state {
                withAnimation(.easeInOut(duration: 0.28)) { stages[i].state = .running }
                stageHeadline = "Reading \(p.tool)…"
            }
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                stages.append(Stage(tool: p.tool, dir: p.tool, state: .running))
            }
            stageHeadline = "Reading \(p.tool)…"
        }
        // ⚠️ SPLIT THE STRING, DO NOT BUILD A URL. The scanner hands over a
        // display path beginning "~/", and URL(fileURLWithPath:) resolves that
        // back to /Users/<name>/… — so the screen showed the absolute path,
        // complete with the account name, in a panel meant to be shown to
        // somebody looking over your shoulder.
        let parts = p.path.split(separator: "/", omittingEmptySubsequences: false)
        currentFile = String(parts.last ?? "")
        currentFolder = parts.dropLast().joined(separator: "/")
    }

    /// ⚠️ THE SAVE PANEL IS THE PERMISSION PROMPT. Writing a report full of file
    /// paths straight into Downloads without asking is the sort of thing this app
    /// exists to warn people about; the user picks the destination, every time.
    func export(_ format: ExportFormat) {
        guard let result = combined else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFilename(format)
        panel.canCreateDirectories = true
        panel.title = "Export findings"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .pdf:
                try PDFReport.write(result, to: url)
            case .csv:
                try exportCSV(result).write(to: url, atomically: true, encoding: .utf8)
            case .markdown:
                try exportMarkdown(result).write(to: url, atomically: true, encoding: .utf8)
            }
            exportedTo = url
        } catch {
            exportError = error.localizedDescription
        }
    }

    func apply(_ finding: Finding) {
        guard let fix = finding.fix else { return }
        // ⚠️ THE CHOSEN FOLDER TRAVELS WITH THE FIX. Without it every fix the
        // code scan offers is refused by insideScannedTree, which only knows
        // about the AI home directories — a button that always fails.
        let extra = codeTarget.map { [$0.path] } ?? []
        Task.detached(priority: .userInitiated) {
            let outcome = applyFix(fix, extraRoots: extra)
            await MainActor.run { self.outcomes[finding.identity] = outcome }
        }
    }
}

private let codeFolderKey = "codeFolder"
private let deepCodeKey = "deepCode"

/// Worst first, and stable inside a severity so the list does not reshuffle
/// when a second scan adds to it.
func sortedForDisplay(_ findings: [Finding]) -> [Finding] {
    findings.sorted { a, b in
        if a.severity != b.severity { return a.severity.rank < b.severity.rank }
        if a.layer != b.layer { return a.layer < b.layer }
        return a.where_ < b.where_
    }
}

/// The bridge for the export menu. NSMenuItem needs an Objective-C target, and a
/// SwiftUI view is not one.
@MainActor
final class ExportTarget: NSObject {
    weak var model: Model?
    @objc func pick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let format = ExportFormat(rawValue: raw) else { return }
        model?.export(format)
    }
}

struct ContentView: View {
    // ⚠️ ONE MODEL, OWNED BY THE DELEGATE. The menu item and the button must
    // drive the same scan; a @StateObject here would give the menu its own.
    @ObservedObject var model: Model
    private let exportTarget = ExportTarget()

    var body: some View {
        ZStack {
            Aurora()
            // ⚠️ safeAreaInset, NOT PADDING AND NOT A SPACER VIEW. Two attempts
            // failed before this one and both failed silently. Padding inside the
            // scroll view scrolls away the moment the content is taller than the
            // window, putting the headline under the traffic lights. A fixed
            // strip stacked above the scroll view is worse: the VStack then
            // wanted more height than the ZStack had, so the ZStack centred it
            // and pushed the strip off the top of the window entirely — measured,
            // by painting it red and finding zero red pixels on screen. An inset
            // is the one form the scroll view itself honours.
            ScrollView {
                content
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.xl)
            }
            // ⚠️ THE SCROLL VIEW MUST BE CLAMPED TO THE WINDOW, and this line is
            // the whole fix. Without it the scroll view took its content's ideal
            // height — around 860pt of hero against a 720pt window — the ZStack
            // grew to match, and a ZStack centres its children, so the top ~70pt
            // was pushed off the screen. Nothing scrolled, because nothing
            // thought it had to. That is why three separate attempts at a top
            // inset all measured identically at 13pt: the inset was there every
            // time, just above the visible edge of the window.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, Chrome.titleBar)
        }
        .frame(minWidth: 860, minHeight: 580)
        .onAppear {
            model.detect()
            // Lets a screenshot reach the results screen without a click. The
            // app's own layout is the thing being checked, so it has to be the
            // real scan and the real findings, not a fixture.
            //
            // PROTECT_AUTOSCAN=machine|installations|code, or =1 for the
            // installations scan, which is what it meant when there was one.
            if let want = ProcessInfo.processInfo.environment["PROTECT_AUTOSCAN"] {
                model.scan(ScanKind(rawValue: want) ?? .installations)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if model.phase == .idle {
            VStack(spacing: 0) {
                hero.frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
                madeBy
            }
        } else if model.phase == .scanning {
            VStack(spacing: 0) {
                ScanningView(model: model)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                madeBy
            }
        } else {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Space.xl) {
                    compactHeader
                    runStrip
                    deltaLine
                    if let r = model.combined { summary(r); findings(r) }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                madeBy
            }
        }
    }

    /// The same footer Radiant and AiOS carry, so the three read as one company's
    /// products rather than three unrelated apps.
    private var madeBy: some View {
        VStack(spacing: Space.md) {
            Rectangle().fill(Ink.panelEdge).frame(height: 1)
                .padding(.bottom, Space.xs)
            Text("Templeton Protect is a Templeton Technologies product")
                .font(.system(size: FontSize.caption))
                .tracking(0.24)
                .foregroundStyle(Ink.secondary(Dim.faint))
            Button {
                // ⚠️ NSWorkspace, not a SwiftUI Link. The app is assembled by hand
                // rather than by Xcode, and opening a URL is the one thing here
                // that leaves the process — do it through the API that always
                // hands off to the browser.
                if let url = URL(string: "https://templetontech.com") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                if let logo = Bundle.main.image(forResource: "templeton-tech") {
                    // ⚠️ A FOOTER MARK IS A SIGNATURE, NOT A BILLBOARD. At 220pt
                    // it dominated the bottom of the window — Tony: "the templeton
                    // technologies logo is way to big in the footer." A company
                    // attribution the same visual weight as the product's own
                    // content reads as the wrong thing being the subject.
                    Image(nsImage: logo)
                        .resizable().scaledToFit()
                        .frame(width: 132)
                        .opacity(Dim.muted)
                } else {
                    // The mark is a bundled asset, so this should not happen —
                    // but a footer that silently vanishes is worse than a word.
                    Text("Templeton Technologies")
                        .font(.system(size: FontSize.small, weight: .semibold))
                        .foregroundStyle(Ink.secondary())
                }
            }
            .buttonStyle(.plain)
            .help("templetontech.com")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xl)
    }

    // ── idle ──────────────────────────────────────────────────────────
    //
    // ⚠️ THE FIRST VERSION WAS A TITLE, A CIRCLE AND A PARAGRAPH IN A VOID.
    // Centered, symmetrical, and saying nothing the product page does not
    // already say — a scanner whose opening screen has learned nothing about
    // your machine has no reason to be an app. The second version read the AI
    // installations before you pressed anything. This one does that for all
    // three scans: what the Mac is, what is installed on it, and which folder
    // the code scan is pointed at, all before a click.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            pitch
            cards
            keepWatchRow
        }
        .padding(.vertical, Space.xl)
    }

    /// The Protect+ row: the resident layer, and the line where the paid
    /// product starts. The engine above it is open source; this is the part
    /// that runs on your behalf.
    private var keepWatchRow: some View {
        HStack(alignment: .center, spacing: Space.lg) {
            Image(systemName: model.keepWatch ? "eye.fill" : "eye")
                .font(.system(size: FontSize.title))
                .foregroundStyle(model.keepWatch ? Ink.accent : Ink.secondary(Dim.faint))
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text("Keep watch")
                        .font(.system(size: FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.primary)
                    Text("PROTECT+")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.navy)
                        .padding(.horizontal, Space.sm).padding(.vertical, 2)
                        .background(Capsule().fill(Ink.accent))
                }
                Text(model.keepWatch
                     ? "Watching from the menu bar: scans re-run on a schedule, and a key written to a conversation log is flagged the moment it lands."
                     : "Stay in the menu bar, re-run the scans on a schedule, and catch a key the moment it is written to a conversation log — instead of whenever you next press the button.")
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(Ink.secondary(Dim.strong))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.lg)
            // ⚠️ DO NOT PROMISE AN ALERT THAT CANNOT ARRIVE. Keep watch still
            // runs with notifications refused — the schedule, the history and the
            // menu bar line all work — but the live alert is the headline of this
            // feature, and silently not delivering it is the worst version of
            // "it's on". Say so, and point at the switch that fixes it.
            if model.keepWatch && model.notificationsBlocked {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "bell.slash.fill")
                        Text("Alerts are off")
                    }
                    .font(.system(size: FontSize.caption, weight: .semibold))
                    .foregroundStyle(Ink.critical)
                    .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                    .background(Capsule().strokeBorder(Ink.critical.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("macOS is not allowing Templeton Protect to post notifications. Scans and the menu bar still work.")
            }
            Toggle("", isOn: $model.keepWatch)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Ink.accent)
        }
        .padding(Space.lg)
        .contentSurface(radius: Radius.card)
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("TEMPLETON PROTECT")
                .font(.system(size: FontSize.caption, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Ink.accent)
            Text("Scan your Mac, your assistants,\nand your code.")
                .font(.system(size: FontSize.display, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Three scans, run in any order, and the findings collect into one list. All of it happens on this Mac, all of it is read-only, and anything shown to you has the secret itself blanked out first.")
                .font(.system(size: FontSize.body))
                .foregroundStyle(Ink.secondary())
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    /// ⚠️ EQUAL HEIGHTS, and it takes both halves of this. maxHeight makes each
    /// card fill whatever the row is; fixedSize makes the row exactly as tall as
    /// its tallest card. With only the first, the row collapses; with only the
    /// second, the cards keep their own ragged heights — three panels of three
    /// different sizes, which is what the first attempt looked like.
    private var cards: some View {
        HStack(alignment: .top, spacing: Space.md) {
            ForEach(ScanKind.allCases, id: \.self) { scanCard($0) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func scanCard(_ kind: ScanKind) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(systemName: kind.icon)
                    .font(.system(size: FontSize.lead))
                    .foregroundStyle(Ink.accent)
                Spacer(minLength: 0)
                // ⚠️ A SCAN THAT HAS ALREADY RUN SAYS SO, ON ITS OWN CARD. Going
                // back to this screen after one scan and finding it unchanged
                // makes it look as though nothing happened.
                if let r = model.results[kind] {
                    Text(r.findings.isEmpty ? "clear" : "\(r.findings.count) found")
                        .font(.system(size: FontSize.caption, weight: .medium))
                        .foregroundStyle(r.findings.isEmpty ? Ink.good : Ink.critical)
                }
            }

            Text(kind.title)
                .font(.system(size: FontSize.lead, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            // What is already known about this Mac, before anything is pressed.
            //
            // ⚠️ TWO SEPARATE LINES, NOT ONE STRING WITH A NEWLINE IN IT. As one
            // Text with lineLimit(2), a long first line wrapped and consumed the
            // budget, so the second fact — the file count, the amount of free
            // disk — simply vanished behind an ellipsis on every card.
            VStack(alignment: .leading, spacing: 2) {
                let (first, second) = preview(kind)
                Text(first).lineLimit(1).truncationMode(.tail)
                Text(second).lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: FontSize.caption, design: .monospaced))
            .foregroundStyle(Ink.secondary(Dim.strong))
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(kind.blurb)
                .font(.system(size: FontSize.caption))
                .foregroundStyle(Ink.secondary(Dim.faint))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.sm)

            Button { model.scan(kind) } label: {
                Text(buttonLabel(kind))
                    .font(.system(size: FontSize.small, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.navy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.md)
                    .primaryAction()
            }
            .buttonStyle(.plain)

            if kind == .code, model.codeTarget?.isRepository == true {
                Toggle(isOn: $model.deepCode) {
                    Text("Also search the repository's history")
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(Ink.secondary(Dim.strong))
                }
                .toggleStyle(.checkbox)
                .help("Finds secrets that were committed and later deleted — they stay in the history. Slower, so it is a choice.")
            }

            // ⚠️ THE FOLDER HAS TO BE CHANGEABLE WITHOUT SCANNING IT FIRST.
            // Without this the only way to pick a different project is to run a
            // scan of the wrong one and come back.
            if kind == .code, model.codeTarget != nil {
                Button { model.chooseCodeFolder(thenScan: false) } label: {
                    // ⚠️ NOT .underline(). It arrived in macOS 13 and this app
                    // still runs on 12, where the modifier does not exist at all.
                    Text("Choose a different folder…")
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(Ink.accent.opacity(Dim.strong))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentSurface(radius: Radius.card)
    }

    private func buttonLabel(_ kind: ScanKind) -> String {
        if model.has(kind) { return "Scan again" }
        if kind == .code && model.codeTarget == nil { return "Choose a folder…" }
        return "Scan"
    }

    /// ⚠️ EVERY LINE HERE IS SOMETHING THE APP HAS ACTUALLY READ. It is tempting
    /// to fill three cards with feature copy, and a security tool that overstates
    /// what it checks is worse than one that says nothing at all.
    private func preview(_ kind: ScanKind) -> (String, String) {
        switch kind {
        case .machine:
            guard let spec = model.spec else { return ("Reading this Mac…", " ") }
            return ("\(spec.model) · \(spec.chip)",
                    "macOS \(spec.systemShort) · \(spec.memory) · \(spec.free)")
        case .installations:
            if model.installed.isEmpty { return ("Looking for AI assistants…", " ") }
            let tools = model.installed.map(\.tool)
            let named = tools.prefix(3).joined(separator: ", ")
                + (tools.count > 3 ? " +\(tools.count - 3)" : "")
            let total = model.installed.reduce(0) { $0 + $1.files }
            let capped = model.installed.contains { $0.atLeast }
            return (named, "\(total.formatted())\(capped ? "+" : "") files to check")
        case .code:
            guard let t = model.codeTarget else {
                return ("No folder chosen yet.", "Pick the top of a project.")
            }
            return (t.display,
                    "\(t.atLeast ? "\(t.files)+" : "\(t.files)") files\(t.isRepository ? " · git repository" : "")")
        }
    }

    // ── header once scanning or done ──────────────────────────────────
    private var compactHeader: some View {
        HStack(spacing: Space.lg) {
            // ⚠️ BACK, NOT RE-SCAN. With three scans there is no single thing
            // to repeat, and the button that used to re-run the only scan now
            // has to return somewhere a choice can be made.
            Button { model.phase = .idle } label: {
                VStack(spacing: 2) {
                    if model.phase == .scanning {
                        Text("…")
                            .font(.system(size: FontSize.lead, weight: .semibold, design: .rounded))
                    } else {
                        // ⚠️ AN ARROW, BECAUSE THE WORD ALONE IS NOT AN AFFORDANCE —
                        // and both of them in champagne, because half a control in
                        // the accent and half in the ink reads as two things that
                        // happen to be near each other rather than one button.
                        Image(systemName: "chevron.left")
                            .font(.system(size: FontSize.body, weight: .semibold))
                        Text("Back")
                            .font(.system(size: FontSize.caption, weight: .semibold, design: .rounded))
                    }
                }
                .foregroundStyle(Ink.accent)
                .frame(width: 84, height: 84)
                /*
                 ⚠️ contentShape, OR ONLY THE GLYPHS ARE CLICKABLE. Tony: "that
                 back button is awkward in that it only works if you click
                 exactly on the Back text."

                 The 84pt frame lays the button out at 84pt and the glass draws a
                 disc that size, but a `.frame` around text does not give SwiftUI
                 anything to hit-test in the empty space around it — the label's
                 hit region stays the shape of the letters. So the control looks
                 like a large target and behaves like a small one, which is worse
                 than looking small, because the miss is unexplained. This states
                 the region explicitly, and it is the circle you can see.
                 */
                .contentShape(Circle())
                .glassCircle()
            }
            .buttonStyle(.plain)
            .help("Back to the three scans")

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Templeton Protect")
                    .font(.system(size: FontSize.title, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                if model.phase == .scanning {
                    // ⚠️ THE WAIT IS REAL, SO IT IS SHOWN. Seventeen seconds of a
                    // still spinner reads as hung; the count says it is working.
                    Text("Reading configuration and conversation logs… \(model.elapsed)s")
                        .font(.system(size: FontSize.small)).foregroundStyle(Ink.secondary())
                } else if let r = model.combined {
                    Text(ranSummary(r))
                        .font(.system(size: FontSize.small)).foregroundStyle(Ink.secondary())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()

            if model.combined != nil {
                // ⚠️ AN AppKit MENU, NOT SwiftUI's. SwiftUI's Menu painted over
                // both the champagne background and the navy text, so the only
                // control on the screen came out as plain white text on the
                // aurora; the styles that fix that need macOS 13 and this app
                // still runs on 12. NSMenu takes the styling as given.
                Button {
                    let menu = NSMenu()
                    for format in ExportFormat.allCases {
                        let item = NSMenuItem(title: format.label,
                                              action: #selector(ExportTarget.pick(_:)), keyEquivalent: "")
                        item.target = exportTarget
                        item.representedObject = format.rawValue
                        menu.addItem(item)
                    }
                    exportTarget.model = model
                    // ⚠️ THE FALLBACK IS THE POINT. popUpContextMenu needs a
                    // current event, and if there is none the button does
                    // nothing at all — a control that silently refuses to work
                    // is the worst failure a button can have.
                    if let view = NSApp.keyWindow?.contentView {
                        if let event = NSApp.currentEvent {
                            NSMenu.popUpContextMenu(menu, with: event, for: view)
                        } else {
                            menu.popUp(positioning: nil,
                                       at: view.convert(NSEvent.mouseLocation, from: nil),
                                       in: view)
                        }
                    }
                } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export findings")
                    }
                    .font(.system(size: FontSize.small, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.navy)
                    .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                    .primaryAction()
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
    }

    /// What has run, and a button for what has not.
    ///
    /// ⚠️ THE RESULTS SCREEN IS A DEAD END WITHOUT THIS. Somebody who runs the
    /// hardware scan first and then wants the other two should not have to work
    /// out that the way back is a button labeled with a different word.
    private var runStrip: some View {
        HStack(spacing: Space.sm) {
            ForEach(ScanKind.allCases, id: \.self) { kind in
                Button { model.scan(kind) } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: model.has(kind) ? "checkmark.circle.fill" : kind.icon)
                            .font(.system(size: FontSize.caption))
                            .foregroundStyle(model.has(kind) ? Ink.good : Ink.accent)
                        Text(model.has(kind) ? kind.title : "\(kind.title) — not run yet")
                            .font(.system(size: FontSize.caption, weight: .medium))
                            .foregroundStyle(model.has(kind) ? Ink.secondary(Dim.strong) : Ink.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                    .background(Capsule().strokeBorder(Ink.panelEdge, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(model.has(kind) ? "Run this scan again" : kind.blurb)
            }
            Spacer(minLength: 0)
        }
    }

    /// "2 new since Tuesday, 3 fixed" — the sentence that makes re-scanning
    /// worth it. Absent on a first scan, and explicit when nothing moved,
    /// because silence reads as a broken feature rather than a quiet week.
    @ViewBuilder private var deltaLine: some View {
        if let d = model.lastDelta {
            HStack(spacing: Space.sm) {
                if d.isQuiet {
                    Image(systemName: "equal.circle.fill")
                        .foregroundStyle(Ink.good)
                    Text("No change since \(relative(d.since)).")
                        .foregroundStyle(Ink.secondary(Dim.strong))
                } else {
                    if !d.new.isEmpty {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(Ink.critical)
                        Text("\(d.new.count) new since \(relative(d.since))")
                            .foregroundStyle(Ink.primary)
                    }
                    if !d.fixed.isEmpty {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.good)
                        Text("\(d.fixed.count) fixed")
                            .foregroundStyle(Ink.secondary(Dim.strong))
                    }
                }
            }
            .font(.system(size: FontSize.small, weight: .medium))
        }
    }

    private func relative(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    private func ranSummary(_ r: ScanResult) -> String {
        var parts: [String] = []
        if model.has(.machine) { parts.append("15 settings on this Mac") }
        if let installs = model.results[.installations] {
            parts.append("\(installs.filesRead.formatted()) files across \(installs.toolsFound.count) installations")
        }
        if let code = model.results[.code], let t = model.codeTarget {
            parts.append("\(code.filesRead.formatted()) files in \((t.path as NSString).lastPathComponent)")
        }
        return "Checked " + parts.joined(separator: ", ") + "."
    }

    // ── summary ───────────────────────────────────────────────────────
    private func summary(_ r: ScanResult) -> some View {
        HStack(spacing: Space.md) {
            tile("\(r.findings.filter { $0.severity == .critical }.count)", "Critical", Ink.critical)
            tile("\(r.findings.filter { $0.severity == .high }.count)", "Worth fixing", Ink.high)
            tile("\(r.findings.filter { $0.severity == .low || $0.severity == .medium }.count)", "Minor", Ink.secondary(Dim.strong))
        }
    }

    private func tile(_ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(value).font(.system(size: FontSize.display, weight: .semibold, design: .rounded))
                .foregroundStyle(tint).monospacedDigit()
            Text(caption.uppercased()).font(.system(size: FontSize.caption, weight: .medium))
                .tracking(0.6).foregroundStyle(Ink.secondary(Dim.faint))
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(radius: Radius.card)
    }

    /// ⚠️ THE ALL-CLEAR MUST NAME WHAT IT COVERS. "Nothing to worry about" after
    /// a hardware scan, on a Mac whose transcripts have never been read, is a
    /// clean bill of health for a check that never ran.
    private var emptyStateLine: String {
        let ran = ScanKind.allCases.filter { model.has($0) }
        let names = ran.map { kind -> String in
            switch kind {
            case .machine: return "this Mac's settings"
            case .installations: return "your AI conversation logs"
            case .code: return "the folder you chose"
            }
        }
        let checked = names.count == 1 ? names[0]
            : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        let missing = ScanKind.allCases.filter { !model.has($0) }
        return "Nothing found in \(checked)."
            + (missing.isEmpty ? "" : " The other \(missing.count == 1 ? "scan has" : "scans have") not been run.")
    }

    // ── findings ──────────────────────────────────────────────────────
    @ViewBuilder private func findings(_ r: ScanResult) -> some View {
        if r.findings.isEmpty {
            VStack(spacing: Space.md) {
                Text("Nothing to worry about")
                    .font(.system(size: FontSize.title, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                Text(emptyStateLine)
                    .font(.system(size: FontSize.small)).foregroundStyle(Ink.secondary())
                    .multilineTextAlignment(.center)
            }
            .padding(Space.xxl).frame(maxWidth: .infinity).contentSurface(radius: Radius.panel)
        } else {
            VStack(spacing: Space.md) {
                ForEach(r.findings, id: \.identity) { FindingCard(finding: $0, model: model) }
            }
        }
    }
}
