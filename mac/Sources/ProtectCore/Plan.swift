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
// ⚠️ THERE IS NO STORE YET, SO THE DEFAULT IS .plus. Shipping a lock with no
// door — features gated behind a purchase that cannot be made — would be
// theater. The gate exists now so the boundary is visible in the product and
// the codebase from day one; flipping the default to .free is the commercial
// launch decision, and it belongs to Tony together with the payment rails
// (licensing server or App Store), not to an agent.
public enum Plan: String {
    case free, plus

    public static var current: Plan {
        // A license file, when the store exists, will be validated here.
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Templeton Protect/license.json")
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let plan = obj["plan"] as? String, plan == "free" {
            return .free
        }
        return .plus
    }

    /// The resident layer is the paid layer.
    public var includesResident: Bool { self == .plus }
}
