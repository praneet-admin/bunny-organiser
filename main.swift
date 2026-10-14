import Cocoa
import WebKit

// Bunny Organiser: a notification-sized floating banner with the Gengo bunny that runs
// ~/2026/_organize_new.py on demand.

let home = FileManager.default.homeDirectoryForCurrentUser
let script = home.appendingPathComponent("2026/_organize_new.py").path
let bannerSize = NSSize(width: 360, height: 80)

// Borderless panels can't become key by default; we need that for clicks and Option-click.
final class Banner: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Bot: NSObject, NSApplicationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    var window: Banner!
    var web: WKWebView!
    var running: Process?
    var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "bot")
        web = WKWebView(frame: NSRect(origin: .zero, size: bannerSize), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]

        // Frosted rounded card, like a macOS notification.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: bannerSize))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        blur.addSubview(web)

        window = Banner(contentRect: NSRect(origin: .zero, size: bannerSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.contentView = blur
        window.delegate = self
        placeTopRight()
        window.orderFrontRegardless()

        let res = Bundle.main.resourceURL!
        web.loadFileURL(res.appendingPathComponent("index.html"), allowingReadAccessTo: res)
        buildMenu()

        // Keep the "N new files waiting" badge fresh. Listing is cheap (no Claude call).
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.web.evaluateJavaScript("window.refresh && window.refresh()")
        }
    }

    func placeTopRight() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: f.maxX - bannerSize.width - 16, y: f.maxY - bannerSize.height - 12))
    }

    // Clicking the Dock icon brings the banner back after it was hidden.
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        placeTopRight()
        window.orderFrontRegardless()
        web.evaluateJavaScript("window.refresh && window.refresh()")
        return true
    }

    func windowDidBecomeKey(_ note: Notification) {
        web.evaluateJavaScript("window.refresh && window.refresh()")
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "open":
            NSWorkspace.shared.open(home.appendingPathComponent("2026"))
        case "hide":
            window.orderOut(nil)
        case "list":
            run(["--list"], kind: "list")
        case "organise":
            run((body["preview"] as? Bool ?? false) ? ["--dry-run"] : [], kind: "organise")
        default: break
        }
    }

    func run(_ args: [String], kind: String) {
        if running != nil { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-u", script] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        p.currentDirectoryURL = home

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var buffer = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let chunk = String(data: h.availableData, encoding: .utf8), !chunk.isEmpty else { return }
            buffer += chunk
            while let nl = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<nl])
                buffer = String(buffer[buffer.index(after: nl)...])
                DispatchQueue.main.async { self?.send("onLine", line) }
            }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                for line in (buffer + rest).split(separator: "\n") { self?.send("onLine", String(line)) }
                self?.running = nil
                self?.web.evaluateJavaScript("window.onDone(\(Self.js(kind)), \(proc.terminationStatus))")
            }
        }
        do {
            try p.run()
            running = p
        } catch {
            send("onLine", "Could not start organiser: \(error.localizedDescription)")
            web.evaluateJavaScript("window.onDone(\(Self.js(kind)), 1)")
        }
    }

    func send(_ fn: String, _ text: String) {
        web.evaluateJavaScript("window.\(fn)(\(Self.js(text)))")
    }

    static func js(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s])
        let arr = String(data: data, encoding: .utf8)!
        return String(arr.dropFirst().dropLast())
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Bunny Organiser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let bot = Bot()
app.delegate = bot
app.setActivationPolicy(.regular)
app.run()
