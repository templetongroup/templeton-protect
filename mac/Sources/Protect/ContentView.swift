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
    private var timer: Timer?

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

    func apply(_ finding: Finding) {
        guard let fix = finding.fix else { return }
        Task.detached(priority: .userInitiated) {
            let outcome = applyFix(fix)
            await MainActor.run { self.outcomes[finding.where_] = outcome }
        }
    }
}

struct ContentView: View {
    // ⚠️ ONE MODEL, OWNED BY THE DELEGATE. The menu item and the button must
    // drive the same scan; a @StateObject here would give the menu its own.
    @ObservedObject var model: Model

    var body: some View {
        ZStack {
            Aurora()
            ScrollView { content.padding(.horizontal, Space.xxl).padding(.bottom, Space.huge) }
        }
        .frame(minWidth: 780, minHeight: 580)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if model.phase == .idle {
            VStack(spacing: 0) { Spacer(minLength: 60); hero; Spacer(minLength: 60) }
                .frame(maxWidth: .infinity, minHeight: 620)
        } else {
            VStack(alignment: .leading, spacing: Space.xl) {
                compactHeader
                if let r = model.result { summary(r); findings(r) }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, Space.xxl)
        }
    }

    // ── idle ──────────────────────────────────────────────────────────
    private var hero: some View {
        VStack(spacing: Space.xl) {
            VStack(spacing: Space.sm) {
                Text("Templeton Protect")
                    .font(.system(size: FontSize.display, weight: .semibold, design: .rounded))
                Text("Scan your AI, then scan your code.")
                    .font(.system(size: FontSize.body))
                    .foregroundStyle(Ink.secondary())
            }

            Button(action: model.scan) {
                Text(model.phase == .scanning ? "Scanning" : "Scan")
                    .font(.system(size: FontSize.title, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 208, height: 208)
                    .glassCircle(tinted: true)
            }
            .buttonStyle(.plain)

            Text("Checks the AI assistants installed on this Mac for credentials left in conversation logs, and for files other accounts can read. Nothing is changed unless you ask.")
                .font(.system(size: FontSize.small))
                .foregroundStyle(Ink.secondary(Dim.faint))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 384)
        }
    }

    // ── header once scanning or done ──────────────────────────────────
    private var compactHeader: some View {
        HStack(spacing: Space.lg) {
            Button(action: model.scan) {
                Text(model.phase == .scanning ? "…" : "Re-scan")
                    .font(.system(size: FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .glassCircle()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Templeton Protect")
                    .font(.system(size: FontSize.title, weight: .semibold, design: .rounded))
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
