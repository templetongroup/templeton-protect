// swift-tools-version:5.9
import PackageDescription

// The Swift test target exists now (TG-291). The TypeScript suite pins the
// installations rules it was written against; everything added since 2026-08-31
// is pinned HERE, where the rules actually live, rather than by porting each
// rule to a second language so a copy of it can be tested.
let package = Package(
    name: "Protect",
    platforms: [.macOS(.v12)],
    dependencies: [
        // ⚠️ THE AUDITED STANDARD, NOT A HAND-ROLLED UPDATER. This app asks
        // people to trust it with the contents of their machine; the one piece
        // that downloads and replaces the binary is the last place to invent
        // something. Sparkle verifies an EdDSA signature over the archive and
        // checks the Developer ID before it swaps anything.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "ProtectCore", path: "Sources/ProtectCore"),
        .executableTarget(name: "Protect", dependencies: ["ProtectCore", .product(name: "Sparkle", package: "Sparkle")], path: "Sources/Protect",
                          /*
                           ⚠️ SwiftPM PICKS UP .metal FILES BY ITSELF AND TRIES TO
                           COMPILE THEM — even with no `resources:` declaration.
                           On a universal build that needs the full Metal
                           Toolchain, which is a separate Xcode download, and the
                           release died at `swift build` with "cannot execute tool
                           'metal'". It read like a notarisation problem and was
                           not; the build never produced a binary.

                           The shaders are excluded here and compiled by build.sh
                           and release.sh with `xcrun metal`, which works without
                           the extra component. One metallib serves both
                           architectures: it holds AIR, which is GPU-family
                           specific rather than CPU specific.
                           */
                          exclude: ["Shaders"],
                          // ⚠️ THE APP IS HAND-ASSEMBLED, so nothing sets an
                          // rpath for it. Sparkle ships as a framework that
                          // lives in Contents/Frameworks; without this the
                          // binary builds and then dies at launch with "image
                          // not found".
                          linkerSettings: [.unsafeFlags([
                              "-Xlinker", "-rpath",
                              "-Xlinker", "@executable_path/../Frameworks",
                          ])]),
        .executableTarget(name: "Probe", dependencies: ["ProtectCore"], path: "Sources/Probe"),
        // The command-line face of the same engine — scan in CI, gate a commit.
        .executableTarget(name: "protect-cli", dependencies: ["ProtectCore"], path: "Sources/CLI"),
        .testTarget(name: "ProtectCoreTests", dependencies: ["ProtectCore"], path: "Tests/ProtectCoreTests"),
    ]
)
