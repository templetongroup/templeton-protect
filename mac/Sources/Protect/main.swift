import AppKit
import WebKit
import ProtectCore

// Templeton Protect — the Mac app.
//
// ⚠️ NO SERVER, AND THAT IS THE POINT. The first version ran the scan in Node
// behind localhost, which meant shipping a runtime dependency a .app cannot rely
// on — an app launched from Finder gets a minimal PATH and would not have found
// node — and defending a local HTTP port with tokens and Origin checks because
// any page in any browser can post to localhost. Native removes both problems:
// nothing listens, and there is nothing to find on PATH.
//
// ⚠️ THE WEB VIEW RENDERS WHATEVER IT IS GIVEN, so the bridge below treats every
// message as untrusted. A fix is decoded into a typed struct and re-validated by
// ProtectCore before anything is touched.

final class Bridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var web: WKWebView?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let kind = body["kind"] as? String,
              let ticket = body["ticket"] as? String else { return }

        switch kind {
        case "scan":
            // Off the main thread: a scan reads thousands of files and freezing
            // the window during it is how an app feels broken.
            DispatchQueue.global(qos: .userInitiated).async {
                let result = scanAiInstallations()
                self.reply(ticket: ticket, encodable: result)
            }
        case "fix":
            guard let raw = body["fix"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let fix = try? JSONDecoder().decode(FixAction.self, from: data) else {
                reply(ticket: ticket, encodable: FixOutcome(ok: false, message: "That request could not be read."))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                self.reply(ticket: ticket, encodable: applyFix(fix))
            }
        default:
            break
        }
    }

    private func reply<T: Encodable>(ticket: String, encodable: T) {
        guard let data = try? JSONEncoder().encode(encodable),
              let json = String(data: data, encoding: .utf8) else { return }
        // ⚠️ BASE64, NOT STRING INTERPOLATION. A path or a finding can contain a
        // quote or a backslash, and pasting JSON straight into a script is how a
        // filename becomes code.
        let payload = Data(json.utf8).base64EncodedString()
        DispatchQueue.main.async {
            self.web?.evaluateJavaScript("window.__reply('\(ticket)', '\(payload)')")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let bridge = Bridge()

    func applicationDidFinishLaunching(_ note: Notification) {
        let config = WKWebViewConfiguration()
        config.userContentController.add(bridge, name: "protect")
        // Nothing here loads anything remote, so nothing needs to persist.
        config.websiteDataStore = .nonPersistent()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Templeton Protect"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 760, height: 560)
        window.center()

        web = WKWebView(frame: window.contentView!.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = bridge
        bridge.web = web
        window.contentView!.addSubview(web)

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            // A missing UI must say so rather than showing a white rectangle.
            web.loadHTMLString("<body style='font:14px -apple-system;padding:40px'>The interface is missing from this build.</body>", baseURL: nil)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate

// The menu bar has to exist or Command-Q does nothing.
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
