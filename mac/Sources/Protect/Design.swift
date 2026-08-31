import SwiftUI

// The scales. Decide once, reuse everywhere.
//
// ⚠️ THE FIRST VERSION PICKED VALUES AD HOC — 13.5pt here, 11.5pt there, padding
// of 18 next to 15 next to 9 — and that is the single biggest cause of a UI
// looking amateur. Not one of those numbers was chosen for a reason; each was
// nudged until it looked passable on its own. Refactoring UI's fix is a
// constrained scale where no two adjacent values sit closer than about 25%, so
// the choice between them is obvious instead of arbitrary.

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let huge: CGFloat = 48
    static let giant: CGFloat = 64
}

enum FontSize {
    static let caption: CGFloat = 12
    static let small: CGFloat = 14
    static let body: CGFloat = 16
    static let lead: CGFloat = 18
    static let title: CGFloat = 24
    static let display: CGFloat = 36
}

/// ⚠️ FIXED OPACITIES TOO. Eyeballing a slider for every muted label is the same
/// mistake in a different property.
enum Dim {
    static let faint: Double = 0.4
    static let muted: Double = 0.6
    static let strong: Double = 0.8
}

/// The palette. Four colors, chosen by Tony, and nothing outside them.
///
///     Midnight Navy  #192A56   the ground
///     Champagne      #F7D794   the one accent
///     Dusty Rose     #EDA6A3   trouble
///     Pearl White    #FCFBFB   the ink
///
/// ⚠️ SEVERITY IS NOT CARRIED BY COLOR ALONE. Rose and champagne are close in
/// warmth and a red/green viewer separates them poorly, so every finding also
/// states its severity in words and carries its own icon. The color is the
/// second signal, never the only one.
enum Palette {
    static let navy = Color(red: 0.098, green: 0.165, blue: 0.337)      // #192A56
    static let champagne = Color(red: 0.969, green: 0.843, blue: 0.580) // #F7D794
    static let rose = Color(red: 0.929, green: 0.651, blue: 0.639)      // #EDA6A3
    static let pearl = Color(red: 0.988, green: 0.984, blue: 0.984)     // #FCFBFB

    /// Two steps below the navy, for the ground the panels sit on. Derived from
    /// the navy rather than picked, so the family stays one family.
    static let deep = Color(red: 0.043, green: 0.075, blue: 0.161)
    static let mid = Color(red: 0.067, green: 0.114, blue: 0.235)
}

enum Ink {
    static let primary = Palette.pearl
    static func secondary(_ o: Double = Dim.muted) -> Color { Palette.pearl.opacity(o) }
    static let critical = Palette.rose
    static let high = Palette.champagne
    /// Nothing wrong. Navy lifted toward pearl — calm, and clearly not a warning.
    static let good = Color(red: 0.749, green: 0.816, blue: 0.910)
    static let accent = Palette.champagne
    /// The panel behind content. Lighter reads as closer — that is the depth
    /// cue here, not a heavier shadow.
    static let panel = Palette.pearl.opacity(0.06)
    static let panelEdge = Palette.pearl.opacity(0.10)
}

/// ⚠️ THE WINDOW IS fullSizeContentView, SO CONTENT STARTS AT y=0 — underneath
/// the traffic lights. Without this inset the headline ran straight into the
/// close button and the eyebrow above it was clipped off the top of the window
/// entirely. Every screen reserves the same strip.
enum Chrome {
    static let titleBar: CGFloat = 52
}

enum Radius {
    static let control: CGFloat = 12
    static let card: CGFloat = 16
    static let panel: CGFloat = 24
}

/// A content surface.
///
/// ⚠️ NOT GLASS, AND THAT IS THE RULE RATHER THAN A PREFERENCE. Apple's macOS
/// guidance puts Liquid Glass on the navigation and controls layer — toolbars,
/// sidebars, bars — and explicitly not on the content layer, nor stacked glass
/// on glass. Every finding card and summary tile in the first version was glass
/// sitting on a glass-ish background, which is exactly the pattern named as
/// wrong. Content gets a quiet panel; the controls keep the glass.
struct ContentSurface: ViewModifier {
    var radius: CGFloat = Radius.card
    func body(content: Content) -> some View {
        content
            .background(Ink.panel, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Ink.panelEdge, lineWidth: 1)
            )
            // Two-part shadow: a wide cast shadow for distance from the page,
            // and a tight one so the edge does not float.
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }
}

extension View {
    func contentSurface(radius: CGFloat = Radius.card) -> some View {
        modifier(ContentSurface(radius: radius))
    }
}
