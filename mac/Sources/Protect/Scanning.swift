import SwiftUI
import ProtectCore

/// What the scan is doing, while it does it.
///
/// ⚠️ THIS REPLACED A SPINNER AND A SECOND COUNT, and the difference is not
/// decoration. A scan of a working machine reads about 8,000 files and takes
/// half a minute; a still spinner for that long reads as hung, and "17s" tells
/// you nothing about whether it is doing the thing you asked for. Naming the
/// file it is on right now — on your Mac, in a folder you recognise — is the
/// whole reassurance.
///
/// The shape follows CleanMyMac's: the stage being worked on expands and carries
/// the live detail; the stages already done collapse to a tile holding their
/// result; the ones still queued sit quiet. The layout moving is the progress
/// indicator.

/// One installation's place in the run.
struct Stage: Identifiable {
    enum State { case waiting, running, done(Int) }
    let tool: String
    let dir: String
    var state: State
    var id: String { dir }
}

struct ScanningView: View {
    @ObservedObject var model: Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            header
            active
            queue
            stopButton
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("SCANNING")
                .font(.system(size: FontSize.caption, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Ink.accent)
            Text(model.stageHeadline)
                .font(.system(size: FontSize.title, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .contentTransitionIfAvailable()
        }
    }

    // ── the stage being worked on ─────────────────────────────────────────
    private var active: some View {
        VStack(spacing: Space.lg) {
            Pulse(active: !reduceMotion)
                .frame(width: 132, height: 132)

            VStack(spacing: Space.xs) {
                // ⚠️ THE FILE NAME IS THE HEADLINE, THE FOLDER IS THE FOOTNOTE.
                // A full path in a single line of mono at this width truncates in
                // the middle and the eye cannot follow it changing many times a
                // second. The name changes; the folder underneath is stable
                // enough to read.
                Text(model.currentFile)
                    .font(.system(size: FontSize.small, design: .monospaced))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1).truncationMode(.middle)
                Text(model.currentFolder)
                    .font(.system(size: FontSize.caption, design: .monospaced))
                    .foregroundStyle(Ink.secondary(Dim.faint))
                    .lineLimit(1).truncationMode(.head)
            }
            .frame(maxWidth: 520)
            .frame(height: 40)

            HStack(spacing: Space.xxl) {
                counter("\(model.filesRead.formatted())", "files read")
                counter("\(model.foundSoFar)", "found so far",
                        tint: model.foundSoFar > 0 ? Ink.critical : Ink.primary)
                counter("\(model.elapsed)s", "elapsed")
            }
        }
        .padding(.vertical, Space.xxl)
        .frame(maxWidth: .infinity)
        .contentSurface(radius: Radius.panel)
    }

    private func counter(_ value: String, _ caption: String, tint: Color = Ink.primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: FontSize.title, weight: .semibold, design: .rounded))
                .foregroundStyle(tint).monospacedDigit()
            Text(caption.uppercased())
                .font(.system(size: FontSize.caption, weight: .medium)).tracking(0.6)
                .foregroundStyle(Ink.secondary(Dim.faint))
        }
    }

    // ── everything else, done or waiting ──────────────────────────────────
    private var queue: some View {
        HStack(spacing: Space.md) {
            ForEach(model.stages) { stage in
                stageTile(stage)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func stageTile(_ stage: Stage) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                switch stage.state {
                case .waiting:
                    Circle().strokeBorder(Ink.secondary(Dim.faint), lineWidth: 1)
                        .frame(width: 10, height: 10)
                case .running:
                    Circle().fill(Ink.accent).frame(width: 10, height: 10)
                case .done(let n):
                    Image(systemName: n > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(n > 0 ? Ink.critical : Ink.good)
                }
                Text(stage.tool)
                    .font(.system(size: FontSize.small, weight: .medium))
                    .foregroundStyle(isPending(stage) ? Ink.secondary(Dim.faint) : Ink.primary)
                Spacer(minLength: 0)
            }
            Text(caption(for: stage))
                .font(.system(size: FontSize.caption))
                .foregroundStyle(Ink.secondary(Dim.faint))
                .lineLimit(1)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentSurface(radius: Radius.card)
        .opacity(isPending(stage) ? 0.55 : 1)
    }

    private func isPending(_ stage: Stage) -> Bool {
        if case .waiting = stage.state { return true }
        return false
    }

    private func caption(for stage: Stage) -> String {
        switch stage.state {
        case .waiting: return "waiting"
        case .running: return "reading…"
        case .done(let n):
            if n == 0 { return "nothing found" }
            return n == 1 ? "1 to look at" : "\(n) to look at"
        }
    }

    // ⚠️ A LONG JOB NEEDS A WAY OUT. Half a minute of reading someone's home
    // folder with no way to stop it is not something to ship in a security tool.
    private var stopButton: some View {
        Button(action: model.cancel) {
            Text("Stop")
                .font(.system(size: FontSize.small, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .padding(.horizontal, Space.xl).padding(.vertical, Space.md)
                .background(Capsule().strokeBorder(Ink.panelEdge, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .frame(maxWidth: .infinity)
    }
}

/// The mark, breathing. Three rings on slightly different periods so the motion
/// never settles into an obvious loop.
private struct Pulse: View {
    let active: Bool
    @State private var phase = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(Ink.accent.opacity(0.35 - Double(i) * 0.09),
                                  lineWidth: 1.5)
                    .scaleEffect(phase ? 1.0 : 0.55 + Double(i) * 0.12)
                    .opacity(phase ? 0 : 1)
                    .animation(active
                               ? .easeOut(duration: 2.2).repeatForever(autoreverses: false)
                                   .delay(Double(i) * 0.62)
                               : nil,
                               value: phase)
            }
            if let swirl = Bundle.main.image(forResource: "swirl") {
                Image(nsImage: swirl)
                    .resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Ink.accent)
                    .rotationEffect(.degrees(phase ? 360 : 0))
                    .animation(active ? .linear(duration: 9).repeatForever(autoreverses: false) : nil,
                               value: phase)
            }
        }
        .onAppear { phase = true }
    }
}

extension View {
    /// contentTransition needs macOS 13; the app still runs on 12.
    @ViewBuilder func contentTransitionIfAvailable() -> some View {
        if #available(macOS 13.0, *) { self.contentTransition(.opacity) } else { self }
    }
}
