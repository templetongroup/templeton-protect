import Foundation

// The commercial split, stated in code so it cannot drift by accident.
//
// Decision (Tony, 2026-09-01): the scanning engine is open source; the resident
// layer — the menu bar presence, scheduled scans, the transcript watcher — is
// the subscription, "Protect+". That is the honest version of open-core this
// project already chose in docs/PRODUCT.md: nothing is withheld from the free
// scanner to force an upgrade; the paid thing is genuinely a different thing —
// it *runs on your behalf* instead of when you press the button.
//
// ⚠️ THE GATE IS REAL NOW. It used to default to `.plus` for everybody, because
// there was no store and shipping a lock with no door is theatre. There is a
// door: a 14-day trial, a licence key from the store, a grace period for when
// the store is unreachable, and a lapse that switches keeping watch off and says
// so. See License.swift.

public enum Plan: String {
    case free, plus

    public static var current: Plan {
        Licensing.entitlement().allowsResident ? .plus : .free
    }

    /// The resident layer is the paid layer.
    public var includesResident: Bool { self == .plus }
}

/// Where somebody goes to buy, and to manage what they bought.
///
/// ⚠️ THE CHECKOUT LINK IS THE ONE PIECE AN AGENT CANNOT CREATE. It comes from
/// the store account — Paddle or Lemon Squeezy, chosen 2026-09-01 for merchant-
/// of-record tax handling — and until that account exists this points at the
/// product page, which is honest: it tells somebody what Protect+ is and does
/// not pretend to take their money.
public enum Store {
    public static let productPage = "https://www.templetongroup.dev/showcase/protect/"
    /// Replace with the store's hosted checkout when the account exists (TG-300).
    public static let checkout = productPage
    public static let manage = productPage
    public static let support = "mailto:hello@templetontech.com?subject=Templeton%20Protect"
}
