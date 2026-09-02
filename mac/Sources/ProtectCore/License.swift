import CryptoKit
import Foundation

// Who has paid, and what happens when they have not.
//
// ⚠️ THE TRIAL IS GENEROUS AND THE LAPSE IS LOUD, because of what this product
// is. A subscription tool that quietly stops watching is worse than one that was
// never installed: the menu bar icon still sits there, so the person believes
// they are covered. When Protect+ lapses, keeping watch STOPS and says so in
// plain words — it never pretends.
//
// ⚠️ THE FREE SCANNER IS NEVER TOUCHED BY ANY OF THIS. Every rule, every fix,
// every export stays available forever, with or without a licence. What is sold
// is the app running on your behalf, and the day somebody stops paying they get
// back exactly the product they could have downloaded for nothing.

/**
 A licence key, checked against a signature this app cannot forge.

 ⚠️ THE OLD CHECK WAS "AT LEAST EIGHT CHARACTERS". Anyone could type `aaaaaaaa`
 into the licence sheet and hold Protect+ for good — and with the repository
 public, the code saying so was there to read. That is not weak enforcement, it
 is none.

 A key is now `TP1-<payload>.<signature>`, Ed25519 over the payload, verified
 against a public key baked into this bundle. Only the holder of the private
 half — in Tony's login keychain, never in this repository — can mint one. That
 stops the threats that actually happen: invented keys, a keygen, one key posted
 on a forum.

 ⚠️ IT DOES NOT STOP SOMEBODY RECOMPILING WITHOUT THE CHECK, and no client-side
 scheme can. That is a smaller group who must redo the work every release and
 give up notarised auto-updates, and it is a licence violation rather than a
 technical hole. Signing raises the floor; it does not build a ceiling.
 */
public enum LicenceKey {
    /// The public half of the signing key. Safe to publish — that is the point.
    /// Read from Info.plist so a rotation does not need a code change.
    static func publicKey(_ bundle: Bundle = .main) -> Curve25519.Signing.PublicKey? {
        guard let s = bundle.object(forInfoDictionaryKey: "TPLicenceKey") as? String,
              let raw = base64url(s),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return nil }
        return key
    }

    static func base64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    public struct Contents: Sendable {
        public let email: String
        public let expires: Date
    }

    /// What this key says, if and only if the signature holds.
    ///
    /// ⚠️ RETURNS NIL FOR ANYTHING IT CANNOT PROVE. A malformed key, a bad
    /// signature and an unreadable payload are the same answer on purpose —
    /// telling somebody *which* part of a forgery failed is a hint for the next
    /// attempt, and none of the three is a case an honest customer hits.
    public static func contents(of key: String,
                                publicKey override: Curve25519.Signing.PublicKey? = nil) -> Contents? {
        guard let pub = override ?? publicKey() else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("TP1-") else { return nil }
        let parts = trimmed.dropFirst(4).split(separator: ".")
        guard parts.count == 2,
              let body = base64url(String(parts[0])),
              let sig = base64url(String(parts[1])),
              pub.isValidSignature(sig, for: body),
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let email = obj["e"] as? String,
              let exp = obj["x"] as? Double
        else { return nil }
        return Contents(email: email, expires: Date(timeIntervalSince1970: exp))
    }
}

public struct License: Codable, Sendable {
    public let key: String
    public let email: String?
    /// When this was last confirmed with the store.
    public let checked: Date
    /// When the current paid period ends, if the store told us.
    public let expires: Date?

    public init(key: String, email: String?, checked: Date, expires: Date?) {
        self.key = key; self.email = email; self.checked = checked; self.expires = expires
    }
}

public enum Entitlement: Equatable, Sendable {
    case trial(daysLeft: Int)
    case subscribed
    /// Paid once, but the store has not been reachable for a long time.
    case unverified(daysLeft: Int)
    case lapsed
    case trialExpired

    public var allowsResident: Bool {
        switch self {
        case .trial, .subscribed, .unverified: return true
        case .lapsed, .trialExpired: return false
        }
    }

