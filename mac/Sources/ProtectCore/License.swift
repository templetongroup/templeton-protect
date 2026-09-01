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

    /// When this copy was first opened. Written once and never rewritten.
    public static func firstRun(_ defaults: UserDefaults = .standard) -> Date {
        if let d = defaults.object(forKey: installedKey) as? Date { return d }
        let now = Date()
        defaults.set(now, forKey: installedKey)
        return now
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
