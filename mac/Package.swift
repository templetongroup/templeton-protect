// swift-tools-version:5.9
import PackageDescription

// ⚠️ NO TEST TARGET YET. This said XCTest was absent because the machine had only
// the Command Line Tools; that stopped being true — xcode-select now points at
// /Applications/Xcode.app, so a Swift test target is possible and worth adding.
// The scan rules are pinned by the TypeScript suite in the parent directory,
// which is the same logic; the Checks executable guards the Swift-only parts.
let package = Package(
    name: "Protect",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "ProtectCore", path: "Sources/ProtectCore"),
        .executableTarget(name: "Protect", dependencies: ["ProtectCore"], path: "Sources/Protect"),
        .executableTarget(name: "Probe", dependencies: ["ProtectCore"], path: "Sources/Probe"),
    ]
)
