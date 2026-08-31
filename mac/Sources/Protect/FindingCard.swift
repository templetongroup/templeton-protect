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
        case .critical: return Ink.critical
        case .high: return Ink.high
        default: return Ink.secondary(Dim.faint)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.md) {
                Circle().fill(tint).frame(width: Space.sm, height: Space.sm).padding(.top, Space.xs + 2)
                    .shadow(color: tint.opacity(0.7), radius: 5)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(finding.title)
                        .font(.system(size: FontSize.body, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.plain)
                        .font(.system(size: FontSize.small))
                        .foregroundStyle(Ink.secondary())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.where_)
                        .font(.system(size: FontSize.caption, design: .monospaced))
                        .foregroundStyle(Ink.secondary(Dim.faint))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showEvidence.toggle() }
                    } label: {
                        // ⚠️ THIS IS A CONTROL, SO IT IS COLOURED LIKE ONE. In
                        // faint grey it read as another line of metadata and
                        // nobody would know there was anything behind it.
                        Text((showEvidence ? "▾ " : "▸ ") + "What was found")
                            .font(.system(size: FontSize.caption, weight: .medium))
                            .foregroundStyle(Palette.rose)
                    }
                    .buttonStyle(.plain)

                    // ⚠️ THE PLAYBOOK IS NOT THE FIX BUTTON. Deleting a
                    // transcript removes the file; it does not tell anybody how
                    // to rotate the key properly or stop it recurring.
                    if let g = finding.guidance {
                        Text("Next: \(g.title)")
                            .font(.system(size: FontSize.caption))
                            .foregroundStyle(Ink.accent.opacity(Dim.strong))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if showEvidence {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(redact(finding.evidence))
                            Text(finding.verified ? "Confirmed by a direct check." : "Pattern match — not confirmed.")
                            Text("Check afterwards: \(finding.validation)")
                        }
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(Ink.secondary(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.lg)

            footer
        }
        .contentSurface(radius: Radius.card)
    }

    @ViewBuilder private var footer: some View {
        if let outcome {
            HStack(spacing: Space.sm) {
                Image(systemName: outcome.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(outcome.message).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: FontSize.caption, weight: .medium))
            .foregroundStyle(outcome.ok ? Ink.good : tint)
            .padding(.leading, Space.lg + Space.sm + Space.md).padding(.trailing, Space.lg).padding(.bottom, Space.lg)
        } else if let fix = finding.fix {
            VStack(alignment: .leading, spacing: Space.sm) {
                // ⚠️ A DESTRUCTIVE FIX ASKS IN PLACE. A sheet is something people
                // dismiss; a step that appears where the eye already is, is not.
                if isArmed {
                    Text(fix.describes)
                        .font(.system(size: FontSize.caption)).foregroundStyle(Ink.secondary(Dim.strong))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.sm) {
                        glassButton("Yes, delete it", tint: tint) { model.apply(finding) }
                        glassButton("Keep it") { model.armed.remove(finding.where_) }
                    }
                } else {
                    // ⚠️ STACKED, NOT SIDE BY SIDE. A small button next to four
                    // wrapped lines of explanation gets centred against them, so
                    // it floated in the middle of a paragraph and the card looked
                    // broken. What the button does is read before it is pressed,
                    // so the sentence goes above it.
                    Text(fix.describes)
                        .font(.system(size: FontSize.caption)).foregroundStyle(Ink.secondary(Dim.faint))
                        .fixedSize(horizontal: false, vertical: true)
                    glassButton(fix.label, tint: fix.destructive ? tint : nil) {
                        if fix.destructive { model.armed.insert(finding.where_) } else { model.apply(finding) }
                    }
                }
            }
            .padding(.leading, Space.lg + Space.sm + Space.md).padding(.trailing, Space.lg).padding(.bottom, Space.lg)
        } else {
            Text("Only you can fix this one — nothing here can do it for you.")
                .font(.system(size: FontSize.caption)).foregroundStyle(Ink.secondary(Dim.faint))
                .padding(.leading, Space.lg + Space.sm + Space.md).padding(.trailing, Space.lg).padding(.bottom, Space.lg)
        }
    }

    @ViewBuilder
    private func glassButton(_ label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? .white)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: Radius.control, interactive: true)
    }
}
