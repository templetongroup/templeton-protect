import AppKit
import Sparkle

// Keeping the app current.
//
// ⚠️ THIS IS THE FIRST THING THIS APP HAS EVER SENT OVER THE NETWORK. Until
// now the product's claim — "all of it happens on this Mac" — was
// unconditionally true: there was no network client in the binary at all. An
// updater changes that, and for a security tool the honest move is to make the
// exception small, legible and refusable rather than to quietly start talking.
//
// What goes out: an HTTPS GET for the appcast, carrying nothing but the version
// this copy is running. What does not: `SUEnableSystemProfiling` is explicitly
// false, so Sparkle sends no hardware or OS profile. Nothing scanned, nothing
// found, and no identifier for this machine ever leaves.
//
// ⚠️ SPARKLE, NOT A HAND-ROLLED UPDATER. The one component that downloads a
// binary and replaces the running app is the last place to invent something.
// Sparkle verifies an EdDSA signature over the archive against a public key
// baked into this bundle, and checks the Developer ID matches before it swaps
// anything — so a compromised web host still cannot ship anybody a payload.
//
// ⚠️ AND IT ASKS BEFORE IT AUTOMATES. `SUEnableAutomaticChecks` is deliberately
// absent from Info.plist, which makes Sparkle put the question to the user on
// second launch instead of deciding for them. A tool that argues for consent
// over standing permissions does not get to switch on its own phone-home.

@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    var updater: SPUUpdater { controller.updater }

    /// The menu item, for the app menu and the menu bar alike.
    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    /// Shown next to the control, so "when did this last look?" is answerable.
    var lastCheckDescription: String {
        guard let date = updater.lastUpdateCheckDate else { return "Not checked yet" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return "Checked \(fmt.localizedString(for: date, relativeTo: Date()))"
    }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// The version a person can quote in a support message.
    static var currentVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}
