import CoreServices
import Foundation

/// FSEvents on the agent home folders, filtered to transcript writes.
///
/// ⚠️ THE WATCHER READS ONLY FILES THE SCAN WOULD READ, and only when the
/// filesystem says they changed. It never polls, and a file with no key hint in
/// its bytes is never decoded — the same cheap-check-first discipline as the
/// scan, because this runs all day.
public final class TranscriptWatcher {
    private var stream: FSEventStreamRef?
    private let roots: [String]
    private let onKey: (String, [String]) -> Void
    /// Paths already reported, so one leaked key is one notification.
    private var reported = Set<String>()
    private let queue = DispatchQueue(label: "protect.watcher", qos: .utility)

    public init(roots: [String], onKey: @escaping (String, [String]) -> Void) {
        self.roots = roots
        self.onKey = onKey
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
                                     // the watcher test dying on signal 11, which is
                                     // the whole reason the watcher lives in core
                                     // where a test can reach it.
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                                              | kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func changed(paths: [String]) {
        for path in paths {
            let name = (path as NSString).lastPathComponent
            guard name.hasSuffix(".jsonl") || name.hasSuffix(".log") || name.hasSuffix(".md") else { continue }
            guard !reported.contains(path) else { continue }
            guard mightHoldKey(at: path) else { continue }
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let vendors = findKeys(in: text)
            guard !vendors.isEmpty else { continue }
            reported.insert(path)
            onKey(path, vendors)
        }
    }

    deinit { stop() }
}
