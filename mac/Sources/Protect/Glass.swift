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
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.14)))
        }
    }

    /// ⚠️ NOTHING GOES *INSIDE* THE MATERIAL BUT TEXT. The first version filled a
    /// white circle behind the label and then applied glass on top — so the eye
    /// saw a flat disc with a blur around it. Glass has to be the only thing
    /// between the label and the background, or it is just a grey circle.
    @ViewBuilder
    func glassCircle(interactive: Bool = true, tinted: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if tinted {
                self.glassEffect(.regular.tint(Color(red: 0.05, green: 0.70, blue: 0.64).opacity(0.55)).interactive(),
                                 in: .circle)
            } else {
                self.glassEffect(.regular.interactive(), in: .circle)
            }
        } else {
            self.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18)))
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
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.07, blue: 0.10),
                                    Color(red: 0.05, green: 0.11, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)

            // Two pools of brand colour, drifting slowly against each other.
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.04, green: 0.63, blue: 0.57).opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: 420))
                .frame(width: 840, height: 840)
                .offset(x: drift ? -170 : -260, y: drift ? -230 : -160)
                .blur(radius: 40)

            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.10, green: 0.44, blue: 0.83).opacity(0.5), .clear],
                                     center: .center, startRadius: 0, endRadius: 400))
                .frame(width: 760, height: 760)
                .offset(x: drift ? 250 : 170, y: drift ? 210 : 280)
                .blur(radius: 44)

            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.43, green: 0.88, blue: 0.78).opacity(0.34), .clear],
                                     center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 520, height: 520)
                .offset(x: drift ? 120 : 40, y: drift ? -260 : -190)
                .blur(radius: 50)

            // ⚠️ SOMETHING WITH AN EDGE. A material that samples a smooth wash
            // has nothing to bend, so it reads as tinted plastic. These thin
            // arcs are what the glass actually refracts, and they are the
            // difference between the effect being visible and not.
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .stroke(Color.white.opacity(0.055), lineWidth: 1.4)
                    .frame(width: 900 + CGFloat(i) * 150, height: 420 + CGFloat(i) * 120)
                    .rotationEffect(.degrees(drift ? -18 + Double(i) * 7 : -30 + Double(i) * 7))
                    .offset(y: CGFloat(i) * 40 - 60)
                    .blur(radius: 0.4)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            // ⚠️ Slow enough to be atmosphere rather than animation. A background
            // that draws the eye is competing with the findings.
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
