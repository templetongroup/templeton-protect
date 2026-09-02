#!/usr/bin/env swift

import CryptoKit
import Foundation
import Security

// Issues and checks Protect+ licences.
//
// ⚠️ THE PRIVATE KEY LIVES IN THE LOGIN KEYCHAIN AND NOWHERE ELSE. Not in this
// repository, which is public; not in an environment variable; not printed.
// Only the PUBLIC key is ever shown, and only that goes into the app. If this
// key leaks, anyone can mint licences and the scheme is over — the same
// property Sparkle's update key has, and it is stored the same way.
//
// ⚠️ A SEPARATE KEY FROM SPARKLE'S. Reusing the update-signing key would mean
// one compromise costs both the ability to sell and the ability to ship — and a
// stolen update key is the worse of the two, because it ships code.
//
//   swift scripts/licence-tool.swift generate
//   swift scripts/licence-tool.swift issue tony@example.com 395
//   swift scripts/licence-tool.swift verify <key>

let service = "ai.templetongroup.protect.licence-signing"
let account = "ed25519"

func keychainRead() -> Data? {
    let q: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
    return out as? Data
}

func keychainWrite(_ data: Data) -> Bool {
    let q: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
    ]
    SecItemDelete(q as CFDictionary)
    var add = q
    add[kSecValueData as String] = data
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
}

/// base64url without padding — a licence key gets pasted into an email, a
/// terminal and a text field, and `+`, `/` and `=` all get mangled somewhere
/// along that path.
func b64url(_ d: Data) -> String {
    d.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func unb64url(_ s: String) -> Data? {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("usage: generate | issue <email> <days> | batch <count> <days> [tag] | verify <key>")
    exit(2)
}

switch command {
case "generate":
    if keychainRead() != nil {
        print("A signing key already exists. Refusing to replace it — every licence")
        print("ever issued would stop verifying. Delete it by hand if that is really")
        print("what you want:")
        print("  security delete-generic-password -s \(service)")
        exit(1)
    }
    let key = Curve25519.Signing.PrivateKey()
    guard keychainWrite(key.rawRepresentation) else {
        print("could not write the key to the keychain"); exit(1)
    }
    print("Signing key created and stored in your login keychain.")
    print("")
    print("Put this in Info.plist as TPLicenceKey — it is the public half and is")
    print("safe to publish:")
    print("")
    print("    \(b64url(key.publicKey.rawRepresentation))")

case "issue":
    guard args.count >= 3, let days = Int(args[2]) else {
        print("usage: issue <email> <days>"); exit(2)
    }
    guard let raw = keychainRead(),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        print("no signing key — run: swift scripts/licence-tool.swift generate"); exit(1)
    }
    let email = args[1]
    let expires = Int(Date().addingTimeInterval(Double(days) * 86_400).timeIntervalSince1970)
    // Compact on purpose: this string gets pasted by a human.
    let payload = #"{"e":"\#(email)","x":\#(expires)}"#
    let body = Data(payload.utf8)
    guard let sig = try? key.signature(for: body) else { print("signing failed"); exit(1) }
    print("TP1-\(b64url(body)).\(b64url(sig))")

/*
 Mint a stack of keys for the store to hand out.

 ⚠️ THE CLOCK STARTS AT MINTING, NOT AT PURCHASE. A key carries an absolute
 expiry date, so one that sits unsold in the store for five months sells with
 seven months left on it. Mint in small, dated batches and top the store up —
 do not mint a year of inventory. Making the term start at activation instead
 needs a new key version and an app that understands it (TG-300).

 The `e` field carries a batch id rather than a buyer, because nobody knows who
 the buyer is at minting time. Nothing enforces the email — it is there so a key
 posted publicly can be traced to the batch it came from.
 */
case "batch":
    guard args.count >= 3, let count = Int(args[1]), let days = Int(args[2]), count > 0 else {
        print("usage: batch <count> <days> [tag]"); exit(2)
    }
    guard let raw = keychainRead(),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        print("no signing key — run: swift scripts/licence-tool.swift generate"); exit(1)
    }
    let stamp = ISO8601DateFormatter()
    stamp.formatOptions = [.withFullDate]
    let today = stamp.string(from: Date())
    let tag = args.count >= 4 ? args[3] : today
    let expiresAt = Date().addingTimeInterval(Double(days) * 86_400)
    let expires = Int(expiresAt.timeIntervalSince1970)

    var rows = ["key,batch,expires"]
    var minted = 0
    for _ in 0..<count {
        // Short random id: unique enough to trace, and it does not leak how many
        // have been sold by counting upwards in public.
        let id = (0..<6).map { _ in "abcdefghjkmnpqrstuvwxyz23456789".randomElement()! }
        let payload = #"{"e":"\#(tag)-\#(String(id))","x":\#(expires)}"#
        let body = Data(payload.utf8)
        guard let sig = try? key.signature(for: body) else { print("signing failed"); exit(1) }
        rows.append("TP1-\(b64url(body)).\(b64url(sig)),\(tag)-\(String(id)),\(expiresAt.ISO8601Format())")
        minted += 1
    }

    let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("licences-\(tag).csv")
    do { try rows.joined(separator: "\n").appending("\n").write(to: out, atomically: true, encoding: .utf8) }
    catch { print("could not write \(out.path): \(error)"); exit(1) }
    print("\(minted) keys, each good until \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
    print(out.path)
    print("")
    print("Upload that file as the store's licence key list. Keep it out of git —")
    print("every line in it is a working subscription.")

case "verify":
    guard args.count >= 2 else { print("usage: verify <key>"); exit(2) }
    guard let raw = keychainRead(),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        print("no signing key"); exit(1)
    }
    let text = args[1]
    guard text.hasPrefix("TP1-") else { print("not a Protect licence"); exit(1) }
    let parts = text.dropFirst(4).split(separator: ".")
    guard parts.count == 2, let body = unb64url(String(parts[0])), let sig = unb64url(String(parts[1])),
          key.publicKey.isValidSignature(sig, for: body) else {
        print("INVALID"); exit(1)
    }
    print("valid: \(String(data: body, encoding: .utf8) ?? "?")")

default:
    print("unknown command \(command)"); exit(2)
}
