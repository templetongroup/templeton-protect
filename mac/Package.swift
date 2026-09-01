// swift-tools-version:5.9
import PackageDescription

// The Swift test target exists now (TG-291). The TypeScript suite pins the
// installations rules it was written against; everything added since 2026-08-31
// is pinned HERE, where the rules actually live, rather than by porting each
// rule to a second language so a copy of it can be tested.
let package = Package(
    name: "Protect",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "ProtectCore", path: "Sources/ProtectCore"),
        .executableTarget(name: "Protect", dependencies: ["ProtectCore"], path: "Sources/Protect"),
        .executableTarget(name: "Probe", dependencies: ["ProtectCore"], path: "Sources/Probe"),
        // The command-line face of the same engine — scan in CI, gate a commit.
        .executableTarget(name: "protect-cli", dependencies: ["ProtectCore"], path: "Sources/CLI"),
        .testTarget(name: "ProtectCoreTests", dependencies: ["ProtectCore"], path: "Tests/ProtectCoreTests"),
    ]
)
