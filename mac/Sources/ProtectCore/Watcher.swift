import CoreServices
import CryptoKit
import Foundation

/// FSEvents on the agent home folders, filtered to transcript writes.
///
/// ⚠️ THE WATCHER READS ONLY FILES THE SCAN WOULD READ, and only when the
/// filesystem says they changed. It never polls, and a file with no key hint in
/// its bytes is never decoded — the same cheap-check-first discipline as the
/// scan, because this runs all day.
///
/// ⚠️ ONE LEAKED KEY IS ONE ALERT, ACROSS RESTARTS. The first version kept the
/// reported paths in memory, so every relaunch re-announced every transcript
/// that still held a key — Tony, after a morning of test builds: "im also
/// getting constant pings like this now." A resident tool that cries the same
/// wolf on every launch is one people mute, and a muted alert is worse than no
/// alert because it looks like cover. What is remembered is a fingerprint of
/// which vendors and how many, so an appended-to session that keeps holding the
/// same key stays silent while a genuinely new key still speaks up.
///
/// ⚠️ AND THE PATH IS NOT WHAT GETS REMEMBERED. Preferences are world-readable;
/// the fingerprint is keyed by a hash of the path so this app's own bookkeeping
/// cannot become the list of where somebody's secrets live.
public final class TranscriptWatcher {
    public struct Hit: Sendable {
        public let path: String
        public let vendors: [String]
    }

    private var stream: FSEventStreamRef?
    private let roots: [String]
    private let onKeys: ([Hit]) -> Void
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "protect.watcher", qos: .utility)

    /// ⚠️ A BURST IS ONE EVENT TO A PERSON. Saving a file can touch several
    /// transcripts at once, and three banners for one moment is the storm in
    /// miniature. Hits collect for a beat and go out together.
    private var pending: [String: Hit] = [:]
    private var flush: DispatchWorkItem?
    private let coalesce: TimeInterval

    private static let key = "watchedKeyFingerprints"

    public init(roots: [String],
                defaults: UserDefaults = .standard,
                coalesce: TimeInterval = 3,
                onKeys: @escaping ([Hit]) -> Void) {
        self.roots = roots
        self.defaults = defaults
        self.coalesce = coalesce
        self.onKeys = onKeys
    }

    public func start() {
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<TranscriptWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watcher.changed(paths: Array(list.prefix(count)))
        }
        stream = FSEventStreamCreate(nil, callback, &context,
                                     roots as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     // ⚠️ 2s latency: transcripts are appended
                                     // line by line; coalescing keeps this from
                                     // running once per token.
                                     2.0,
                                     // ⚠️ UseCFTypes IS LOAD-BEARING. Without it the
                                     // callback's paths parameter is a C char** and
                                     // casting it to CFArray is a segfault — found by
                                     // the watcher test dying on signal 11.
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                                              | kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        flush?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /**
     Which assistant's folder this file lives in.

     ⚠️ A UUID FILENAME IS NOT A PLACE. The alert read "keys in
     1a183aae-5627-487d-b514-c49ed7c7c117.jsonl", which tells the reader nothing
     they can act on — Claude Code names session files by id. Naming the
     assistant is the fact a person can use; the exact path is on the finding
     card once the app is open.
     */
    public static func agent(forPath path: String, home: String = NSHomeDirectory()) -> String? {
        for ai in aiHomes {
            let root = (home as NSString).appendingPathComponent(ai.dir)
            if path.hasPrefix(root + "/") { return ai.tool }
        }
        return nil
    }

    /// What this file's keys look like, so an unchanged file stays quiet and a
    /// new key does not.
    static func fingerprint(_ vendors: [String]) -> String {
        Set(vendors).sorted().joined(separator: ",") + "×\(vendors.count)"
    }

    static func tag(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func changed(paths: [String]) {
        for path in paths {
            let name = (path as NSString).lastPathComponent
            guard name.hasSuffix(".jsonl") || name.hasSuffix(".log") || name.hasSuffix(".md") else { continue }
            guard mightHoldKey(at: path) else { continue }
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let vendors = findKeys(in: text)
            guard !vendors.isEmpty else { continue }

            var seen = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
            let tag = Self.tag(path)
            let print = Self.fingerprint(vendors)
            guard seen[tag] != print else { continue }   // same keys as last time — say nothing
            seen[tag] = print
            defaults.set(seen, forKey: Self.key)

            pending[path] = Hit(path: path, vendors: vendors)
        }
        guard !pending.isEmpty else { return }
        flush?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let batch = Array(self.pending.values)
            self.pending = [:]
            guard !batch.isEmpty else { return }
            self.onKeys(batch)
        }
        flush = work
        queue.asyncAfter(deadline: .now() + coalesce, execute: work)
    }

    /// Forget what has been reported — for "show me these again", and for tests.
    public static func forgetReported(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    deinit { stop() }
}
