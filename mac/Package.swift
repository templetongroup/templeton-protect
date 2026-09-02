// swift-tools-version:5.9
import Foundation
import PackageDescription

/*
 ⚠️ THE PAID LAYER IS NOT IN THIS REPOSITORY. Protect+ — the resident menu bar,
 the schedule, the live transcript watcher and the licence verification — lives
 in templetongroup/templeton-protect-plus, which is private. Its sources are
 checked out into the `Plus` folders below, which are gitignored here.

 A public clone has no `Plus` folders, so PROTECT_PLUS is undefined and the app
 builds as the free scanner: every rule, every fix, every export, and no paywall
 code to delete. That is the point of the split — LICENSE already called the
 resident layer commercial, and until now its source sat in a public repository
 with a removable `if`, which made the split a claim rather than a fact.

 scripts/link-plus.sh wires a local checkout in.
*/
func hasPlus() -> Bool {
    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let dir = here.appendingPathComponent("Sources/ProtectCore/Plus")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return files.contains { $0.hasSuffix(".swift") }
}
let plus = hasPlus()
let plusFlags: [SwiftSetting] = plus ? [.define("PROTECT_PLUS")] : []

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
        .target(name: "ProtectCore", path: "Sources/ProtectCore", swiftSettings: plusFlags),
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
                          swiftSettings: plusFlags,
                          linkerSettings: [.unsafeFlags([
                              "-Xlinker", "-rpath",
                              "-Xlinker", "@executable_path/../Frameworks",
                          ])]),
        .executableTarget(name: "Probe", dependencies: ["ProtectCore"], path: "Sources/Probe"),
        // The command-line face of the same engine — scan in CI, gate a commit.
        .executableTarget(name: "protect-cli", dependencies: ["ProtectCore"], path: "Sources/CLI"),
        .testTarget(name: "ProtectCoreTests", dependencies: ["ProtectCore"], path: "Tests/ProtectCoreTests", swiftSettings: plusFlags),
    ]
)
