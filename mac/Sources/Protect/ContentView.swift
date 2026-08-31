import SwiftUI
import ProtectCore

// The interface. Three states, and the layout is the state.

enum Phase { case idle, scanning, done }

@MainActor final class Model: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var result: ScanResult?
    @Published var elapsed = 0
    @Published var outcomes: [String: FixOutcome] = [:]
    @Published var armed: Set<String> = []
    /// What is on this Mac, found without scanning. Populated on appear.
    @Published var installed: [Installed] = []
    @Published var exportedTo: URL?
    @Published var exportError: String?
    private var timer: Timer?

    func detect() {
        guard installed.isEmpty else { return }
        // ⚠️ OFF THE MAIN THREAD. Measured at 283ms on a working machine — not
        // enough to notice in a terminal, plenty to drop frames on launch.
        Task.detached(priority: .userInitiated) {
            let found = detectInstallations()
            await MainActor.run { self.installed = found }
        }
    }

    func scan() {
        guard phase != .scanning else { return }
        phase = .scanning
        elapsed = 0
        outcomes = [:]
        armed = []
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
        Task.detached(priority: .userInitiated) {
            let r = scanAiInstallations()
            await MainActor.run {
                self.timer?.invalidate()
                self.result = r
                self.phase = .done
            }
        }
    }

    /// ⚠️ THE SAVE PANEL IS THE PERMISSION PROMPT. Writing a report full of file
    /// paths straight into Downloads without asking is the sort of thing this app
    /// exists to warn people about; the user picks the destination, every time.
    func export(_ format: ExportFormat) {
        guard let result else { return }
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
        Task.detached(priority: .userInitiated) {
            let outcome = applyFix(fix)
            await MainActor.run { self.outcomes[finding.where_] = outcome }
        }
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
            if ProcessInfo.processInfo.environment["PROTECT_AUTOSCAN"] != nil { model.scan() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if model.phase == .idle {
            VStack(spacing: 0) {
                hero.frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
                madeBy
            }
        } else {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Space.xl) {
                    compactHeader
                    if let r = model.result { summary(r); findings(r) }
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
                    Image(nsImage: logo)
                        .resizable().scaledToFit()
                        .frame(width: 220)
                        .opacity(Dim.strong)
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
    // Centred, symmetrical, and saying nothing the product page does not already
    // say — a scanner whose opening screen has learned nothing about your machine
    // has no reason to be an app. This one reads the installations before you
    // press anything, so the first thing on screen is your own Mac.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            HStack(alignment: .top, spacing: Space.huge) {
                pitch
                machine
            }
            checks
        }
        .padding(.vertical, Space.xl)
    }

    /// ⚠️ EVERY CLAIM HERE IS ONE THE ENGINE ACTUALLY MAKES. It is tempting to
    /// fill the bottom of a sparse screen with feature copy, and a security tool
    /// that overstates what it checks is worse than one that says nothing.
    /// These three are the rules in Scan.swift, in the user's words.
    private var checks: some View {
        // ⚠️ EQUAL HEIGHTS, and it takes both halves of this. maxHeight makes each
        // card fill whatever the row is; fixedSize makes the row exactly as tall
        // as its tallest card. With only the first, the row collapses; with only
        // the second, the cards keep their own ragged heights, which is what they
        // did — three panels of three different sizes.
        HStack(alignment: .top, spacing: Space.md) {
            check("key.horizontal.fill", "Keys in your chat history",
                  "Anthropic, OpenAI, GitHub, Google, Slack and GitLab keys, left behind in conversation logs.")
            check("lock.open.fill", "Files other accounts can open",
                  "The file and every folder above it. A loose file inside a locked-down folder is not a problem, and is not reported as one.")
            check("wifi.slash", "Nothing leaves this Mac",
                  "The scan is local, and anything it shows you has the secret itself blanked out first.")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func check(_ icon: String, _ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Image(systemName: icon)
                .font(.system(size: FontSize.lead))
                .foregroundStyle(Ink.accent)
            Text(title)
                .font(.system(size: FontSize.small, weight: .semibold))
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.system(size: FontSize.caption))
                .foregroundStyle(Ink.secondary(Dim.faint))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentSurface(radius: Radius.card)
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("TEMPLETON PROTECT")
                    .font(.system(size: FontSize.caption, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Ink.accent)
                Text("Scan your AI,\nthen scan your code.")
                    .font(.system(size: FontSize.display, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Credentials get pasted into chats and left in conversation logs. This finds them, and finds the files another account on this Mac can read.")
                    .font(.system(size: FontSize.body))
                    .foregroundStyle(Ink.secondary())
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420, alignment: .leading)
            }

            Button(action: model.scan) {
                HStack(spacing: Space.sm) {
                    Image(systemName: "shield.lefthalf.filled")
                    Text(model.phase == .scanning ? "Scanning" : "Scan this Mac")
                }
                .font(.system(size: FontSize.lead, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.navy)
                .padding(.horizontal, Space.xxl).padding(.vertical, Space.lg)
                .primaryAction()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)

            Text("Read-only. Nothing is changed unless you ask for it.")
                .font(.system(size: FontSize.caption))
                .foregroundStyle(Ink.secondary(Dim.faint))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var machine: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("ON THIS MAC")
                    .font(.system(size: FontSize.caption, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Ink.secondary(Dim.faint))
                Spacer()
                // ⚠️ A BARE COLUMN OF NUMBERS MEANS NOTHING. "2,289" next to
                // Claude Code could be days, sessions, megabytes. The column has
                // a name now, and the row below says what the scan will do with
                // them.
                Text("FILES TO CHECK")
                    .font(.system(size: FontSize.caption, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Ink.secondary(Dim.faint))
            }
            .padding(.horizontal, Space.lg).padding(.top, Space.lg)

            if model.installed.isEmpty {
                Text("Looking…")
                    .font(.system(size: FontSize.small)).foregroundStyle(Ink.secondary(Dim.faint))
                    .padding(.horizontal, Space.lg).padding(.bottom, Space.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.installed) { item in
                        HStack(spacing: Space.md) {
                            Circle().fill(Ink.accent).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.tool)
                                    .font(.system(size: FontSize.small, weight: .medium))
                                    .foregroundStyle(Ink.primary)
                                Text(item.dir)
                                    .font(.system(size: FontSize.caption, design: .monospaced))
                                    .foregroundStyle(Ink.secondary(Dim.faint))
                            }
                            Spacer(minLength: Space.lg)
                            // ⚠️ TABULAR DIGITS. Counts in a stacked column that
                            // do not share a digit width read as a ragged mess.
                            Text(item.atLeast ? "\(item.files)+" : "\(item.files)")
                                .font(.system(size: FontSize.caption, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(Ink.secondary())
                        }
                        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                        if item.id != model.installed.last?.id {
                            Rectangle().fill(Ink.panelEdge).frame(height: 1)
                                .padding(.leading, Space.lg + 6 + Space.md)
                        }
                    }
                }

                Text(installedFooter)
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(Ink.secondary(Dim.faint))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.sm).padding(.bottom, Space.lg)
            }
        }
        .frame(width: 320)
        .contentSurface(radius: Radius.panel)
    }

    private var installedFooter: String {
        let total = model.installed.reduce(0) { $0 + $1.files }
        let capped = model.installed.contains { $0.atLeast }
        return "About \(total.formatted())\(capped ? "+" : "") files in these folders. The scan reads the ones that can hold a key — logs, configs and transcripts — and skips the rest."
    }

    // ── header once scanning or done ──────────────────────────────────
    private var compactHeader: some View {
        HStack(spacing: Space.lg) {
            Button(action: model.scan) {
                Text(model.phase == .scanning ? "…" : "Re-scan")
                    .font(.system(size: FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                    .frame(width: 84, height: 84)
                    .glassCircle()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Templeton Protect")
                    .font(.system(size: FontSize.title, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                if model.phase == .scanning {
                    // ⚠️ THE WAIT IS REAL, SO IT IS SHOWN. Seventeen seconds of a
                    // still spinner reads as hung; the count says it is working.
                    Text("Reading configuration and conversation logs… \(model.elapsed)s")
                        .font(.system(size: FontSize.small)).foregroundStyle(Ink.secondary())
                } else if let r = model.result {
                    Text("Checked \(r.filesRead.formatted()) files across \(r.toolsFound.count) installations: \(r.toolsFound.joined(separator: ", "))")
                        .font(.system(size: FontSize.small)).foregroundStyle(Ink.secondary())
                }
            }
            Spacer()

            if model.result != nil {
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

    // ── findings ──────────────────────────────────────────────────────
    @ViewBuilder private func findings(_ r: ScanResult) -> some View {
        if r.findings.isEmpty {
            VStack(spacing: Space.md) {
                Text("Nothing to worry about")
                    .font(.system(size: FontSize.title, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                Text("No credentials are sitting in your AI conversation logs, and nothing another account could read.")
                    .font(.system(size: FontSize.small)).foregroundStyle(Ink.secondary())
                    .multilineTextAlignment(.center)
            }
            .padding(Space.xxl).frame(maxWidth: .infinity).contentSurface(radius: Radius.panel)
        } else {
            VStack(spacing: Space.md) {
                ForEach(r.findings, id: \.where_) { FindingCard(finding: $0, model: model) }
            }
        }
    }
}
