import Cocoa
import WebKit

// Mr. Box: a notification-sized floating banner with a tidy-box mascot that runs
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
        case "expand":
            setExpanded(body["open"] as? Bool ?? false)
        case "search":
            let query = body["query"] as? String ?? ""
            let id = body["id"] as? Int ?? 0
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let results = Search.run(query)
                let json = String(data: (try? JSONSerialization.data(withJSONObject: results)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
                DispatchQueue.main.async { self?.web.evaluateJavaScript("window.onResults(\(id), \(json))") }
            }
        case "openFile":
            if let path = body["path"] as? String { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        case "reveal":
            if let path = body["path"] as? String { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        case "list":
            run(["--list"], kind: "list")
        case "organise":
            run((body["preview"] as? Bool ?? false) ? ["--dry-run"] : [], kind: "organise")
        default: break
        }
    }

    // Search grows the banner downward (top edge stays put) and takes keyboard focus.
    func setExpanded(_ open: Bool) {
        let height: CGFloat = open ? 440 : bannerSize.height
        var frame = window.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        window.setFrame(frame, display: true, animate: true)
        if open {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(web)
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
        appMenu.addItem(withTitle: "Quit Mr. Box", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }
}

// Spotlight search across the home folder: file names first, then words inside documents.
enum Search {
    static let limit = 40
    static let skip = ["/Library/", "/.", "/node_modules/", ".app/", "/__pycache__/", "/2026/_move_log.tsv"]

    static func run(_ query: String) -> [[String: Any]] {
        let names = mdfind(["-onlyin", home.path, "-name", query])
        let content = mdfind(["-onlyin", home.path, query])
        var seen = Set<String>()
        var ranked: [(score: Int, path: String)] = []
        for (paths, isName) in [(names, true), (content, false)] {
            for p in paths where !seen.contains(p) && !skip.contains(where: { p.contains($0) }) {
                seen.insert(p)
                ranked.append((score(p, isName: isName), p))
            }
        }
        ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.path.count < $1.path.count }
        // Keep each project's results together, projects ordered by their best match.
        let top = ranked.prefix(limit).map { describe($0.path) }
        var order: [String] = []
        for r in top where !order.contains(r["group"] as! String) { order.append(r["group"] as! String) }
        return order.flatMap { g in top.filter { $0["group"] as! String == g } }
    }

    static func mdfind(_ args: [String]) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").prefix(500).map(String.init)
    }

    static func rel(_ path: String) -> String {
        path.hasPrefix(home.path + "/") ? String(path.dropFirst(home.path.count + 1)) : path
    }

    static func score(_ path: String, isName: Bool) -> Int {
        let r = rel(path)
        var s = isName ? 10 : 0
        if r.hasPrefix("2026/") && !r.contains("_To_Review") { s += 4 }
        if r.contains("/07_Final/") { s += 3 }
        if r.contains("/99_Archive/") { s -= 3 }
        s -= r.split(separator: "/").count / 4
        return s
    }

    // group = heading in the list, where = second line under the file name
    static func describe(_ path: String) -> [String: Any] {
        let r = rel(path)
        let parts = r.split(separator: "/").map(String.init)
        let name = parts.last ?? r
        var group = "Other places", where_ = "~/" + parts.dropLast().joined(separator: "/")
        if parts.first == "2026", parts.count >= 3 {
            if parts[1] == "_To_Review" {
                group = "To Review"; where_ = "2026 / _To_Review"
            } else if parts.count == 3 {
                group = parts[2].replacingOccurrences(of: "_", with: " ")
                where_ = "Project folder  ·  " + parts[1].replacingOccurrences(of: "_", with: " ")
            } else if parts.count >= 4 {
                group = parts[2].replacingOccurrences(of: "_", with: " ")
                where_ = parts[3..<(parts.count - 1)].joined(separator: " / ") + "  ·  " + parts[1].replacingOccurrences(of: "_", with: " ")
            }
        } else if let top = parts.first, ["Personal", "Installers"].contains(top) {
            group = top
        }
        return ["path": path, "name": name, "group": group, "where": where_, "icon": icon(path)]
    }

    static func icon(_ path: String) -> String {
        let img = NSWorkspace.shared.icon(forFile: path)
        let size = NSSize(width: 56, height: 56)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return "" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return "" }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}

// `MrBox --search "words"` prints results and exits (handy for testing search from a terminal).
if let i = CommandLine.arguments.firstIndex(of: "--search"), i + 1 < CommandLine.arguments.count {
    for r in Search.run(CommandLine.arguments[i + 1]) {
        print("[\(r["group"]!)] \(r["name"]!)  —  \(r["where"]!)  (icon \(((r["icon"] as? String) ?? "").count > 100 ? "ok" : "missing"))")
    }
    exit(0)
}

let app = NSApplication.shared
let bot = Bot()
app.delegate = bot
app.setActivationPolicy(.regular)
app.run()
