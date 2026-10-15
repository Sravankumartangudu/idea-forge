// Extras.swift — the parts that reach outside the board: global hotkeys, reading the page you're on,
// the quick-capture box, the weekly digest, the update check, and the local signals that
// 🔍 Find challenges looks through.

import AppKit
import Carbon
import UserNotifications

// MARK: - Global hotkeys (⌃⌥N quick capture; ⌃⌥I captures the page, only where page reading is on)

enum Hotkeys {
    private static var refs: [EventHotKeyRef] = []
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handler: EventHandlerRef?
    /// The keys in use, e.g. "⌃⌥", or "" when off (or another app holds them).
    private(set) static var label = ""

    static func register(page: @escaping () -> Void, quick: @escaping () -> Void) {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        label = ""
        guard Settings.hotkeys else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                DispatchQueue.main.async { Hotkeys.actions[id.id]?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        actions = [1: page, 2: quick]
        // ⌃⌥ first; if another app (say, the other Idea Forge edition) already holds them, add ⇧.
        for (mods, text) in Settings.hotkeyShift ? [(controlKey | optionKey | shiftKey, "⌃⌥⇧")]
                                                 : [(controlKey | optionKey, "⌃⌥"), (controlKey | optionKey | shiftKey, "⌃⌥⇧")] {
            var got: [EventHotKeyRef] = []
            let keys = Settings.pageReading ? [(kVK_ANSI_I, UInt32(1)), (kVK_ANSI_N, UInt32(2))] : [(kVK_ANSI_N, UInt32(2))]
            for (key, id) in keys {
                var ref: EventHotKeyRef?
                let sig = EventHotKeyID(signature: OSType(0x4946_4f47), id: id)   // 'IFOG'
                if RegisterEventHotKey(UInt32(key), UInt32(mods), sig, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { got.append(ref) }
            }
            if got.count == keys.count { refs = got; label = text; return }
            got.forEach { UnregisterEventHotKey($0) }
        }
    }
}

// MARK: - Reading the page you're on (📎 Capture)

/// What 📎 Capture saw. Only `url`/`title`/`selection` (and, when the edition doesn't read the page with
/// its own tools, a trimmed `text`) go to the AI; nothing here is stored.
struct Page {
    var url = "", title = "", app = "", selection = "", text = ""
}

enum PageReader {
    struct Failure: LocalizedError { let errorDescription: String? }

    /// Browsers that answer Apple Events for their active tab. Firefox doesn't.
    static let browsers: [String: (name: String, safari: Bool)] = [
        "com.google.Chrome": ("Chrome", false), "com.google.Chrome.beta": ("Chrome Beta", false),
        "com.google.Chrome.canary": ("Chrome Canary", false), "com.microsoft.edgemac": ("Edge", false),
        "com.brave.Browser": ("Brave", false), "company.thebrowser.Browser": ("Arc", false),
        "com.vivaldi.Vivaldi": ("Vivaldi", false), "com.operasoftware.Opera": ("Opera", false),
        "com.apple.Safari": ("Safari", true), "com.apple.SafariTechnologyPreview": ("Safari Preview", true),
    ]
    static let slack = "com.tinyspeck.slackmacgap"

    /// The last browser or Slack you were in, so Capture from the board or the menu still knows the page.
    private static var last: String?
    private static var watching: NSObjectProtocol?
    private static var clipCount = NSPasteboard.general.changeCount

    /// Only while page reading is on (an edition that never offers it never starts).
    static func start() {
        guard Settings.pageReading, watching == nil else { return }
        noteFront()
        watching = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in noteFront() }
    }
    static func stop() {
        if let w = watching { NSWorkspace.shared.notificationCenter.removeObserver(w) }
        watching = nil
        last = nil
    }
    private static func noteFront() {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        if browsers[bid] != nil || bid == slack {
            if bid == slack && last != slack { clipCount = NSPasteboard.general.changeCount }
            last = bid
        }
    }

    /// The page in the last browser you used (or what you copied in Slack). Main thread.
    static func read() -> Result<Page, Error> {
        guard Settings.pageReading else { return .failure(Failure(errorDescription: "Page reading is off. Turn it on in Settings first.")) }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var bid = last.flatMap { running.contains($0) ? $0 : nil }
        if bid == nil { bid = browsers.keys.sorted().first { running.contains($0) } }
        guard let bid else { return .failure(Failure(errorDescription: "Open the page in your browser first (Chrome, Safari, Edge, Arc, Brave…).")) }
        if bid == slack { return slackPage() }
        let b = browsers[bid]!
        func tab(_ what: String) -> String {
            b.safari ? "tell application id \"\(bid)\" to get \(what) of current tab of front window"
                     : "tell application id \"\(bid)\" to get \(what) of active tab of front window"
        }
        var err: NSDictionary?
        let url = NSAppleScript(source: tab("URL"))?.executeAndReturnError(&err).stringValue ?? ""
        if let err {
            if (err[NSAppleScript.errorNumber] as? Int) == -1743 {
                return .failure(Failure(errorDescription: "\(Edition.name) isn't allowed to see \(b.name)'s tab. Turn it on in System Settings › Privacy & Security › Automation › \(Edition.name) › \(b.name)."))
            }
            return .failure(Failure(errorDescription: "\(b.name) has no page open."))
        }
        var page = Page(url: url, app: b.name)
        err = nil
        page.title = NSAppleScript(source: tab(b.safari ? "name" : "title"))?.executeAndReturnError(&err).stringValue ?? ""
        // Selection and page text, when the browser allows JavaScript from Apple Events. Pages the edition
        // reads with its own tools only send the selection.
        let js = #"JSON.stringify({s:String(getSelection()||'').slice(0,4000),t:(document.body?document.body.innerText:'').slice(0,12000)})"#
            .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = b.safari ? "tell application id \"\(bid)\" to do JavaScript \"\(js)\" in current tab of front window"
                           : "tell application id \"\(bid)\" to execute active tab of front window javascript \"\(js)\""
        err = nil
        if let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue, err == nil,
           let o = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: String] {
            page.selection = (o["s"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            page.text = squeeze(o["t"] ?? "")
        }
        return .success(page)
    }

    /// Slack's desktop app can't be scripted: use what you copied there (a message link, or text).
    private static func slackPage() -> Result<Page, Error> {
        let pb = NSPasteboard.general
        let s = (pb.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard pb.changeCount != clipCount, !s.isEmpty else {
            return .failure(Failure(errorDescription: "In Slack, copy the message link (⋮ › Copy link) or the text first, then capture again."))
        }
        clipCount = pb.changeCount
        if s.hasPrefix("http"), !s.contains(" "), !s.contains("\n") { return .success(Page(url: s, title: "Slack message", app: "Slack")) }
        return .success(Page(title: "Copied from Slack", app: "Slack", selection: String(s.prefix(4000))))
    }

    /// When JavaScript is off, fetch the page and strip it to text. Signed-in pages come back as a login
    /// page, so this only helps with public ones.
    static func fetchText(_ page: Page, done: @escaping (Page) -> Void) {
        guard page.text.isEmpty, !Edition.readsWithTools(page.url), let u = URL(string: page.url), ["http", "https"].contains(u.scheme ?? "") else {
            done(page); return
        }
        URLSession.shared.dataTask(with: URLRequest(url: u, timeoutInterval: 15)) { data, _, _ in
            var p = page
            if let data, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                var t = html.replacingOccurrences(of: #"(?is)<(script|style|noscript|svg)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
                t = t.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                for (a, b) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
                    t = t.replacingOccurrences(of: a, with: b)
                }
                p.text = squeeze(t)
            }
            DispatchQueue.main.async { done(p) }
        }.resume()
    }

    private static func squeeze(_ s: String) -> String {
        let t = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\n\s*(\n\s*)+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(t.prefix(12000))
    }
}

// MARK: - Quick capture (a small floating box, from anywhere)

final class QuickPanel: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private var panel: NSPanel?
    private var field: NSTextField!
    private var kind: NSSegmentedControl!
    /// Called with ("idea" | "challenge", text).
    var onSubmit: ((String, String) -> Void)?

    func toggle() {
        if let p = panel, p.isVisible { p.orderOut(nil); return }
        if panel == nil { build() }
        field.stringValue = ""
        panel!.center()
        panel!.setFrameOrigin(NSPoint(x: panel!.frame.minX, y: panel!.frame.minY + 160))
        NSApp.activate(ignoringOtherApps: true)
        panel!.makeKeyAndOrderFront(nil)
        panel!.makeFirstResponder(field)
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 64),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .hudWindow, .utilityWindow],
                        backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.delegate = self
        let v = NSView(frame: p.contentRect(forFrameRect: p.frame))
        kind = NSSegmentedControl(labels: ["💡 Idea", "🧗 Challenge"], trackingMode: .selectOne, target: nil, action: nil)
        kind.selectedSegment = 0
        kind.controlSize = .regular
        kind.sizeToFit()
        kind.frame.origin = NSPoint(x: 14, y: (64 - kind.frame.height) / 2)
        field = NSTextField(frame: NSRect(x: kind.frame.maxX + 10, y: 18, width: 560 - kind.frame.maxX - 24, height: 28))
        field.placeholderString = "A thought, or something that keeps slowing you down…  ⏎ to add · Esc to close"
        field.font = .systemFont(ofSize: 15)
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.delegate = self
        v.addSubview(kind); v.addSubview(field)
        p.contentView = v
        panel = p
    }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let t = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { onSubmit?(kind.selectedSegment == 1 ? "challenge" : "idea", t) }
            panel?.orderOut(nil)
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { panel?.orderOut(nil); return true }
        if sel == #selector(NSResponder.insertTab(_:)) { kind.selectedSegment = 1 - kind.selectedSegment; return true }
        return false
    }
}

