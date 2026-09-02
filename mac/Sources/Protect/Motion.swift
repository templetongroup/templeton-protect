import SwiftUI

/*
 Motion that carries information.

 ⚠️ THE APP ALREADY HAD ENOUGH DECORATION. There is a breathing pulse on the
 scanning screen and a swirl on the idle one, and adding more of that kind would
 have said nothing about a security scanner. Everything in this file is tied to
 something the app is actually doing: findings arriving one at a time because
 that is how they are found, a tick drawing itself because a change just landed,
 a ring filling because the next press cannot be taken back.

 Every piece here checks `accessibilityReduceMotion` and resolves to its finished
 state when motion is turned off — never to a missing control.
 */

// ── findings arriving ────────────────────────────────────────────────────────

/// Rises into place a beat after the one above it.
///
/// ⚠️ THE TOTAL DELAY IS CAPPED. At 45ms a card, a forty-finding scan would
/// still be sliding cards in nearly two seconds after the results appeared, and
/// the bottom of the list reads as broken rather than choreographed.
struct Arrive: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                guard !reduceMotion else { shown = true; return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)
                    .delay(min(Double(index) * 0.045, 0.5))) { shown = true }
            }
    }
}

extension View {
    func arrives(at index: Int) -> some View { modifier(Arrive(index: index)) }
}

// ── a change that landed ─────────────────────────────────────────────────────

/// A ring and a tick that draw themselves once, when a fix comes back good.
///
/// Drawn rather than an SF Symbol with a symbol effect, because those need
/// macOS 14 and this ships to 12.
struct DrawnCheck: View {
    var size: CGFloat = 13
    var color: Color = Ink.good
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Tick()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .padding(size * 0.27)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !drawn else { return }
            guard !reduceMotion else { drawn = true; return }
            withAnimation(.easeOut(duration: 0.4)) { drawn = true }
        }
        .accessibilityHidden(true)
    }

    private struct Tick: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            return p
        }
    }
}

// ── the press that cannot be taken back ──────────────────────────────────────

/// Press and hold; a ring fills; let go early and nothing happens.
///
/// ⚠️ THIS IS FOR IRREVERSIBLE WORK ONLY. Protect deletes and rewrites files
/// outright rather than moving them to the Trash — a file full of leaked keys
/// sitting recoverable in the Trash is not a fix — so there is nothing to undo
/// afterwards and the whole of the safety has to live in the press.
///
/// ⚠️ IT FALLS BACK TO A PLAIN BUTTON when motion is reduced or VoiceOver is
/// running. A hold is a motor task, and the confirmation step before it is
/// already deliberate; the answer to somebody who cannot hold a button down is
/// a button, not a dead end.
struct HoldToConfirm: View {
    let label: String
    let holdingLabel: String
    var tint: Color = Ink.critical
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var fired = false

    private let duration: Double = 1.0

    var body: some View {
        if reduceMotion || NSWorkspace.shared.isVoiceOverEnabled {
            Button(action: action) { text(label) }
                .buttonStyle(.plain)
                .liquidGlass(cornerRadius: Radius.control, interactive: true)
        } else {
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(tint.opacity(0.22))
                        .frame(width: pressed ? geo.size.width : 0)
                        .animation(.linear(duration: pressed ? duration : 0.18), value: pressed)
                }
                text(pressed ? holdingLabel : label)
            }
            .fixedSize()
            .liquidGlass(cornerRadius: Radius.control, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            /*
             ⚠️ onLongPressGesture AND NOT A BUTTON. A Button fires on a click,
             so a stray click would still do the irreversible thing and the ring
             would be decoration over an unchanged risk. This way a quick click
             does nothing at all.
             */
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 12) {
                guard !fired else { return }
                fired = true
                action()
            } onPressingChanged: { down in
                pressed = down
                if !down { fired = false }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityHint("Press and hold to confirm. This cannot be undone.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .help("Press and hold — this cannot be undone.")
        }
    }

    private func text(_ s: String) -> some View {
        Text(s)
            .font(.system(size: FontSize.caption, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
    }
}
