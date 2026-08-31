import SwiftUI

// Liquid Glass, with an honest fallback.
//
// ⚠️ GATED, NOT ASSUMED. glassEffect ships in macOS 26; this Mac runs 26.5 so it
// gets the real material. Raising the whole package's deployment target instead
// would have been easier and would have dropped every Mac below 26 — so the
// effect is gated and older systems get .ultraThinMaterial, which is the closest
// thing that has always existed.
//
// ⚠️ GLASS NEEDS SOMETHING BEHIND IT. A translucent panel over a flat grey is
// just a grey panel; the material only reads as glass when there is colour and
// motion underneath for it to refract. That is what Aurora below is for, and it
// is the reason the first version looked flat however the panels were styled.

extension View {
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Palette.pearl.opacity(0.14)))
        }
    }

    /// ⚠️ NOTHING GOES *INSIDE* THE MATERIAL BUT TEXT. The first version filled a
    /// white circle behind the label and then applied glass on top — so the eye
    /// saw a flat disc with a blur around it. Glass has to be the only thing
    /// between the label and the background, or it is just a grey circle.
    /// The primary action. Solid, not glass.
    ///
    /// ⚠️ GLASS TINT DOES NOT SURVIVE THE WINDOW LOSING FOCUS. Tinted glass was
    /// tried here first and measured: focused it read champagne, unfocused the
    /// system dropped the tint and the app's only call to action rendered as a
    /// plain grey disc. A primary action cannot depend on the window being
    /// frontmost to be findable. Glass stays on the secondary controls, where
    /// going quiet when inactive is correct behaviour rather than a fault.
    func primaryAction() -> some View {
        self
            .background(Palette.champagne, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.pearl.opacity(0.55), lineWidth: 1))
            .shadow(color: Palette.champagne.opacity(0.30), radius: 30)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    @ViewBuilder
    func glassCircle(interactive: Bool = true, tinted: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if tinted {
                self.glassEffect(.regular.tint(Palette.champagne.opacity(0.85)).interactive(),
                                 in: .circle)
            } else {
                // ⚠️ THE OUTLINE IS NOT DECORATION. Glass goes flat when the
                // window is not frontmost, and an unlit disc with a word in it
                // does not read as a button. The border is what says "control"
                // in the state the material stops saying it.
                self.glassEffect(.regular.interactive(), in: .circle)
                    .overlay(Circle().strokeBorder(Palette.pearl.opacity(0.22), lineWidth: 1))
            }
        } else {
            self.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Palette.pearl.opacity(0.18)))
        }
    }
}

/// The light the glass refracts. Slow, wide, and never in front of anything.
struct Aurora: View {
    @State private var drift = false
    // ⚠️ REDUCE MOTION IS NOT OPTIONAL. A slow drifting background is exactly the
    // ambient animation that setting exists to stop, and the first version ran it
    // regardless. A still gradient is a perfectly good background.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // ⚠️ THE DECORATION IS AN OVERLAY, NOT A ZSTACK SIBLING, AND IT IS
        // CLIPPED. As a ZStack this view reported the size of its largest child —
        // a 1200pt capsule — so the window's ZStack grew to about 870pt against a
        // 720pt window and centred itself, pushing roughly 75pt off the top. The
        // headline sat under the traffic lights and three separate attempts at a
        // top inset all measured identically, because every one of them was
        // being applied above the visible edge of the window. An overlay does
        // not vote on its parent's size; the gradient alone decides it.
        LinearGradient(colors: [Palette.deep, Palette.mid],
                       startPoint: .top, endPoint: .bottom)
            .overlay {
                ZStack {

            // Two pools of brand colour, drifting slowly against each other.
            Circle()
                .fill(RadialGradient(colors: [Palette.champagne.opacity(0.20), .clear],
                                     center: .center, startRadius: 0, endRadius: 420))
                .frame(width: 840, height: 840)
                .offset(x: drift ? -170 : -260, y: drift ? -230 : -160)
                .blur(radius: 40)

            Circle()
                .fill(RadialGradient(colors: [Palette.navy.opacity(0.75), .clear],
                                     center: .center, startRadius: 0, endRadius: 400))
                .frame(width: 760, height: 760)
                .offset(x: drift ? 250 : 170, y: drift ? 210 : 280)
                .blur(radius: 44)

            Circle()
                .fill(RadialGradient(colors: [Palette.rose.opacity(0.16), .clear],
                                     center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 520, height: 520)
                .offset(x: drift ? 120 : 40, y: drift ? -260 : -190)
                .blur(radius: 50)

            // The mark itself, enormous and nearly gone, bleeding off the right
            // edge. It ties the window to the icon in the Dock and gives the
            // composition a weight on the side the text does not occupy.
            if let swirl = Bundle.main.image(forResource: "swirl") {
                Image(nsImage: swirl)
                    .resizable().renderingMode(.template)
                    .frame(width: 900, height: 900)
                    .foregroundStyle(Palette.pearl.opacity(0.035))
                    .offset(x: 380, y: 120)
            }

                }
                .allowsHitTesting(false)
            }
            .clipped()
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            // ⚠️ Slow enough to be atmosphere rather than animation. A background
            // that draws the eye is competing with the findings.
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
