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
    @StateObject private var model = Model()

    var body: some View {
        ZStack {
            Aurora()
            ScrollView { content.padding(.horizontal, 34).padding(.bottom, 44) }
        }
        .frame(minWidth: 780, minHeight: 580)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if model.phase == .idle {
            VStack(spacing: 0) { Spacer(minLength: 60); hero; Spacer(minLength: 60) }
                .frame(maxWidth: .infinity, minHeight: 620)
        } else {
            VStack(alignment: .leading, spacing: 22) {
                compactHeader
                if let r = model.result { summary(r); findings(r) }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, 34)
        }
    }

    // ── idle ──────────────────────────────────────────────────────────
    private var hero: some View {
        VStack(spacing: 26) {
            VStack(spacing: 7) {
                Text("Templeton Protect")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("Scan your AI, then scan your code.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Button(action: model.scan) {
                Text(model.phase == .scanning ? "Scanning" : "Scan")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 208, height: 208)
                    .glassCircle(tinted: true)
            }
            .buttonStyle(.plain)

            Text("Checks the AI assistants installed on this Mac for credentials left in conversation logs, and for files other accounts can read. Nothing is changed unless you ask.")
                .font(.system(size: 13.5))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
        }
    }

    // ── header once scanning or done ──────────────────────────────────
    private var compactHeader: some View {
        HStack(spacing: 16) {
            Button(action: model.scan) {
                Text(model.phase == .scanning ? "…" : "Re-scan")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .glassCircle()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("Templeton Protect")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                if model.phase == .scanning {
                    // ⚠️ THE WAIT IS REAL, SO IT IS SHOWN. Seventeen seconds of a
                    // still spinner reads as hung; the count says it is working.
                    Text("Reading configuration and conversation logs… \(model.elapsed)s")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                } else if let r = model.result {
                    Text("Checked \(r.filesRead.formatted()) files across \(r.toolsFound.count) installations: \(r.toolsFound.joined(separator: ", "))")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
        }
    }

    // ── summary ───────────────────────────────────────────────────────
    private func summary(_ r: ScanResult) -> some View {
        HStack(spacing: 12) {
            tile("\(r.findings.filter { $0.severity == .critical }.count)", "Critical", Color(red: 1, green: 0.45, blue: 0.40))
            tile("\(r.findings.filter { $0.severity == .high }.count)", "Worth fixing", Color(red: 1, green: 0.72, blue: 0.38))
            tile("\(r.findings.filter { $0.severity == .low || $0.severity == .medium }.count)", "Minor", .white.opacity(0.65))
        }
    }

    private func tile(_ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(tint).monospacedDigit()
            Text(caption.uppercased()).font(.system(size: 10.5, weight: .medium))
                .tracking(0.7).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 20)
    }

    // ── findings ──────────────────────────────────────────────────────
    @ViewBuilder private func findings(_ r: ScanResult) -> some View {
        if r.findings.isEmpty {
            VStack(spacing: 10) {
                Text("Nothing to worry about")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("No credentials are sitting in your AI conversation logs, and nothing another account could read.")
                    .font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(38).frame(maxWidth: .infinity).liquidGlass()
        } else {
            VStack(spacing: 12) {
                ForEach(r.findings, id: \.where_) { FindingCard(finding: $0, model: model) }
            }
        }
    }
}
