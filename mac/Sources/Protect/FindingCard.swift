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
    // ⚠️ THE SAME AFFORDANCE AS PROTECT_AUTOSCAN, AND FOR THE SAME REASON. The
    // steps only exist once somebody clicks, and a screenshot cannot click. This
    // is how the expanded card gets verified against the running app rather than
    // against the source — which is the rule that caught every layout bug in
    // NOTES.md. PROTECT_EXPAND=1.
    // ⚠️ BOTH OF THEM, so a screenshot shows the two disclosures open together —
    // which is the arrangement the ordering bug only appeared in.
    @State private var showEvidence = ProcessInfo.processInfo.environment["PROTECT_EXPAND"] != nil
    @State private var showSteps = ProcessInfo.processInfo.environment["PROTECT_EXPAND"] != nil

    private var outcome: FixOutcome? { model.outcomes[finding.identity] }
    private var isArmed: Bool { model.armed.contains(finding.identity) }

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
                        // ⚠️ THIS IS A CONTROL, SO IT IS COLORED LIKE ONE. In
                        // faint grey it read as another line of metadata and
                        // nobody would know there was anything behind it.
                        Text((showEvidence ? "▾ " : "▸ ") + "What was found")
                            .font(.system(size: FontSize.caption, weight: .medium))
                            .foregroundStyle(Palette.rose)
                    }
                    .buttonStyle(.plain)

                    /*
                     ⚠️ A DISCLOSURE'S CONTENT GOES DIRECTLY UNDER ITS OWN
                     TOGGLE. This block used to sit at the bottom of the card,
                     below the next-steps section, so opening "What was found"
                     made text appear underneath a different heading entirely.
                     Tony: "when i click the What was found text, it opens below
                     the Yellow text. hard to follow." Two disclosures on one
                     card only work if each one grows in place.
                     */
                    if showEvidence {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(redact(finding.evidence))
                            Text(finding.verified ? "Confirmed by a direct check." : "Pattern match — not confirmed.")
                            Text("Check afterwards: \(finding.validation)")
                        }
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(Ink.secondary(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Space.sm)
                        .padding(.bottom, Space.xs)
                    }

                    /*
                     ⚠️ THE FIX BUTTON IS NOT THE FIX. Removing a key from a
                     transcript changes nothing about whether that key still
                     works; the step that matters happens on somebody else's
                     website.

                     ⚠️ AND IT HAS TO OPEN. This was a line of yellow text
                     reading "Next: How to rotate a leaked key properly" — the
                     title of a document that is not in the app, cannot be
                     clicked, and turned out to be an enterprise runbook about
                     Active Directory. Tony, looking at the shipped app: "they
                     point nowhere and are meaningless." A label that names help
                     nobody can reach is worse than no label, because it looks
                     like help. It expands now, and the page is a button.
                     */
                    if let g = finding.guidance {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { showSteps.toggle() }
                        } label: {
                            Text((showSteps ? "▾ " : "▸ ") + g.title)
                                .font(.system(size: FontSize.caption, weight: .medium))
                                .foregroundStyle(Ink.accent)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)

                        if showSteps {
                            VStack(alignment: .leading, spacing: Space.sm) {
                                ForEach(Array(g.steps.enumerated()), id: \.offset) { i, step in
                                    HStack(alignment: .top, spacing: Space.sm) {
                                        Text("\(i + 1)")
                                            .font(.system(size: FontSize.caption, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Ink.accent)
                                            .frame(width: 14, alignment: .trailing)
                                        Text(step)
                                            .font(.system(size: FontSize.caption))
                                            .foregroundStyle(Ink.secondary(Dim.strong))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    }
                                }
                                if !g.links.isEmpty {
                                    HStack(spacing: Space.sm) {
                                        ForEach(g.links, id: \.url) { link in
                                            Button {
                                                // ⚠️ NSWorkspace, not a SwiftUI Link — the
                                                // app is assembled by hand, and this is the
                                                // API that always hands off to the browser.
                                                if let url = URL(string: link.url) {
                                                    NSWorkspace.shared.open(url)
                                                }
                                            } label: {
                                                HStack(spacing: Space.xs) {
                                                    Image(systemName: "arrow.up.forward.square")
                                                    Text(link.label)
                                                }
                                                .font(.system(size: FontSize.caption, weight: .semibold, design: .rounded))
                                                .foregroundStyle(Ink.primary)
                                                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                                                .background(Capsule().strokeBorder(Ink.panelEdge, lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                            .help(link.url)
                                        }
                                    }
                                    .padding(.top, Space.xs)
                                }
                            }
                            .padding(.leading, Space.sm)
                            .padding(.top, Space.xs)
                        }
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
                        glassButton("Keep it") { model.armed.remove(finding.identity) }
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
                        if fix.destructive { model.armed.insert(finding.identity) } else { model.apply(finding) }
                    }
                }
            }
            .padding(.leading, Space.lg + Space.sm + Space.md).padding(.trailing, Space.lg).padding(.bottom, Space.lg)
        } else {
            // ⚠️ "NOTHING HERE CAN DO IT FOR YOU" WAS A DEAD END when the card
            // above it now carries the steps and the page. Say where to look.
            Text(finding.guidance == nil
                 ? "Only you can fix this one — nothing here can do it for you. \(finding.remedy)"
                 : "This one is yours to do — the steps are above.")
                .font(.system(size: FontSize.caption)).foregroundStyle(Ink.secondary(Dim.faint))
                .fixedSize(horizontal: false, vertical: true)
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
