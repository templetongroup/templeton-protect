import Foundation
import ProtectCore
let t = Date()
let r = scanAiInstallations()
print(String(format: "swift: %d findings, %d files, %.1fs", r.findings.count, r.filesRead, -t.timeIntervalSinceNow))
