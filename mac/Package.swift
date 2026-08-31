// swift-tools-version:5.9
import PackageDescription

// ⚠️ NO TEST TARGET, AND NOT BY CHOICE — the same constraint as the AiOS app:
// this machine has the Command Line Tools, not full Xcode, so XCTest is absent.
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
