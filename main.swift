// Idea Forge — a menu-bar backlog for the apps and agents you want to build next.
//
// Drop a raw thought in, the AI shapes it into a card (title, what it does, where it ships, build steps),
// and you drag cards across the board from 💭 Inbox to 🚀 Shipped. 🧗 Challenges hold the problems that
// keep slowing you down; ideas get sparked from them, and 📎 Capture pulls both from the page you're on.
// Everything lives only on this Mac, in ~/Library/Application Support/<Edition.folder>/ideas.json (or a
// folder you pick). The app watches that file, so anything else that edits it shows up at once.
//
// Shared core: the personal and work editions differ only in Edition.swift. AI.swift talks to the AI,
// Extras.swift holds hotkeys, page reading, quick capture, the digest and the update check.

import AppKit
import ServiceManagement
import WebKit

// MARK: - Settings

enum Settings {
    static let d = UserDefaults.standard
    /// "system" (follow macOS), "light" or "dark".
    static var appearance: String {
        get { let v = d.string(forKey: "appearance") ?? Edition.defaultAppearance
              return Edition.appearances.contains { $0.0 == v } ? v : Edition.defaultAppearance }
        set { d.set(newValue, forKey: "appearance") }
    }
    static func applyAppearance() {
        switch Edition.appearance(appearance) {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
    /// The model picker's value (Edition.model turns it into the model a task runs on).
    static var model: String {
        get { let v = d.string(forKey: "model") ?? Edition.defaultModel
              return Edition.models.contains { $0.0 == v } ? v : Edition.defaultModel }
        set { d.set(newValue, forKey: "model") }
    }
    /// Show the pending count next to the menu-bar icon.
    static var showCount: Bool {
        get { d.object(forKey: "showCount") as? Bool ?? true }
        set { d.set(newValue, forKey: "showCount") }
    }
    /// Shape new thoughts with the AI as soon as they're added.
    static var autoShape: Bool {
        get { d.object(forKey: "autoShape") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoShape") }
    }
    /// Suggest ideas for a challenge as soon as it's shaped.
    static var autoSpark: Bool {
        get { d.object(forKey: "autoSpark") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoSpark") }
    }
    /// Run 🔍 Find challenges once a day in the background.
    static var autoFind: Bool {
        get { d.object(forKey: "autoFind") as? Bool ?? false }
        set { d.set(newValue, forKey: "autoFind") }
    }
    static var lastFind: Date? {
        get { d.object(forKey: "lastFind") as? Date }
        set { d.set(newValue, forKey: "lastFind") }
    }
    /// A weekly notification: added, shipped, open challenges.
    static var digest: Bool {
        get { d.object(forKey: "digest") as? Bool ?? true }
        set { d.set(newValue, forKey: "digest") }
    }
    static var lastDigest: Date? {
        get { d.object(forKey: "lastDigest") as? Date }
        set { d.set(newValue, forKey: "lastDigest") }
    }
    /// 📎 Reading the page you're on, and the edition's connected systems. Off until you turn it on,
    /// and only in an edition that offers it.
    static var pageReading: Bool {
        get { Edition.pageReading && d.bool(forKey: "pageReading") }
        set { d.set(newValue, forKey: "pageReading") }
    }
    /// ⌃⌥N (quick capture) and, with page reading on, ⌃⌥I (capture the page) from anywhere.
    static var hotkeys: Bool {
        get { d.object(forKey: "hotkeys") as? Bool ?? true }
        set { d.set(newValue, forKey: "hotkeys") }
    }
    /// Use ⌃⌥⇧ instead, e.g. when another app already has ⌃⌥I.
    static var hotkeyShift: Bool {
        get { d.bool(forKey: "hotkeyShift") }
        set { d.set(newValue, forKey: "hotkeyShift") }
    }
    /// People you add yourself, for "Who can help" and "Added by".
    static var people: [String] {
        get { d.stringArray(forKey: "people") ?? [] }
        set { d.set(newValue, forKey: "people") }
    }
    /// Yours plus the edition's (e.g. a shared team list).
    static var allPeople: [String] {
        Array(Set(people + Edition.people())).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    /// A folder you picked for ideas.json (e.g. in iCloud Drive); nil = Application Support.
    static var dataDir: String? {
        get { Edition.dataFolderChoice ? d.string(forKey: "dataDir") : nil }
        set { d.set(newValue, forKey: "dataDir") }
    }
    /// The last release we told you about, so each one is announced once.
    static var toldUpdate: String {
        get { d.string(forKey: "toldUpdate") ?? "" }
        set { d.set(newValue, forKey: "toldUpdate") }
    }
}

// MARK: - Store (ideas.json, watched for outside edits)

private let isoDate: (String?) -> Date? = { s in
    guard let s else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}

/// Just what the menu needs. The board owns the full schema and saves the whole file.
struct Idea: Decodable {
    let id: String
    let n: Int?
    let title: String?
    let raw: String?
    let summary: String?
    let status: String?
    let priority: String?
    let type: String?
    let app: String?
    let home: String?
    let created: String?
    let shippedAt: String?
    /// The challenge it was sparked from.
    let challenge: String?
    /// The agent or app it belongs to, so related ideas sit together.
    let group: String?

    var name: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let r = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? "Untitled idea" : String(r.prefix(60))
    }
    /// inbox · shaped · building · shipped · parked · removed, or "suggested" (✨ waiting in the tray).
    var stage: String { status ?? "inbox" }
    /// Its group, else the app it's for.
    var groupName: String {
        let g = (group ?? "").trimmingCharacters(in: .whitespaces)
        return g.isEmpty ? (app ?? "").trimmingCharacters(in: .whitespaces) : g
    }
    var pending: Bool { ["inbox", "shaped", "building"].contains(stage) }
    var createdAt: Date? { isoDate(created) }
    var shippedDate: Date? { isoDate(shippedAt) }
}

/// A problem that keeps slowing you down; ideas are sparked from it.
struct Challenge: Decodable {
    let id: String
    let n: Int?
    let title: String?
    let detail: String?
    /// suggested · open · solved · dismissed
    let status: String?
    let impact: String?
    let often: String?
    let hits: Int?

    var name: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? String((detail ?? "Untitled challenge").prefix(60)) : t
    }
    var stage: String { status ?? "open" }
    /// How much it's worth solving: impact × how often × times hit.
    var heat: Int {
        let i = ["high": 3, "med": 2, "low": 1][impact ?? "med"] ?? 2
        let o = ["daily": 4, "weekly": 3, "monthly": 2, "rare": 1][often ?? "weekly"] ?? 2
        return i * o * max(1, hits ?? 1)
    }
}

final class Store {
    static let shared = Store()
    /// App Support/<folder>: settings files, the model cache, build scripts. Never moves.
    let support: URL
    /// Where ideas.json lives (support, or a folder you picked).
    private(set) var dir: URL
    var file: URL { dir.appendingPathComponent("ideas.json") }
    private(set) var data = Data()
    private(set) var ideas: [Idea] = []
    private(set) var challenges: [Challenge] = []
    var onChange: (() -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    /// `--demo` loads demo.json into memory and never writes — for screenshots.
    let demo = CommandLine.arguments.contains("--demo")

    init() {
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Edition.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        if let p = Settings.dataDir, FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
            dir = URL(fileURLWithPath: p, isDirectory: true)
        } else {
            dir = support
        }
        if demo, let u = Bundle.main.url(forResource: "demo", withExtension: "json"), let d = try? Data(contentsOf: u) {
            apply(d)
        } else {
            apply((try? Data(contentsOf: file)) ?? Data(#"{"version":1,"ideas":[],"challenges":[]}"#.utf8))
            watch()
        }
    }

    private func apply(_ d: Data) {
        struct File: Decodable { let ideas: [Idea]?; let challenges: [Challenge]? }
        data = d
        let f = try? JSONDecoder().decode(File.self, from: d)
        ideas = f?.ideas ?? []
        challenges = f?.challenges ?? []
    }

    /// Points the board at another folder (nil = back to Application Support). If the folder has no
    /// ideas.json yet, the current one is copied there, so nothing is lost; if it has one, that one is used.
    func move(to newDir: URL?) {
        let target = newDir ?? support
        guard target.standardizedFileURL != dir.standardizedFileURL else { return }
        let dest = target.appendingPathComponent("ideas.json")
        if !FileManager.default.fileExists(atPath: dest.path) { try? data.write(to: dest, options: .atomic) }
        Settings.dataDir = newDir?.path
        source?.cancel()
        source = nil
        dir = target
        apply((try? Data(contentsOf: file)) ?? data)
        if !demo { watch() }
        onChange?()
    }

    /// The board sends the whole document after every change.
    func save(_ json: Data) {
        guard json != data else { return }
        apply(json)
        guard !demo else { return }
        // Keep one rolling backup, so a bad save can always be undone by hand.
        let bak = dir.appendingPathComponent("ideas.backup.json")
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.removeItem(at: bak)
            try? FileManager.default.copyItem(at: file, to: bak)
        }
        try? json.write(to: file, options: .atomic)
    }

    /// Atomic writes replace the file, so watch the folder and re-read on any change.
    private func watch() {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        s.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let w = DispatchWorkItem { self?.reload() }
            self?.pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
        }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    private func reload() {
        guard let d = try? Data(contentsOf: file), d != data,
              (try? JSONSerialization.jsonObject(with: d)) != nil else { return }   // ignore half-written or broken edits
        apply(d)
        onChange?()
    }

    /// The pending list as a Markdown checklist (also used by `--checklist`).
    var checklist: String {
        let stages: [(String, String)] = [("building", "🔨 Building"), ("shaped", "📐 Shaped"), ("inbox", "💭 Inbox"), ("parked", "🧊 Parked")]
        let types = ["agent": "🤖 New agent", "enhancement": "✨ Enhancement", "fix": "🐞 Fix", "chore": "🧹 Chore"]
        let homes = ["personal": "🏠 Personal", "work": "💼 Work", "local": "🔒 Local"]
        let prio = ["high": "🔥", "med": "⚡", "low": "🌱"]
        let open = ideas.filter { $0.pending || $0.stage == "parked" }
        var out = ["## \(Edition.symbol) \(Edition.name) — \(ideas.filter { $0.pending }.count) pending"]
        for (key, label) in stages {
            let list = ideas.filter { $0.stage == key }
            guard !list.isEmpty else { continue }
            out.append("\n### \(label) (\(list.count))")
            for i in list {
                var tags = [types[i.type ?? ""], i.groupName.isEmpty ? nil : "▤ " + i.groupName, homes[i.home ?? ""], prio[i.priority ?? ""]].compactMap { $0 }
                if tags.isEmpty { tags = ["unshaped"] }
                let ref = i.n.map { "#\($0) " } ?? ""
                let sum = (i.summary ?? "").isEmpty ? "" : " — \(i.summary!)"
                out.append("- [ ] \(ref)**\(i.name)**\(sum) _(\(tags.joined(separator: " · ")))_")
            }
        }
        if open.isEmpty { out.append("\nNothing pending. Drop a thought in to get started.") }
        let hot = challenges.filter { $0.stage == "open" }.sorted { $0.heat > $1.heat }
        if !hot.isEmpty {
            out.append("\n### 🧗 Open challenges (\(hot.count))")
            for c in hot {
                let ideasFor = ideas.filter { $0.pending && $0.challenge == c.id }.compactMap { $0.n }.map { "#\($0)" }
                let tags = [c.impact.map { "\($0) impact" }, c.often, (c.hits ?? 1) > 1 ? "hit \(c.hits!)×" : nil,
                            ideasFor.isEmpty ? nil : "ideas " + ideasFor.joined(separator: " ")].compactMap { $0 }
                out.append("- [ ] C#\(c.n ?? 0) **\(c.name)**\(tags.isEmpty ? "" : " _(\(tags.joined(separator: " · ")))_")")
            }
        }
        let tray = ideas.filter { $0.stage == "suggested" }.count + challenges.filter { $0.stage == "suggested" }.count
        if tray > 0 { out.append("\n✨ \(tray) suggestion\(tray == 1 ? "" : "s") waiting in the tray.") }
        return out.joined(separator: "\n")
    }
}

// MARK: - Your apps (for "enhancement for …" and where an idea ships)

enum Fleet {
    /// Apps on this Mac: names from Nexus heartbeats when present, plus every git folder in ~ that builds an app.
    /// Each gets a home from its git origin — github.com = personal, any other host = work, none = local.
    static func apps() -> [[String: String]] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

        var folders: [String: (name: String, home: String, path: String, repo: String)] = [:]
        for name in (try? fm.contentsOfDirectory(atPath: home.path)) ?? [] where !name.hasPrefix(".") {
            let dir = home.appendingPathComponent(name)
            let looksLikeApp = ["build.sh", "package.json", "app/build.sh", "mac/build.sh"].contains {
                fm.fileExists(atPath: dir.appendingPathComponent($0).path)
            }
            guard looksLikeApp else { continue }
            let o = origin(dir.appendingPathComponent(".git/config"))
            folders[key(name)] = (name, o.home, dir.path, o.repo)
        }

        var out: [String: (home: String, path: String, repo: String)] = [:]
        let beats = home.appendingPathComponent(".nexus/heartbeats")
        for f in (try? fm.contentsOfDirectory(at: beats, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" {
            guard !f.lastPathComponent.hasPrefix("com.test."),
                  let d = try? Data(contentsOf: f),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let n = o["name"] as? String, !n.isEmpty else { continue }
            if let f = folders.removeValue(forKey: key(n)) { out[n] = (f.home, f.path, f.repo) } else if out[n] == nil { out[n] = ("", "", "") }
        }
        for (_, f) in folders { out[f.name] = (f.home, f.path, f.repo) }
        return out.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { ["name": $0, "home": out[$0]?.home ?? "", "path": out[$0]?.path ?? "", "repo": out[$0]?.repo ?? ""] }
    }

    /// Home from the git origin, plus the repo's web page ("https://host/owner/repo") for "Open as issue".
    private static func origin(_ config: URL) -> (home: String, repo: String) {
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return ("local", "") }
        var inOrigin = false
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { inOrigin = t == #"[remote "origin"]"# ; continue }
            if inOrigin, t.hasPrefix("url") {
                return (t.contains("github.com") ? "personal" : "work", webURL(t.components(separatedBy: "=").dropFirst().joined(separator: "=")))
            }
        }
        return ("local", "")
    }

    /// git@host:owner/repo.git, ssh://git@host/owner/repo, https://user@host/owner/repo.git → https://host/owner/repo
    private static func webURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(".git") { s.removeLast(4) }
        if let m = s.range(of: #"^[\w.-]+@([^:/]+):(.+)$"#, options: .regularExpression), m.lowerBound == s.startIndex {
            let host = s.components(separatedBy: "@")[1].components(separatedBy: ":")[0]
            return "https://\(host)/" + s.components(separatedBy: ":").dropFirst().joined(separator: ":")
        }
        guard let u = URL(string: s), let host = u.host, u.path.count > 1 else { return "" }
        return "https://\(host)\(u.path)"
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let board = Board()
    let quick = QuickPanel()
    /// Background jobs running (page reads, finds): the menu-bar title shows "…" while any are.
    var working = 0 { didSet { updateTitle() } }
    private var tick: Timer?

    /// A build left running would carry on with nobody to report to, so quitting stops it.
    func applicationWillTerminate(_ n: Notification) { AutoBuild.stopAll() }

    func applicationDidFinishLaunching(_ n: Notification) {
        Settings.applyAppearance()
        installEditMenu()
        let store = Store.shared
        Edition.setUp { [weak self] in
            Settings.applyAppearance()
            self?.board.push()
        }
        NexusBeacon.start(name: Edition.name) {
            let ideas = store.ideas
            let building = ideas.filter { $0.stage == "building" }.count
            let open = store.challenges.filter { $0.stage == "open" }.count
            return ("ok", "\(ideas.filter { $0.pending }.count) pending · \(building) building · \(open) challenges")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        NexusBeacon.attach(item)   // lets the app live in its parent's (Nexus or Citadel) menu
        Edition.started()
        item.button?.toolTip = "\(Edition.name) — your next apps and agents"
        updateTitle()
        store.onChange = { [weak self] in
            self?.updateTitle()
            self?.board.push()
            NexusBeacon.beat()
        }
        PageReader.start()
        Notify.shared.start()
        Notify.shared.onOpen = { [weak self] script in self?.board.show(then: script.isEmpty ? nil : script) }
        quick.onSubmit = { [weak self] kind, text in
            self?.board.ensure(then: "forge.quick(\(Board.js(kind)), \(Board.js(text)))")
        }
        registerHotkeys()
        if CommandLine.arguments.contains("--board") || store.demo { board.show() }
        // Hourly: fresh model lists, the weekly digest, the daily find, the update check.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.hourly() }
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.hourly() }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    func registerHotkeys() {
        Hotkeys.register(page: { [weak self] in self?.capturePage(fromBoard: false) },
                         quick: { [weak self] in self?.quick.toggle() })
    }

    func hourly() {
        guard !Store.shared.demo else { return }
        if AI.modelsStale { AI.refreshModels { [weak self] _ in self?.board.push() } }
        if let (title, body) = Digest.dueNote() { Notify.shared.post(title, body) }
        if Settings.autoFind, AI.ready, Date().timeIntervalSince(Settings.lastFind ?? .distantPast) > 22 * 3600 {
            findChallenges(background: true)
        }
        Updates.check { [weak self] in
            self?.board.push()
            if let l = Updates.latest, Settings.toldUpdate != l.version {
                Settings.toldUpdate = l.version
                Notify.shared.post("\(Edition.name) \(l.version) is out", "You have \(Updates.current). Click to see what's new.",
                                   open: "forge.open(\(Board.js(l.url)))")
            }
        }
    }

    func updateTitle() {
        let count = Store.shared.ideas.filter { $0.pending }.count
        let base = Settings.showCount && count > 0 ? "\(Edition.symbol) \(count)" : Edition.symbol
        item.button?.title = working > 0 ? base + " …" : base
    }

    // MARK: Background AI jobs (the board doesn't need to be open)

    /// 📎 Reads the page you're on, asks the AI for challenges and ideas in it, and adds them to the
    /// ✨ Suggested tray. From the hotkey or menu, the result comes back as a notification.
    func capturePage(fromBoard: Bool) {
        func fail(_ msg: String) {
            if fromBoard { board.run("forge.pageRead(null, \(Board.js(msg)), false)") }
            else { NSSound.beep(); Notify.shared.post("📎 Couldn't capture the page", msg) }
        }
        guard Settings.pageReading else { fail("Page reading is off. Turn it on in Settings first."); return }
        if let why = AI.problem() { fail(why); return }
        switch PageReader.read() {
        case .failure(let e): fail(e.localizedDescription)
        case .success(let page):
            working += 1
            if !fromBoard { Notify.shared.post("📎 Reading the page…", page.title.isEmpty ? page.app : page.title) }
            let started = Date()
            PageReader.fetchText(page) { page in
                AI.readPage(page) { r in
                    self.working -= 1
                    let bg = !fromBoard || !self.board.visible
                    let src: [String: Any] = ["url": page.url, "title": page.title, "app": page.app,
                                              "secs": Int(Date().timeIntervalSince(started))]
                    var payload = src
                    switch r {
                    case .success(let s):
                        payload["result"] = s
                        self.board.ensure(then: "forge.pageRead(\(Board.json(payload)), null, \(bg))")
                    case .failure(let e):
                        if fromBoard { self.board.run("forge.pageRead(null, \(Board.js(e.localizedDescription)), false)") }
                        else { Notify.shared.post("📎 Couldn't read the page", e.localizedDescription) }
                    }
                }
            }
        }
    }

    /// 🔍 Looks through local signals (and, in an edition with tools, its connected systems) for recurring
    /// problems, and adds them as suggested challenges.
    func findChallenges(background: Bool) {
        if let why = AI.problem() {
            if background { return }
            board.run("forge.found(null, \(Board.js(why)), false)"); return
        }
        working += 1
        Settings.lastFind = Date()
        Signals.collect { signals in
            AI.find(signals: signals) { r in
                self.working -= 1
                let bg = background || !self.board.visible
                switch r {
                case .success(let s): self.board.ensure(then: "forge.found(\(Board.json(s)), null, \(bg))")
                case .failure(let e):
                    if bg { if !background { Notify.shared.post("🔍 Find challenges didn't finish", e.localizedDescription) } }
                    else { self.board.run("forge.found(null, \(Board.js(e.localizedDescription)), false)") }
                }
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = Store.shared
        let ideas = store.ideas
        if let l = Updates.latest { menu.addItem(action("⬆️  Update to \(Edition.name) \(l.version)…", #selector(openUpdate))); menu.addItem(.separator()) }
        menu.addItem(action("Open Board", #selector(openBoard), "b"))
        menu.addItem(action("Capture a Thought…", #selector(capture), "n"))
        let page = action("📎  Capture This Page", #selector(capturePageMenu))
        let qc = action("Quick Capture…", #selector(quickCapture))
        if !Hotkeys.label.isEmpty {
            let mods: NSEvent.ModifierFlags = Hotkeys.label.contains("⇧") ? [.control, .option, .shift] : [.control, .option]
            page.keyEquivalent = "i"; page.keyEquivalentModifierMask = mods
            qc.keyEquivalent = "n"; qc.keyEquivalentModifierMask = mods
        }
        if Settings.pageReading { menu.addItem(page) }
        menu.addItem(qc)
        menu.addItem(action("Add Clipboard as Idea", #selector(captureClipboard)))
        menu.addItem(.separator())

        let order = ["building": 0, "shaped": 1, "inbox": 2]
        let rank = ["high": 0, "med": 1, "low": 2]
        let next = ideas.filter { $0.pending }.sorted {
            (order[$0.stage]!, rank[$0.priority ?? "med"] ?? 1) < (order[$1.stage]!, rank[$1.priority ?? "med"] ?? 1)
        }
        if next.isEmpty {
            menu.addItem(info("Nothing pending — capture a thought"))
        } else {
            menu.addItem(groupHeader("Up next"))
            let icon = ["building": "🔨", "shaped": "📐", "inbox": "💭"]
            for i in next.prefix(7) {
                let t = i.name.count > 52 ? String(i.name.prefix(51)) + "…" : i.name
                let it = action("\(icon[i.stage]!)  \(t)", #selector(openIdea(_:)))
                it.representedObject = i.id
                menu.addItem(it)
            }
            if next.count > 7 { menu.addItem(info("+ \(next.count - 7) more on the board")) }
        }
        let open = store.challenges.filter { $0.stage == "open" }.count
        let tray = ideas.filter { $0.stage == "suggested" }.count + store.challenges.filter { $0.stage == "suggested" }.count
        if open > 0 || tray > 0 { menu.addItem(.separator()) }
        if open > 0 { menu.addItem(action("🧗  \(open) open challenge\(open == 1 ? "" : "s")", #selector(openChallenges))) }
        if tray > 0 { menu.addItem(action("✨  \(tray) suggestion\(tray == 1 ? "" : "s") to review", #selector(openTray))) }
        menu.addItem(.separator())
        if !next.isEmpty { menu.addItem(action("🎯  What Should I Build Next?", #selector(whatNext))) }
        menu.addItem(action(working > 0 ? "🔍  Finding challenges…" : "🔍  Find Challenges", #selector(findMenu)))
        menu.addItem(action("Copy Pending Checklist", #selector(copyChecklist)))
        menu.addItem(settingsItem())
        menu.addItem(action("Help & Source on \(Edition.repoLabel)", #selector(openHelp)))
        if let i = Edition.menuItem() { menu.addItem(i) }
        menu.addItem(.separator())
        menu.addItem(action("Quit \(Edition.name)", #selector(quit), "q"))
    }

    func settingsItem() -> NSMenuItem {
        let it = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let m = NSMenu()
        let p = AI.current
        m.addItem(groupHeader("AI"))
        m.addItem(info("\(p.name.components(separatedBy: " · ")[0]) · \(AI.runModel(p))" + (AI.ready ? "" : "  ⚠️")))
        if p.id == "claude-code" && Edition.models.count <= 4 {
            m.addItem(segmentRow("Claude model", Edition.models.map { App.short($0.1) }, Edition.models.firstIndex { $0.0 == Settings.model } ?? 0, #selector(segModel(_:))))
        }
        m.addItem(action("AI & Models…", #selector(openAISettings)))
        m.addItem(.separator())
        m.addItem(groupHeader("Automation"))
        m.addItem(switchRow("Shape new thoughts", Settings.autoShape, #selector(switchShape(_:))))
        m.addItem(switchRow("Suggest ideas for challenges", Settings.autoSpark, #selector(switchSpark(_:))))
        m.addItem(switchRow("Find challenges daily", Settings.autoFind, #selector(switchFind(_:))))
        m.addItem(switchRow("Weekly digest", Settings.digest, #selector(switchDigest(_:))))
        if Edition.pageReading {
            m.addItem(switchRow("📎 Read pages · \(Edition.toolsLabel)", Settings.pageReading, #selector(switchPages(_:))))
        }
        let keys = Hotkeys.label.isEmpty ? (Settings.hotkeyShift ? "⌃⌥⇧" : "⌃⌥") : Hotkeys.label
        m.addItem(switchRow(Settings.pageReading ? "Hotkeys \(keys)I · N" : "Hotkey \(keys)N", Settings.hotkeys, #selector(switchHotkeys(_:))))
        m.addItem(.separator())
        m.addItem(groupHeader("General"))
        m.addItem(switchRow("Show pending count", Settings.showCount, #selector(switchCount(_:))))
        m.addItem(switchRow("Launch at login", SMAppService.mainApp.status == .enabled, #selector(switchLogin(_:))))
        m.addItem(segmentRow("Appearance", Edition.appearances.map { App.short($0.1) }, Edition.appearances.firstIndex { $0.0 == Settings.appearance } ?? 0, #selector(segAppearance(_:))))
        m.addItem(.separator())
        m.addItem(action("Show Ideas File in Finder", #selector(revealFile)))
        it.submenu = m
        return it
    }

    // MARK: Settings rows (grouped, with switches and segmented controls)

    static let rowWidth: CGFloat = 300

    /// A picker label short enough for a menu segment: "Haiku · fast" → "Haiku", "Citadel's choice — Sonnet" → "Citadel".
    static func short(_ label: String) -> String {
        let s = label.components(separatedBy: " · ")[0].components(separatedBy: " — ")[0].components(separatedBy: " (")[0]
        return s.replacingOccurrences(of: "Citadel's choice", with: "Citadel")
    }

    func groupHeader(_ title: String) -> NSMenuItem {
        let it = NSMenuItem()
        it.isEnabled = false
        it.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.6])
        return it
    }

    func rowLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .menuFont(ofSize: 13)
        l.textColor = .labelColor
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    func switchRow(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: App.rowWidth, height: 30))
        let l = rowLabel(title); l.frame = NSRect(x: 14, y: 6, width: App.rowWidth - 82, height: 18)
        let sw = NSSwitch(); sw.controlSize = .small; sw.state = on ? .on : .off
        sw.target = self; sw.action = sel
        sw.sizeToFit(); sw.frame.origin = NSPoint(x: App.rowWidth - sw.frame.width - 14, y: (30 - sw.frame.height) / 2)
        v.addSubview(l); v.addSubview(sw)
        let it = NSMenuItem(); it.view = v
        return it
    }

    func segmentRow(_ title: String, _ labels: [String], _ selected: Int, _ sel: Selector) -> NSMenuItem {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: App.rowWidth, height: 52))
        let l = rowLabel(title); l.frame = NSRect(x: 14, y: 31, width: App.rowWidth - 28, height: 16)
        let seg = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: sel)
        seg.controlSize = .small; seg.segmentStyle = .rounded; seg.selectedSegment = selected
        seg.frame = NSRect(x: 14, y: 5, width: App.rowWidth - 28, height: 22)
        v.addSubview(l); v.addSubview(seg)
        let it = NSMenuItem(); it.view = v
        return it
    }

    @objc func switchShape(_ s: NSSwitch) { Settings.autoShape = s.state == .on; board.push() }
    @objc func switchSpark(_ s: NSSwitch) { Settings.autoSpark = s.state == .on; board.push() }
    @objc func switchFind(_ s: NSSwitch) { Settings.autoFind = s.state == .on; board.push() }
    @objc func switchDigest(_ s: NSSwitch) { Settings.digest = s.state == .on; board.push() }
    @objc func switchPages(_ s: NSSwitch) { setPageReading(s.state == .on) }
    func setPageReading(_ on: Bool) {
        Settings.pageReading = on
        if on { PageReader.start() } else { PageReader.stop() }
        registerHotkeys()
        board.push()
    }
    @objc func switchHotkeys(_ s: NSSwitch) { Settings.hotkeys = s.state == .on; registerHotkeys(); board.push() }
    @objc func switchCount(_ s: NSSwitch) { Settings.showCount = s.state == .on; updateTitle() }
    @objc func switchLogin(_ s: NSSwitch) {
        toggleLogin()
        s.state = SMAppService.mainApp.status == .enabled ? .on : .off   // snap back if it failed
    }
    @objc func segModel(_ s: NSSegmentedControl) {
        let opts = Edition.models.map { $0.0 }
        guard opts.indices.contains(s.selectedSegment) else { return }
        Settings.model = opts[s.selectedSegment]; Edition.modelChanged(); board.push()
    }
    @objc func segAppearance(_ s: NSSegmentedControl) {
        let opts = Edition.appearances.map { $0.0 }
        guard opts.indices.contains(s.selectedSegment) else { return }
        Settings.appearance = opts[s.selectedSegment]
        Settings.applyAppearance()
        board.push()
    }

    func info(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    func action(_ title: String, _ sel: Selector, _ key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        return it
    }

    // MARK: Actions

    @objc func openBoard() { board.show() }
    @objc func capture() { board.show(then: "forge.focusCapture()") }
    @objc func capturePageMenu() { capturePage(fromBoard: false) }
    @objc func quickCapture() { quick.toggle() }
    @objc func openIdea(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String else { return }
        board.show(then: "forge.openCard(\(Board.js(id)))")
    }
    @objc func captureClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { NSSound.beep(); return }
        board.show(then: "forge.capture(\(Board.js(text)))")
    }
    @objc func openChallenges() { board.show(then: "forge.tab('challenges')") }
    @objc func openTray() { board.show(then: "forge.showTray()") }
    @objc func openAISettings() { board.show(then: "forge.openSettings()") }
    @objc func openUpdate() { if let l = Updates.latest, let u = URL(string: l.url) { NSWorkspace.shared.open(u) } }
    @objc func whatNext() { board.show(then: "forge.whatNext()") }
    @objc func findMenu() { if working == 0 { findChallenges(background: false); board.show(then: "forge.tab('challenges')") } }
    @objc func copyChecklist() { Board.copy(Store.shared.checklist) }
    @objc func openHelp() { NSWorkspace.shared.open(URL(string: Edition.repoURL + "#readme")!) }
    @objc func revealFile() { NSWorkspace.shared.activateFileViewerSelecting([Store.shared.file]) }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change Launch at Login"
            a.informativeText = "\(error.localizedDescription)\n\nMove \(Edition.name) to the Applications folder and try again, or add it in System Settings → General → Login Items."
            a.runModal()
        }
    }

    /// Menu-bar apps have no main menu, so ⌘C / ⌘V would not work in the board's text fields.
    func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let am = NSMenu(); am.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appItem.submenu = am
        let editItem = NSMenuItem(); main.addItem(editItem)
        let em = NSMenu(title: "Edit")
        em.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        em.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        em.addItem(.separator())
        em.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        em.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        em.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        em.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = em
        NSApp.mainMenu = main
    }
}

// MARK: - Board window (board.html in a web view)

final class Board: NSObject, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var window: NSWindow?
    var web: WKWebView?
    var ready = false
    var queued: [String] = []
    var visible: Bool { window?.isVisible ?? false }

    static func js(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(decoding: d, as: UTF8.self) + "[0]"
    }
    static func json(_ o: Any) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: o)) ?? Data("null".utf8), as: UTF8.self)
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// Loads the board without showing it, so background captures can add to it.
    func ensure(then script: String? = nil) {
        if window == nil {
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "forge")
            let w = WKWebView(frame: .zero, configuration: cfg)
            w.navigationDelegate = self
            w.setValue(false, forKey: "drawsBackground")
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1340, height: 860),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
            win.title = Edition.name
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.minSize = NSSize(width: 960, height: 600)
            win.backgroundColor = NSColor(name: nil) { a in
                a.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? NSColor(red: 0.957, green: 0.961, blue: 0.976, alpha: 1)
                                                                : NSColor(red: 0.051, green: 0.059, blue: 0.082, alpha: 1)
            }
            // The page runs under the title bar, and a web view never lets a click move its window.
            // A strip over the page's empty top band does.
            let root = NSView()
            w.frame = root.bounds
            w.autoresizingMask = [.width, .height]
            root.addSubview(w)
            let strip = DragStrip(frame: NSRect(x: 0, y: 0, width: 1340, height: DragStrip.height))
            strip.autoresizingMask = [.width, .minYMargin]
            root.addSubview(strip)
            win.contentView = root
            strip.frame.origin.y = root.bounds.height - DragStrip.height
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.setFrameAutosaveName(Edition.folder + "Board")
            if !win.setFrameUsingName(Edition.folder + "Board") { win.center() }
            window = win
            web = w
            ready = false
            if let u = Bundle.main.url(forResource: "board", withExtension: "html") {
                w.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent())
            }
        }
        if let s = script { run(s) }
    }

    func show(then script: String? = nil) {
        ensure(then: script)
        NSApp.setActivationPolicy(.regular)   // Dock icon + ⌘-Tab while the window is open
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func run(_ s: String) {
        if ready { web?.evaluateJavaScript(s, completionHandler: nil) } else { queued.append(s) }
    }

    /// Sends the whole state to the page: ideas and challenges, your apps, the AI, settings.
    func push() {
        guard web != nil else { return }
        let store = Store.shared
        let ideas = (try? JSONSerialization.jsonObject(with: store.data)) ?? ["version": 1, "ideas": [], "challenges": []]
        let state: [String: Any] = [
            "doc": ideas,
            "apps": Fleet.apps(),
            "people": Settings.allPeople,
            "ai": AI.state(),
            "updates": Updates.state(),
            "hotkeys": Hotkeys.label,
            "edition": ["name": Edition.name, "symbol": Edition.symbol, "flavor": Edition.flavor,
                        "repo": Edition.repoURL, "repoLabel": Edition.repoLabel, "tools": Edition.toolsLabel,
                        "dataFolder": Edition.dataFolderChoice, "pageReading": Edition.pageReading, "appearances": Edition.appearances.map { [$0.0, $0.1] }],
            "demo": store.demo,
            "file": store.file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
            "customFolder": Settings.dataDir != nil,
            "settings": ["appearance": Settings.appearance, "autoShape": Settings.autoShape, "autoSpark": Settings.autoSpark,
                         "autoFind": Settings.autoFind, "digest": Settings.digest, "hotkeys": Settings.hotkeys,
                         "hotkeyShift": Settings.hotkeyShift, "people": Settings.people, "pageReading": Settings.pageReading,
                         "lastFind": Settings.lastFind.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                         "showCount": Settings.showCount, "login": SMAppService.mainApp.status == .enabled],
            "version": Updates.current,
            "autoRunning": AutoBuild.running,
        ]
        web?.evaluateJavaScript("forge.load(\(Board.json(state)))", completionHandler: nil)
    }

    /// Runs an AI call and hands the result to `forge.<fn>(<id>, result, error)`.
    private func reply(_ fn: String, _ id: String?, _ r: Result<Any, Error>) {
        let head = id.map { Board.js($0) + ", " } ?? ""
        switch r {
        case .success(let v): run("forge.\(fn)(\(head)\(Board.json(v)), null)")
        case .failure(let e): run("forge.\(fn)(\(head)null, \(Board.js(e.localizedDescription)))")
        }
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let msg = m.body as? [String: Any], let cmd = msg["cmd"] as? String else { return }
        Edition.boardAction(cmd)
        let app = NSApp.delegate as? App
        let id = msg["id"] as? String
        switch cmd {
        case "ready":
            ready = true
            push()
            queued.forEach { web?.evaluateJavaScript($0, completionHandler: nil) }
            queued = []
        case "save":
            guard let doc = msg["doc"], let d = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) else { return }
            Store.shared.save(d)
            app?.updateTitle()
            NexusBeacon.beat()
        case "shape":
            guard let id, let text = msg["text"] as? String else { return }
            AI.shape(text, id: id, single: msg["single"] as? Bool ?? false) { [weak self] r in self?.reply("shaped", id, r.map { $0 }) }
        case "shapeChallenge":
            guard let id, let text = msg["text"] as? String else { return }
            AI.shapeChallenge(text, id: id) { [weak self] r in self?.reply("challengeShaped", id, r.map { $0 }) }
        case "spark":
            guard let id, let text = msg["text"] as? String else { return }
            AI.spark(text) { [weak self] r in self?.reply("sparked", id, r.map { $0 }) }
        case "ask":
            guard let id, let brief = msg["brief"] as? String, let q = msg["q"] as? String else { return }
            AI.ask(brief: brief, question: q, id: id) { [weak self] r in self?.reply("answered", id, r.map { $0 }) }
        case "next":
            guard let board = msg["board"] as? String else { return }
            AI.whatNext(board) { [weak self] r in self?.reply("nextPicks", nil, r.map { $0 }) }
        case "place":
            guard let list = msg["list"] as? String else { return }
            AI.place(list) { [weak self] r in self?.reply("placed", nil, r.map { $0 }) }
        case "capturePage":
            app?.capturePage(fromBoard: true)
        case "findChallenges":
            app?.findChallenges(background: false)
        case "build":
            guard let brief = msg["brief"] as? String, let n = msg["n"] as? Int else { return }
            let ok = AI.build(brief: brief, app: msg["app"] as? String ?? "", number: n, tool: msg["tool"] as? String ?? "claude")
            run("forge.built(\(ok))")
        case "autoBuild":
            // ⚡ Auto-build: Claude Code builds the card in the background; the card moves when it reports back.
            guard let id, let brief = msg["brief"] as? String, let n = msg["n"] as? Int else { return }
            let r = AutoBuild.start(id: id, n: n, brief: brief, app: msg["app"] as? String ?? "", name: msg["name"] as? String ?? "",
                                    steps: msg["steps"] as? [String] ?? [], dir: msg["dir"] as? String ?? "",
                progress: { [weak self] line in
                    guard let self, self.ready else { return }
                    self.run("forge.autoProgress(\(Board.js(id)), \(Board.js(line)))")
                },
                done: { [weak self] result in
                    guard let self else { return }
                    app?.working -= 1
                    self.ensure(then: "forge.autoBuilt(\(Board.js(id)), \(Board.json(result)), \(!self.visible))")
                })
            switch r {
            case .success(let info):
                app?.working += 1
                run("forge.autoStarted(\(Board.js(id)), null, \(Board.json(info)))")
            case .failure(let e):
                run("forge.autoStarted(\(Board.js(id)), \(Board.js(e.localizedDescription)), null)")
            }
        case "autoStop":
            if let id { AutoBuild.stop(id) }
        case "autoResume":
            guard let s = msg["session"] as? String, let dir = msg["dir"] as? String, let n = msg["n"] as? Int else { return }
            run("forge.built(\(AI.resume(session: s, dir: dir, number: n)))")
        case "copy":
            if let t = msg["text"] as? String { Board.copy(t) }
        case "notify":
            Notify.shared.post(msg["title"] as? String ?? Edition.name, msg["body"] as? String ?? "", open: msg["open"] as? String ?? "")
        case "ai":
            // Provider, model, server address and keys.
            let p = AI.all.first { $0.id == (msg["provider"] as? String ?? AI.current.id) } ?? AI.current
            switch msg["key"] as? String ?? "" {
            case "provider":
                AI.setProvider(p.id)
                if AI.modelsStale { AI.refreshModels { [weak self] _ in self?.push() } }
            case "model": if let v = msg["value"] as? String { AI.setModel(v, for: p) }
            case "base":
                AI.setBase(msg["value"] as? String ?? "", for: p)
                AI.refreshModels(p) { [weak self] _ in self?.push() }
            case "apiKey":
                AI.setKey(msg["value"] as? String, for: p)
                if AI.hasKey(p) { AI.refreshModels(p) { [weak self] _ in self?.push() } }
            case "refresh":
                AI.refreshModels(p) { [weak self] err in
                    self?.push()
                    self?.run("forge.toast(\(Board.js(err.map { "↻ " + $0 } ?? "↻ Model list updated")))")
                }
            case "test":
                AI.test { [weak self] ok, text in self?.run("forge.tested(\(ok), \(Board.js(text)))") }
                return
            default: break
            }
            push()
        case "setting":
            guard let k = msg["key"] as? String else { return }
            let v = msg["value"]
            switch k {
            case "appearance": if let v = v as? String { Settings.appearance = v; Settings.applyAppearance() }
            case "model": if let v = v as? String { Settings.model = v; Edition.modelChanged() }
            case "autoShape": if let v = v as? Bool { Settings.autoShape = v }
            case "autoSpark": if let v = v as? Bool { Settings.autoSpark = v }
            case "autoFind": if let v = v as? Bool { Settings.autoFind = v }
            case "digest": if let v = v as? Bool { Settings.digest = v }
            case "pageReading": if let v = v as? Bool { app?.setPageReading(v); return }
            case "hotkeys": if let v = v as? Bool { Settings.hotkeys = v; app?.registerHotkeys() }
            case "hotkeyShift": if let v = v as? Bool { Settings.hotkeyShift = v; app?.registerHotkeys() }
            case "people": if let v = v as? [String] { Settings.people = v.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            case "showCount": if let v = v as? Bool { Settings.showCount = v; app?.updateTitle() }
            case "login": app?.toggleLogin()
            default: break
            }
            push()
        case "chooseFolder":
            guard Edition.dataFolderChoice else { return }
            if msg["reset"] as? Bool == true { Store.shared.move(to: nil); return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            panel.prompt = "Use This Folder"
            panel.message = "Pick a folder for ideas.json — for example in iCloud Drive or Dropbox, to sync it between Macs."
            panel.beginSheetModal(for: window!) { r in
                if r == .OK, let u = panel.url { Store.shared.move(to: u) }
            }
        case "checkUpdate":
            Updates.check(force: true) { [weak self] in
                self?.push()
                self?.run("forge.toast(\(Board.js(Updates.latest.map { "⬆️ \($0.version) is out" } ?? (Updates.error.isEmpty ? "✓ You have the latest version" : Updates.error))))")
            }
        case "reveal":
            NSWorkspace.shared.activateFileViewerSelecting([Store.shared.file])
        case "open":
            if let s = msg["url"] as? String, let u = URL(string: s), ["https", "http"].contains(u.scheme ?? "") { NSWorkspace.shared.open(u) }
        default: break
        }
    }

    func windowWillClose(_ n: Notification) { NSApp.setActivationPolicy(.accessory) }

    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = a.request.url, a.navigationType == .linkActivated, u.scheme != "file" {
            NSWorkspace.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { ready = false }
}

/// Takes drags (double-click zooms) across the page's top band, leaving the traffic lights alone.
final class DragStrip: NSView {
    static let height: CGFloat = 26
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sup = superview else { return nil }
        let p = convert(point, from: sup)
        guard bounds.contains(p), p.x > 78 else { return nil }
        return self
    }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 {
            let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
            if action == "Minimize" { window?.performMiniaturize(nil) } else if action != "None" { window?.zoom(nil) }
            return
        }
        window?.performDrag(with: e)
    }
}

// MARK: - Main

if CommandLine.arguments.contains("--checklist") {
    print(Store.shared.checklist)
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
