import AppKit

// The only place this app writes anything.
//
// ⚠️ EVERY GUARD ASSUMES THE REQUEST IS WRONG. It arrives from a web view, and a
// web view renders whatever it is given — so a fix is never "do what the message
// says". It is: prove the target is ours, prove it is still what we found, act,
// then check the act took.

/**
 ⚠️ THE ALLOWED ROOTS ARE THE AI HOMES PLUS WHATEVER THE USER OPENED A PANEL TO
 CHOOSE, AND NOTHING ELSE. The code scan can report a file anywhere on the disk,
 so the old rule — "must be under ~/.claude and friends" — would have refused
 every fix it offers. Widening it to "anywhere" is the wrong repair: the roots
 that get added here are the ones somebody picked in a save panel by hand, which
 is the same consent the export destination relies on.
 */
public func insideScannedTree(_ target: String, home: String = NSHomeDirectory(),
                              extraRoots: [String] = []) -> Bool {
    let expanded = target.hasPrefix("~")
        ? (home as NSString).appendingPathComponent(String(target.dropFirst(1)))
        : target
    // ⚠️ RESOLVED FIRST, so "~/.claude/../../etc/passwd" fails here rather than
    // succeeding quietly.
    let full = (expanded as NSString).standardizingPath
    let roots = aiHomes.map { ((home as NSString).appendingPathComponent($0.dir) as NSString).standardizingPath }
        + extraRoots.map { ($0 as NSString).standardizingPath }
    return roots.contains { full == $0 || full.hasPrefix($0 + "/") }
}

public func applyFix(_ fix: FixAction, home: String = NSHomeDirectory(),
                     extraRoots: [String] = []) -> FixOutcome {
    // ⚠️ BEFORE THE PATH GUARDS, BECAUSE THIS TARGET IS NOT A PATH. Running an
    // openSettings action through standardizingPath and attributesOfItem gives
    // "that file is already gone" for every machine finding on the screen.
    if fix.kind == .openSettings { return openSettings(fix.target) }

    let expanded = fix.target.hasPrefix("~")
        ? (home as NSString).appendingPathComponent(String(fix.target.dropFirst(1)))
        : fix.target
    let full = (expanded as NSString).standardizingPath

    guard insideScannedTree(fix.target, home: home, extraRoots: extraRoots) else {
        return FixOutcome(ok: false, message: "That path is outside the folders this app scans, so it will not be touched.")
    }

    let fm = FileManager.default
    // ⚠️ THE LINK, NOT ITS TARGET. destinationOfSymbolicLink succeeding means
    // this is a symlink, and following one would land the change somewhere else.
    if (try? fm.destinationOfSymbolicLink(atPath: full)) != nil {
        return FixOutcome(ok: false, message: "That path is a symbolic link, so it is left alone.")
    }
    guard let attrs = try? fm.attributesOfItem(atPath: full) else {
        return FixOutcome(ok: false, message: "That file is already gone. Scan again to refresh the list.")
    }
    guard (attrs[.type] as? FileAttributeType) == .typeRegular else {
        return FixOutcome(ok: false, message: "That path is not a regular file, so it is left alone.")
    }

    switch fix.kind {
    case .chmod:
        let mode = fix.mode ?? 0o600
        do {
            try fm.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: full)
        } catch {
            return FixOutcome(ok: false, message: "Could not change permissions: \(error.localizedDescription)")
        }
        // ⚠️ CONFIRM IT TOOK. Reporting success without checking is how a tool
        // tells somebody they are safe when they are not.
        let now = ((try? fm.attributesOfItem(atPath: full))?[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        return now == mode
            ? FixOutcome(ok: true, message: "Now readable only by you (\(String(format: "%03o", now))).")
            : FixOutcome(ok: false, message: "Permissions did not change — still \(String(format: "%03o", now)).")
    case .deleteFile:
        do {
            try fm.removeItem(atPath: full)
        } catch {
            return FixOutcome(ok: false, message: "Could not delete it: \(error.localizedDescription)")
        }
        return FixOutcome(ok: true, message: "Deleted. The keys that were in it still need rotating at the service that issued them.")
    case .openSettings:
        return openSettings(fix.target)
    case .redactInFile:
        guard let before = try? String(contentsOfFile: full, encoding: .utf8) else {
            return FixOutcome(ok: false, message: "Could not read that file to edit it.")
        }
        let (text, removed) = redactKeys(before)
        if removed == 0 {
            return FixOutcome(ok: true, message: "No key-shaped values left in it — nothing to remove.")
        }
        /*
         ⚠️ WRITE BESIDE IT AND RENAME. Truncating the real file and refilling it
         means an interrupted write leaves somebody's conversation half
         destroyed — which is precisely the outcome this fix exists to avoid.
         Rename is atomic, so the file is either the old one or the new one.
         */
        let tmp = full + ".protect-\(ProcessInfo.processInfo.processIdentifier)"
        do {
            try text.write(toFile: tmp, atomically: false, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: NSNumber(value: UInt16(0o600))], ofItemAtPath: tmp)
            _ = try fm.replaceItemAt(URL(fileURLWithPath: full), withItemAt: URL(fileURLWithPath: tmp))
        } catch {
            try? fm.removeItem(atPath: tmp)
            return FixOutcome(ok: false, message: "Could not rewrite it: \(error.localizedDescription)")
        }
        // ⚠️ CONFIRM IT ACTUALLY TOOK, the same as chmod above. Telling somebody
        // a key is gone while it is still on disk is worse than not offering.
        let after = (try? String(contentsOfFile: full, encoding: .utf8)).map { findKeys(in: $0) } ?? []
        guard after.isEmpty else {
            return FixOutcome(ok: false, message: "\(after.count) key-shaped value(s) are still in the file. Nothing was lost — but do not treat this as done.")
        }
        return FixOutcome(ok: true, message: "\(removed) value(s) replaced with a marker; the rest of the conversation is untouched. The keys themselves are still live until you rotate them.")
    }
}

