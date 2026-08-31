import SwiftUI
import ProtectCore

// One finding, and what to do about it.
//
// ⚠️ THE PLAIN SENTENCE IS THE HEADLINE, NOT THE EVIDENCE. "file 644, directories
// 755 → 755" is what was measured and belongs behind a disclosure; whether the
// reader should care is the sentence above it.

struct FindingCard: View {
    let finding: Finding
    @ObservedObject var model: Model
    @State private var showEvidence = false

    private var outcome: FixOutcome? { model.outcomes[finding.where_] }
    private var isArmed: Bool { model.armed.contains(finding.where_) }

    private var tint: Color {
        switch finding.severity {
        case .critical: return Color(red: 1, green: 0.45, blue: 0.40)
        case .high: return Color(red: 1, green: 0.72, blue: 0.38)
        default: return .white.opacity(0.45)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                Circle().fill(tint).frame(width: 8, height: 8).padding(.top, 7)
                    .shadow(color: tint.opacity(0.7), radius: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(finding.title)
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.plain)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.where_)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showEvidence.toggle() }
                    } label: {
                        Text((showEvidence ? "▾ " : "▸ ") + "What was found")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)

                    // ⚠️ THE PLAYBOOK IS NOT THE FIX BUTTON. Deleting a
                    // transcript removes the file; it does not tell anybody how
                    // to rotate the key properly or stop it recurring.
                    if let g = finding.guidance {
                        Text("Next: \(g.title)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.43, green: 0.88, blue: 0.80).opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if showEvidence {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(redact(finding.evidence))
                            Text(finding.verified ? "Confirmed by a direct check." : "Pattern match — not confirmed.")
                            Text("Check afterwards: \(finding.validation)")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)

            footer
        }
        .liquidGlass(cornerRadius: 22)
    }

    @ViewBuilder private var footer: some View {
        if let outcome {
            HStack(spacing: 7) {
                Image(systemName: outcome.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(outcome.message).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(outcome.ok ? Color(red: 0.42, green: 0.85, blue: 0.62) : tint)
            .padding(.horizontal, 18).padding(.bottom, 16)
        } else if let fix = finding.fix {
            VStack(alignment: .leading, spacing: 9) {
                // ⚠️ A DESTRUCTIVE FIX ASKS IN PLACE. A sheet is something people
                // dismiss; a step that appears where the eye already is, is not.
                if isArmed {
                    Text(fix.describes)
                        .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        glassButton("Yes, delete it", tint: tint) { model.apply(finding) }
                        glassButton("Keep it") { model.armed.remove(finding.where_) }
                    }
                } else {
                    HStack(spacing: 10) {
                        glassButton(fix.label, tint: fix.destructive ? tint : nil) {
                            if fix.destructive { model.armed.insert(finding.where_) } else { model.apply(finding) }
                        }
                        Text(fix.describes)
                            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 16)
        } else {
            Text("Only you can fix this one — nothing here can do it for you.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 18).padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func glassButton(_ label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? .white)
                .padding(.horizontal, 15).padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 11, interactive: true)
    }
}