    /// One sentence, in the words somebody needs to hear.
    public var summary: String {
        switch self {
        case .subscribed: return "Protect+ is active."
        case .trial(let d):
            return d == 1 ? "Protect+ trial — 1 day left." : "Protect+ trial — \(d) days left."
        case .unverified(let d):
            return "Protect+ could not be confirmed with the store. Still watching for \(d) more day\(d == 1 ? "" : "s")."
        case .lapsed:
            return "Protect+ has lapsed. Keeping watch is off — scanning still works."
        case .trialExpired:
            return "Your Protect+ trial has ended. Keeping watch is off — scanning still works."
        }
    }
}

public enum Licensing {
    static let trialDays = 14
    /// ⚠️ A GRACE PERIOD, BECAUSE THE STORE WILL BE DOWN ONE DAY. Cutting
    /// somebody's protection off because a server was unreachable on a Tuesday
    /// is punishing a paying customer for our outage.
    static let graceDays = 14

    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Templeton Protect")
    }
    private static var licenseURL: URL { support.appendingPathComponent("license.json") }
    private static let installedKey = "firstRunDate"

    private static var stampURL: URL { support.appendingPathComponent(".first-run") }

    /**
     When this copy was first opened.

     ⚠️ RECORDED TWICE, AND THE EARLIEST WINS. It lived only in UserDefaults,
     which means `defaults delete ai.templetongroup.protect firstRunDate` bought
     another fourteen days — I reset my own trial with exactly that command while
     testing. Writing a second copy beside the licence file, and always believing
     whichever is older, means clearing one achieves nothing.

     ⚠️ THIS IS FRICTION, NOT ENFORCEMENT, and it is worth being honest about
     which. Somebody who deletes both is back to a fresh trial. The point is that
     it stops being a thing you do by accident or by following a one-line tip,
     which is where nearly all of it happens.
     */
    public static func firstRun(_ defaults: UserDefaults = .standard) -> Date {
        var found: [Date] = []
        if let d = defaults.object(forKey: installedKey) as? Date { found.append(d) }
        if let data = try? Data(contentsOf: stampURL),
           let t = TimeInterval(String(decoding: data, as: UTF8.self)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)) {
            found.append(Date(timeIntervalSince1970: t))
        }
        let start = found.min() ?? Date()
        // Re-write both, so a cleared copy is restored from the survivor.
        defaults.set(start, forKey: installedKey)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? Data(String(start.timeIntervalSince1970).utf8).write(to: stampURL, options: .atomic)
        return start
    }

    public static func saved() -> License? {
        guard let data = try? Data(contentsOf: licenseURL) else { return nil }
        return try? JSONDecoder().decode(License.self, from: data)
    }

    public static func save(_ license: License) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(license).write(to: licenseURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: licenseURL.path)
    }

    public static func forget() throws {
        try? FileManager.default.removeItem(at: licenseURL)
    }

    /// What this copy is entitled to right now.
    public static func entitlement(now: Date = Date(),
                                   defaults: UserDefaults = .standard) -> Entitlement {
        if let license = saved() {
            /*
             ⚠️ THE STORED FILE IS RE-VERIFIED, NOT TRUSTED. It sits in
             Application Support where anyone can edit it, so a saved licence
             proves nothing on its own — without this, forging entitlement is
             editing a JSON file rather than typing a fake key, which is easier
             than the hole that was just closed.

             When no public key is available (a unit test, an unbundled build)
             the signature cannot be checked, and the file's own dates are used.
             That is deliberate: the app always has the key, so the fallback only
             ever applies where there is nothing to protect.
             */
            if LicenceKey.publicKey() != nil {
                guard let contents = LicenceKey.contents(of: license.key) else { return .lapsed }
                if contents.expires < now { return .lapsed }
                return .subscribed
            }
            // A paid period the store gave us an end date for.
            if let expires = license.expires, expires < now { return .lapsed }
            let sinceCheck = now.timeIntervalSince(license.checked) / 86_400
            if sinceCheck > Double(graceDays) { return .lapsed }
            if sinceCheck > 3 {
                return .unverified(daysLeft: max(0, graceDays - Int(sinceCheck)))
            }
            return .subscribed
        }
        let used = now.timeIntervalSince(firstRun(defaults)) / 86_400
        let left = trialDays - Int(used)
        return left > 0 ? .trial(daysLeft: left) : .trialExpired
    }
}
