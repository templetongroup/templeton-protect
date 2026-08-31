import Foundation

// The only place this app writes anything.
//
// ⚠️ EVERY GUARD ASSUMES THE REQUEST IS WRONG. It arrives from a web view, and a
// web view renders whatever it is given — so a fix is never "do what the message
// says". It is: prove the target is ours, prove it is still what we found, act,
// then check the act took.

public func insideScannedTree(_ target: String, home: String = NSHomeDirectory()) -> Bool {
    let expanded = target.hasPrefix("~")
        ? (home as NSString).appendingPathComponent(String(target.dropFirst(1)))
        : target
    // ⚠️ RESOLVED FIRST, so "~/.claude/../../etc/passwd" fails here rather than
    // succeeding quietly.
    let full = (expanded as NSString).standardizingPath
    return aiHomes.contains { ai in
        let root = ((home as NSString).appendingPathComponent(ai.dir) as NSString).standardizingPath
        return full == root || full.hasPrefix(root + "/")
    }
}

public func applyFix(_ fix: FixAction, home: String = NSHomeDirectory()) -> FixOutcome {
    let expanded = fix.target.hasPrefix("~")
        ? (home as NSString).appendingPathComponent(String(fix.target.dropFirst(1)))
        : fix.target
    let full = (expanded as NSString).standardizingPath

    guard insideScannedTree(fix.target, home: home) else {
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
    }
}