// MARK: - Notifications (background captures, finds and the weekly digest)

final class Notify: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notify()
    var onOpen: ((String) -> Void)?
    private var asked = false

    func start() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    /// `open` is a board script to run when the note is clicked ("" = just open the board).
    func post(_ title: String, _ body: String, open: String = "") {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNUserNotificationCenter.current()
        let send = {
            let n = UNMutableNotificationContent()
            n.title = title; n.body = body; n.userInfo = ["open": open]
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
        }
        if asked { send(); return }
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            self.asked = true
            if ok { send() }
        }
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        let open = r.notification.request.content.userInfo["open"] as? String ?? ""
        DispatchQueue.main.async { self.onOpen?(open) }
        done()
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner])
    }
}

// MARK: - Weekly digest

enum Digest {
    /// Monday, or a week since the last one: what you added and shipped, and the hottest open challenge.
    static func dueNote(now: Date = Date()) -> (String, String)? {
        guard Settings.digest else { return nil }
        let last = Settings.lastDigest
        let cal = Calendar.current
        let monday = cal.component(.weekday, from: now) == 2 && cal.component(.hour, from: now) >= 9
        guard let last else { Settings.lastDigest = now; return nil }   // first run: start the clock, say nothing
        guard (monday && !cal.isDate(last, inSameDayAs: now)) || now.timeIntervalSince(last) > 7 * 86400 else { return nil }
        Settings.lastDigest = now
        let week = now.addingTimeInterval(-7 * 86400)
        let s = Store.shared
        let added = s.ideas.filter { ($0.createdAt ?? .distantPast) > week && $0.stage != "suggested" }.count
        let shipped = s.ideas.filter { $0.stage == "shipped" && ($0.shippedDate ?? .distantPast) > week }.count
        let open = s.challenges.filter { $0.stage == "open" }
        let waiting = s.ideas.filter { $0.stage == "suggested" }.count + s.challenges.filter { $0.stage == "suggested" }.count
        var parts = ["\(added) idea\(added == 1 ? "" : "s") added", "\(shipped) shipped", "\(open.count) open challenge\(open.count == 1 ? "" : "s")"]
        if waiting > 0 { parts.append("\(waiting) suggestion\(waiting == 1 ? "" : "s") waiting") }
        var body = parts.joined(separator: " · ") + "."
        if let hot = open.max(by: { $0.heat < $1.heat }) { body += "\nHottest: \(hot.name)" }
        return ("\(Edition.symbol) Your week in \(Edition.name)", body)
    }
}

