import AppKit
import SwiftUI

// Templeton Protect.
//
// ⚠️ THE WEB VIEW IS GONE. It was the fastest way to iterate on a look, and the
// wrong way to ship one: a translucent panel drawn in CSS over an opaque window
// is a picture of glass, not glass. macOS 26's material samples what is actually
// behind it, and that only works if the interface is native. The scan never
// moved — it was already Swift — so this replaced a renderer, not the product.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    // ⚠️ Model is @MainActor, so the delegate that owns it must be too — the
    // alternative is a nonisolated init reaching into main-actor state.
    let model = Model()

    @objc func scanNow(_ sender: Any?) { model.scan() }

    @objc func openHelp(_ sender: Any?) {
        if let url = URL(string: "https://github.com/templetongroup/templeton-protect") {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(
            // ⚠️ TALL ENOUGH FOR THE WHOLE OPENING SCREEN. At 720 the footer fell below
            // the fold on first launch, so the first thing a new user saw was a
            // page that had already been cut off.
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 860),
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
        // ⚠️ SET ON THE WINDOW, NOT JUST THE VIEW. preferredColorScheme styles
        // SwiftUI controls but leaves AppKit's own label color in light mode,
        // which is how the app's own title came out black on navy.
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        if ProcessInfo.processInfo.environment["PROTECT_GEOM"] != nil {
            let cv = window.contentView!
            FileHandle.standardError.write("""
            frame=\(cv.frame)
            contentLayoutRect=\(window.contentLayoutRect)
            windowFrame=\(window.frame)

            """.data(using: .utf8)!)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

// ⚠️ TOP-LEVEL CODE IS NOT ON THE MAIN ACTOR HERE, and the delegate and its
// model both are. assumeIsolated is correct rather than a workaround: this runs
// on the main thread by definition — it is the process entry point — the
// compiler simply cannot see that from a top-level statement.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate

    // ⚠️ A MAC APP HAS A MENU BAR, AND MINE HAD ONE MENU. The checklist is
    // App/File/Edit/View/Window/Help with Settings on Command-comma — an app missing
    // Edit has no Copy, no Select All and no dictation, all of which the system
    // would have provided for free. Every primary command is reachable from the
    // keyboard: Command-R scans.
    let menu = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About Templeton Protect", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide Templeton Protect", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(hideOthers)
    appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit Templeton Protect", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    menu.addItem(appItem)

    let scanItem = NSMenuItem()
    let scanMenu = NSMenu(title: "Scan")
    scanMenu.addItem(withTitle: "Scan Now", action: #selector(AppDelegate.scanNow(_:)), keyEquivalent: "r")
    scanItem.submenu = scanMenu
    menu.addItem(scanItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
    editItem.submenu = editMenu
    menu.addItem(editItem)

    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    windowItem.submenu = windowMenu
    menu.addItem(windowItem)
    app.windowsMenu = windowMenu

    let helpItem = NSMenuItem()
    let helpMenu = NSMenu(title: "Help")
    helpMenu.addItem(withTitle: "Templeton Protect Help", action: #selector(AppDelegate.openHelp(_:)), keyEquivalent: "?")
    helpItem.submenu = helpMenu
    menu.addItem(helpItem)

    app.mainMenu = menu

    app.run()
}
