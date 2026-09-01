import AppKit
import SwiftUI
import ProtectCore

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
    /// The Protect+ layer: menu bar, schedule, transcript watcher. Owned here
    /// so it outlives the window.
    var resident: Resident?

    // ⚠️ ONE SELECTOR, THREE ITEMS. NSMenuItem needs an Objective-C target and
    // a SwiftUI view is not one, so which scan an item runs travels in its tag
    // rather than in three near-identical methods.
    @objc func scanNow(_ sender: Any?) {
        let kind = (sender as? NSMenuItem).flatMap { ScanKind.allCases.indices.contains($0.tag) ? ScanKind.allCases[$0.tag] : nil }
        model.scan(kind ?? .installations)
    }

    @objc func openHelp(_ sender: Any?) {
        if let url = URL(string: "https://github.com/templetongroup/templeton-protect") {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        makeWindow()
        resident = Resident(model: model, showWindow: { [weak self] in self?.showWindow() })
        model.resident = { [weak self] in self?.resident }
        showWindow()
    }

    /**
     Bring the window back, from the menu bar or from anywhere else.

     ⚠️ THE DELEGATE OWNS ITS WINDOW; NOBODY REACHES THROUGH `NSApp.windows`.
     The menu bar's "Open Templeton Protect" used to do
     `NSApp.windows.first?.makeKeyAndOrderFront(nil)`, and it did nothing at all.
     Once a status item exists, `NSApp.windows` also holds the status bar's own
     window, and `.first` is not documented to be the one you meant — so the call
     raised a 22pt strip in the menu bar and left the real window where it was.
     Measured, not guessed: after clicking the item, the frontmost application
     was Preview.

     ⚠️ AND `orderFrontRegardless()` AFTER THE ACTIVATE. `activate` is a request
     macOS is allowed to refuse — a background app asking for the foreground is
     exactly the thing recent macOS got stricter about — and a refused activate
     leaves the window behind whatever is in front of it. That is the "button
     that silently does nothing" failure this project has a rule against, so the
     window is ordered front whether or not the app won activation.
     */
    func showWindow() {
        if window == nil { makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() {
        window = NSWindow(
            /*
             ⚠️ TALL ENOUGH FOR THE WHOLE OPENING SCREEN, AND THIS REGRESSES EVERY
             TIME A ROW IS ADDED. At 720 the footer fell below the fold on first
             launch. It happened again at 860 the moment the Keep watch row went
             in — Tony: "the main window does not show the templeton technologies
             logo when it opens." The company mark is the last thing on the page,
             so it is the canary: if it is not visible on open, the window is too
             short. Measure it in a screenshot after adding anything to the idle
             screen; do not assume the old number still holds.
             */
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Templeton Protect"
        // ⚠️ A PROGRAMMATIC NSWindow IS RELEASED WHEN CLOSED BY DEFAULT, and this
        // delegate holds its own strong reference — so the red button handed the
        // window to AppKit to destroy while `window` still pointed at it. With
        // keep-watch on, closing the window is a normal thing to do and reopening
        // it is the whole point of the menu item; the app must still own a window
        // afterwards.
        window.isReleasedWhenClosed = false
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
    }

    // ⚠️ CLOSING THE WINDOW MUST NOT KILL THE WATCH. When keep-watch is on the
    // app lives in the menu bar; quitting is the menu's Quit item, on purpose.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        !(resident?.enabled ?? false)
    }
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
    // ⚠️ IN THE APP MENU WHERE macOS USERS LOOK FOR IT, not buried in settings.
    let updates = NSMenuItem(title: "Check for Updates…",
                             action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
    updates.target = Updater.shared
    appMenu.addItem(updates)
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
    // Command-1, 2, 3, in the order they appear on the opening screen.
    for (i, kind) in ScanKind.allCases.enumerated() {
        let item = NSMenuItem(title: kind.title, action: #selector(AppDelegate.scanNow(_:)),
                              keyEquivalent: "\(i + 1)")
        item.tag = i
        scanMenu.addItem(item)
    }
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
