import Foundation

/// A cancellation flag the scanning thread can read without hopping actors.
///
/// ⚠️ POLLED ONCE PER FILE — thousands of times in a run. Anything that requires
/// a hop to the main actor to read costs more than the work it is guarding.
final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
    func reset() { lock.lock(); value = false; lock.unlock() }
}

/// Lets something through at most once per interval.
final class Throttle: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: TimeInterval
    private var last: TimeInterval = 0
    init(interval: TimeInterval) { self.interval = interval }

    func ready() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        guard now - last >= interval else { return false }
        last = now
        return true
    }
}
