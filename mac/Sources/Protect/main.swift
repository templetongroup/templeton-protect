import AppKit
import SwiftUI

// Templeton Protect.
//
// ⚠️ THE WEB VIEW IS GONE. It was the fastest way to iterate on a look, and the
// wrong way to ship one: a translucent panel drawn in CSS over an opaque window
// is a picture of glass, not glass. macOS 26's material samples what is actually
// behind it, and that only works if the interface is native. The scan never
// moved — it was already Swift — so this replaced a renderer, not the product.

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Templeton Protect"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // ⚠️ THE TITLE BAR MUST NOT PAINT. Glass refracts what is behind it, and
        // an opaque bar above the content is a grey band the material cannot see
        // through — the one detail that gives away a fake.
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 780, height: 580)
        window.center()
        window.contentView = NSHostingView(rootView: ContentView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate

let menu = NSMenu()
let appItem = NSMenuItem()
menu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "About Templeton Protect", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "Hide Templeton Protect", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
appMenu.addItem(withTitle: "Quit Templeton Protect", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
app.mainMenu = menu

app.run()
