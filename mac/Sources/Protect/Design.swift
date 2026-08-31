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

enum Ink {
    static let primary = Color.white
    static func secondary(_ o: Double = Dim.muted) -> Color { .white.opacity(o) }
    static let critical = Color(red: 1.00, green: 0.45, blue: 0.40)
    static let high = Color(red: 1.00, green: 0.72, blue: 0.38)
    static let good = Color(red: 0.42, green: 0.85, blue: 0.62)
    static let accent = Color(red: 0.43, green: 0.88, blue: 0.80)
    /// The panel behind content. Lighter reads as closer — that is the depth
    /// cue here, not a heavier shadow.
    static let panel = Color.white.opacity(0.06)
    static let panelEdge = Color.white.opacity(0.10)
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