/**
 Open the System Settings pane a machine finding names.

 ⚠️ THE PANE IS CHOSEN BY macOS VERSION, NOT PROBED, AND THAT IS THE WHOLE POINT
 OF THIS FUNCTION. Ventura renamed every settings pane, so the identifiers come
 in pairs. The obvious design — try the modern one, fall back to the legacy one
 if it fails — cannot work, and it took opening the pane and watching it to see
 why: `NSWorkspace.open` returns **true for any URL using this scheme**, because
 System Settings claims the scheme itself and is launched whether or not the pane
 identifier means anything to it. A wrong identifier therefore reports success
 and drops somebody on the front page with no explanation. So the fallback chain
 was a fiction; the version test is the real answer.

 ⚠️ AND THE LAST RESORT STILL EARNS ITS PLACE. If the URL cannot be built or
 System Settings is not where it is expected, the app opens System Settings by
 path and says so, because a finding that leaves somebody with a sentence and no
 working button is the failure this project has a rule against.
 */
func openSettings(_ target: String) -> FixOutcome {
    let panes = target.split(separator: "|").map(String.init)
    // macOS 13 is where the pane identifiers changed; this app runs on 12.
    let ventura = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0))
    let pane = (ventura ? panes.first : panes.last) ?? ""
    if !pane.isEmpty, let url = URL(string: "x-apple.systempreferences:" + pane),
       NSWorkspace.shared.open(url) {
        return FixOutcome(ok: true, message: "System Settings is open at that pane. The change is yours to make — this app does not flip system switches for you.")
    }
    for app in ["/System/Applications/System Settings.app", "/System/Applications/System Preferences.app"] {
        if FileManager.default.fileExists(atPath: app),
           NSWorkspace.shared.open(URL(fileURLWithPath: app)) {
            return FixOutcome(ok: true, message: "System Settings is open. This version of macOS moved the pane, so use the search box at the top left — the remedy above names it.")
        }
    }
    return FixOutcome(ok: false, message: "Could not open System Settings. The remedy above names the pane to open by hand.")
}
