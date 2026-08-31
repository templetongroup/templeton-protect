import Foundation

/// What is on this Mac, answered before any scanning happens.
///
/// ⚠️ THIS IS DELIBERATELY NOT A SCAN. The idle screen needs something true
/// about *this* machine to show — a scanner whose first screen is a paragraph of
/// marketing tells you nothing you could not have read on a website. But it also
/// has to be instant, so nothing here opens a file or reads a byte of content:
/// it checks for the directory and counts entries under a hard cap.
public struct Installed: Identifiable, Sendable {
    public let tool: String
    public let dir: String
    public let files: Int
    /// True when the count stopped at the cap rather than at the end.
    public let atLeast: Bool
    public var id: String { dir }
}

/// Counting is capped because ~/.claude on a working machine holds tens of
/// thousands of files, and the idle screen must not wait for a full walk.
private let countCap = 4000

public func detectInstallations(home: String = NSHomeDirectory()) -> [Installed] {
    let fm = FileManager.default
    return aiHomes.compactMap { ai in
        let path = (home as NSString).appendingPathComponent(ai.dir)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        var n = 0
        if let walk = fm.enumerator(at: URL(fileURLWithPath: path),
                                    includingPropertiesForKeys: nil,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            while walk.nextObject() != nil {
                n += 1
                if n >= countCap { break }
            }
        }
        return Installed(tool: ai.tool, dir: "~/" + ai.dir, files: n, atLeast: n >= countCap)
    }
}
