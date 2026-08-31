import Foundation

// What to actually do about a finding.
//
// ⚠️ THIS REPLACED A LINE OF YELLOW TEXT THAT POINTED NOWHERE. Every finding
// used to end with "Next: How to rotate a leaked key properly" — the name of a
// folder under `skills/`, which is not bundled in the app, is not clickable, and
// when you do open it turns out to be an enterprise runbook about Active
// Directory and HashiCorp Vault. Tony, on seeing it in the shipped app: "they
// point nowhere and are meaningless."
//
// He was right twice over. A label that names a document nobody can open is
// worse than no label, because it looks like help. And the help it named was for
// a different reader entirely — somebody rotating service accounts across a
// domain, not somebody who has just been told an OpenAI key is sitting in a chat
// log on their laptop.
//
// So the steps live here, in the app, in the words of the person reading them,
// and the link is a real button that opens the page where the thing gets done.

public struct WebLink: Codable, Sendable {
    public let label: String
    public let url: String
    public init(label: String, url: String) { self.label = label; self.url = url }
}

public struct NextSteps: Codable, Sendable {
    /// What this gets you, said as a promise rather than a topic.
    public let title: String
    /// Short, ordered, and each one a thing a person does.
    public let steps: [String]
    /// Pages the steps refer to. Never invented — see the note on `rotateAt`.
    public let links: [WebLink]
    public init(title: String, steps: [String], links: [WebLink] = []) {
        self.title = title; self.steps = steps; self.links = links
    }
}

/**
 Where each vendor's keys are rotated.

 ⚠️ ROTATING IS THE FIX; TAKING THE KEY OUT OF THE FILE IS THE CLEAN-UP. Tony, on
 the remedy text: "i would offer the advice of rotating the key along with the
 delete from transcript button." Neither redacting nor deleting makes a leaked key
 safe — it sat in plain text and must be assumed copied. Naming the page turns
 "rotate your keys" from a lecture into something a person does in the next
 minute.

 ⚠️ ONLY VENDORS WHOSE PAGE IS KNOWN GET A LINK. A plausible-looking URL that
 404s is the same failure as the label that pointed nowhere, one step later.
 */
public let rotateAt: [String: String] = [
    "OpenAI": "https://platform.openai.com/api-keys",
    "Anthropic": "https://console.anthropic.com/settings/keys",
    "GitHub": "https://github.com/settings/tokens",
    "Google": "https://console.cloud.google.com/apis/credentials",
    "Slack": "https://api.slack.com/apps",
    "GitLab": "https://gitlab.com/-/user_settings/personal_access_tokens",
    "AWS": "https://console.aws.amazon.com/iam/home#/security_credentials",
    "Stripe": "https://dashboard.stripe.com/apikeys",
    "SendGrid": "https://app.sendgrid.com/settings/api_keys",
    "Twilio": "https://console.twilio.com/us1/account/keys-credentials/api-keys",
    "npm": "https://www.npmjs.com/settings/~/tokens",
]

/// One line naming the pages, for the remedy text and the exports — where a
/// button cannot go.
public func rotateAdvice(_ vendors: [String]) -> String {
    let known = vendors.filter { rotateAt[$0] != nil }.sorted()
    guard !known.isEmpty else { return "Rotate them wherever they were issued." }
    return "Rotate: " + known.map { vendor in
        // The page, without the scheme — it is being read, not clicked.
        let page = rotateAt[vendor]!.replacingOccurrences(of: "https://", with: "")
        return "\(vendor) at \(page)"
    }.joined(separator: "; ") + "."
}

/// The steps for a key that has been sitting somewhere in plain text.
public func rotationSteps(_ vendors: [String], found: String) -> NextSteps {
    let known = vendors.filter { rotateAt[$0] != nil }.sorted()
    var steps = [
        "Treat these keys as already known. They sat in plain text in \(found), so the only safe assumption is that they have been copied — by a backup, a sync client, a screen share, or another program on this Mac.",
        known.isEmpty
            ? "Issue a new key wherever this one was issued, and put the new one somewhere the file cannot reach — an environment variable or your password manager."
            : "Open the \(known.count == 1 ? "page" : "pages") below and issue a new key. Put the new one in an environment variable or your password manager, not back into a file.",
        "Delete the old key at the same time. A key that is replaced but not revoked is still a working key.",
        "Only then clean up the file. Removing the value here changes nothing about whether the old key works.",
    ]
    if !known.isEmpty {
        steps.append("If anything stopped working after the swap, it was using the old key — which is exactly what you needed to find out.")
    }
    return NextSteps(title: "Rotate these keys — that is the fix, and this is not",
                     steps: steps,
                     links: known.map { WebLink(label: "\($0) keys", url: rotateAt[$0]!) })
}

/**
 Replace every key-shaped value in a file, leaving the rest byte for byte.

 ⚠️ THE FIX FOR A KEY IN A TRANSCRIPT IS REMOVING THE KEY, NOT THE TRANSCRIPT.
 This app shipped signed and notarized offering "Delete this transcript" as the
 only option. Tony: "if it surfaces something like an openai key in a transcript,
 how can we delete the entire session from their folders? that would be
 incredibly destructive." He is right — somebody's conversation history is not
 ours to destroy to clean up one value in it. This is the Swift half of the
 change the TypeScript engine took on 2026-08-31; the two must not drift again.
 */
public func redactKeys(_ contents: String) -> (text: String, removed: Int) {
    var text = contents
    var removed = 0
    for (vendor, re) in keyShapesForRedaction {
        let ns = NSMutableString(string: text)
        var offset = 0
        let matches = re.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for m in matches {
            guard let r = Range(m.range, in: text) else { continue }
            var body = String(text[r])
            for prefix in keyPrefixes where body.hasPrefix(prefix) {
                body = String(body.dropFirst(prefix.count)); break
            }
            // ⚠️ A PLACEHOLDER IS NOT A KEY, and rewriting one would edit
            // somebody's documentation for no reason. Same exclusion the finder
            // uses, so the two never disagree about what is a key.
            if isPlaceholder(body) { continue }
            // Same length is not the goal; saying what happened is. Somebody
            // reading this transcript later should understand why it is gone.
            let replacement = "[\(vendor) key removed by Templeton Protect]"
            ns.replaceCharacters(in: NSRange(location: m.range.location + offset,
                                             length: m.range.length),
                                 with: replacement)
            offset += replacement.utf16.count - m.range.length
            removed += 1
        }
        text = ns as String
    }
    return (text, removed)
}

let keyPrefixes = ["sk-ant-", "sk-", "ghp_", "gho_", "ghu_", "ghs_", "ghr_",
                   "AIza", "glpat-", "AKIA", "ASIA", "sk_live_", "npm_"]
