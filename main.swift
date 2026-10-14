import Cocoa
import WebKit

// Bunny Organiser: a window with the Gengo bunny that runs ~/2026/_organize_new.py on demand.

let home = FileManager.default.homeDirectoryForCurrentUser
let script = home.appendingPathComponent("2026/_organize_new.py").path

final class Bot: NSObject, NSApplicationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var running: Process?

    func applicationDidFinishLaunching(_ note: Notification) {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "bot")
        web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Bunny Organiser"
        window.minSize = NSSize(width: 360, height: 560)
        window.contentView = web
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)

        let res = Bundle.main.resourceURL!
        web.loadFileURL(res.appendingPathComponent("index.html"), allowingReadAccessTo: res)
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func windowDidBecomeKey(_ note: Notification) {
        web.evaluateJavaScript("window.refresh && window.refresh()")
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "open":
            NSWorkspace.shared.open(home.appendingPathComponent("2026"))
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
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let bot = Bot()
app.delegate = bot
app.setActivationPolicy(.regular)
app.run()