// MARK: - Update check (a newer release on the repo)

enum Updates {
    private(set) static var latest: (version: String, url: String)?
    private(set) static var checkedAt: Date?
    private(set) static var error = ""

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func check(force: Bool = false, done: (() -> Void)? = nil) {
        guard !Edition.releasesAPI.isEmpty, let u = URL(string: Edition.releasesAPI) else { done?(); return }
        if !force, let c = checkedAt, Date().timeIntervalSince(c) < 12 * 3600 { done?(); return }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let o = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                checkedAt = Date()
                if let tag = o?["tag_name"] as? String {
                    let v = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                    latest = newer(v, than: current) ? (v, o?["html_url"] as? String ?? Edition.repoURL + "/releases/latest") : nil
                    error = ""
                } else {
                    error = err == nil ? "Couldn't read the latest release (\((resp as? HTTPURLResponse)?.statusCode ?? 0))." : "You're offline."
                }
                done?()
            }
        }.resume()
    }

    static func state() -> [String: Any] {
        ["enabled": !Edition.releasesAPI.isEmpty, "current": current, "latest": latest?.version ?? "", "url": latest?.url ?? "",
         "checkedAt": checkedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "", "error": error]
    }
}

// MARK: - Local signals for 🔍 Find challenges

enum Signals {
    /// TODO/FIXME/HACK notes in your app folders and open issues on your public GitHub repos.
    /// Lines only, at most a few dozen; the AI groups them into challenges.
    static func collect(done: @escaping (String) -> Void) {
        let apps = Fleet.apps()
        DispatchQueue.global().async {
            var lines: [String] = []
            for a in apps where !(a["path"] ?? "").isEmpty {
                for hit in todos(in: a["path"]!).prefix(8) { lines.append("Code TODO in \(a["name"]!): \(hit)") }
                if lines.count > 60 { break }
            }
            let g = DispatchGroup()
            var issues: [String] = []
            let lock = NSLock()
            for a in apps {
                guard let repo = a["repo"], let u = URL(string: repo), u.host == "github.com",
                      let api = URL(string: "https://api.github.com/repos\(u.path)/issues?state=open&per_page=10") else { continue }
                g.enter()
                URLSession.shared.dataTask(with: URLRequest(url: api, timeoutInterval: 12)) { data, _, _ in
                    defer { g.leave() }
                    let rows = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
                    let got = rows.filter { $0["pull_request"] == nil }.compactMap { r -> String? in
                        guard let t = r["title"] as? String else { return nil }
                        return "Open GitHub issue on \(a["name"]!): \(t) — \(r["html_url"] as? String ?? "")"
                    }
                    lock.lock(); issues += got; lock.unlock()
                }.resume()
            }
            _ = g.wait(timeout: .now() + 15)
            lines += issues.prefix(40)
            DispatchQueue.main.async { done(lines.joined(separator: "\n")) }
        }
    }

    private static func todos(in dir: String) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // rg when it's there (fast, respects .gitignore), else grep.
        p.arguments = ["-lc", #"""
            export PATH="$HOME/.devbar/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
            if command -v rg >/dev/null; then rg -n --no-heading -m 3 -g '!*.min.*' -g '!node_modules' -g '!dist' -g '!build' -e '(TODO|FIXME|HACK)\b[:(]?' "$1"
            else grep -rnE -m 3 --exclude-dir={node_modules,dist,build,.git} '(TODO|FIXME|HACK)\b' "$1"; fi 2>/dev/null | head -40
            """#, "ideaforge", dir]
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self).split(separator: "\n").map { line in
            let s = String(line).replacingOccurrences(of: dir + "/", with: "")
            return String(s.prefix(200))
        }
    }
}
