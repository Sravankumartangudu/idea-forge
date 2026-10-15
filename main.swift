// Idea Forge — a menu-bar backlog for the apps and agents you want to build next.
//
// Drop a raw thought in, Claude shapes it into a card (title, what it does, where it ships, build steps),
// and you drag cards across the board from 💭 Inbox to 🚀 Shipped. Ideas live only on this Mac, in
// ~/Library/Application Support/<Edition.folder>/ideas.json. The app watches that file, so anything else
// that edits it (a script, a Claude Code session) shows up on the board at once.
//
// Shared core: the personal and work editions differ only in Edition.swift.

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
    /// Shape new thoughts with Claude as soon as they're added.
    static var autoShape: Bool {
        get { d.object(forKey: "autoShape") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoShape") }
    }
}

// MARK: - Store (ideas.json, watched for outside edits)

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

    var name: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let r = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? "Untitled idea" : String(r.prefix(60))
    }
    var stage: String { status ?? "inbox" }
    var pending: Bool { ["inbox", "shaped", "building"].contains(stage) }
}

final class Store {
    static let shared = Store()
    let dir: URL
    let file: URL
    private(set) var data = Data()
    private(set) var ideas: [Idea] = []
    var onChange: (() -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    /// `--demo` loads demo.json into memory and never writes — for screenshots.
    let demo = CommandLine.arguments.contains("--demo")

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Edition.folder, isDirectory: true)
        file = dir.appendingPathComponent("ideas.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if demo, let u = Bundle.main.url(forResource: "demo", withExtension: "json"), let d = try? Data(contentsOf: u) {
            apply(d)
        } else {
            apply((try? Data(contentsOf: file)) ?? Data(#"{"version":1,"ideas":[]}"#.utf8))
            watch()
        }
    }

    private func apply(_ d: Data) {
        struct File: Decodable { let ideas: [Idea] }
        data = d
        ideas = (try? JSONDecoder().decode(File.self, from: d))?.ideas ?? []
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
                var tags = [types[i.type ?? ""], (i.app ?? "").isEmpty ? nil : i.app, homes[i.home ?? ""], prio[i.priority ?? ""]].compactMap { $0 }
                if tags.isEmpty { tags = ["unshaped"] }
                let ref = i.n.map { "#\($0) " } ?? ""
                let sum = (i.summary ?? "").isEmpty ? "" : " — \(i.summary!)"
                out.append("- [ ] \(ref)**\(i.name)**\(sum) _(\(tags.joined(separator: " · ")))_")
            }
        }
        if open.isEmpty { out.append("\nNothing pending. Drop a thought in to get started.") }
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

        var folders: [String: (name: String, home: String, path: String)] = [:]
        for name in (try? fm.contentsOfDirectory(atPath: home.path)) ?? [] where !name.hasPrefix(".") {
            let dir = home.appendingPathComponent(name)
            let looksLikeApp = ["build.sh", "package.json", "app/build.sh", "mac/build.sh"].contains {
                fm.fileExists(atPath: dir.appendingPathComponent($0).path)
            }
            guard looksLikeApp else { continue }
            folders[key(name)] = (name, originHome(dir.appendingPathComponent(".git/config")), dir.path)
        }

        var out: [String: (home: String, path: String)] = [:]
        let beats = home.appendingPathComponent(".nexus/heartbeats")
        for f in (try? fm.contentsOfDirectory(at: beats, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" {
            guard !f.lastPathComponent.hasPrefix("com.test."),
                  let d = try? Data(contentsOf: f),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let n = o["name"] as? String, !n.isEmpty else { continue }
            if let f = folders.removeValue(forKey: key(n)) { out[n] = (f.home, f.path) } else if out[n] == nil { out[n] = ("", "") }
        }
        for (_, f) in folders { out[f.name] = (f.home, f.path) }
        return out.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { ["name": $0, "home": out[$0]?.home ?? "", "path": out[$0]?.path ?? ""] }
    }

    private static func originHome(_ config: URL) -> String {
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return "local" }
        var inOrigin = false
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { inOrigin = t == #"[remote "origin"]"# ; continue }
            if inOrigin, t.hasPrefix("url") {
                return t.contains("github.com") ? "personal" : "work"
            }
        }
        return "local"
    }
}

// MARK: - Claude (the local `claude` CLI, one tool-less turn per task)

enum Claude {
    struct Failure: LocalizedError { let errorDescription: String? }

    static let available: Bool = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", #"export PATH="$HOME/.local/bin:$HOME/.devbar/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; command -v claude >/dev/null"#]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }()

    /// Copies only the auth keys from ~/.claude/settings.json: user settings are skipped
    /// (`--setting-sources project`) so no allow-list or hook from them can ride along.
    private static func authSettings() -> URL {
        let out = Store.shared.dir.appendingPathComponent("auth-settings.json")
        let user = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        var auth: [String: Any] = [:]
        if let d = try? Data(contentsOf: user), let all = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for k in ["apiKeyHelper", "env", "awsAuthRefresh", "awsCredentialExport", "forceLoginMethod"] { auth[k] = all[k] }
        }
        if let d = try? JSONSerialization.data(withJSONObject: auth) {
            try? d.write(to: out, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: out.path)
        }
        return out
    }

    /// Runs one turn with no tools and a JSON schema. `done` gets the structured output (or an error) on the main queue.
    static func run(task: String, system: String, schema: String, prompt: String,
                    done: @escaping (Result<[String: Any], Error>) -> Void) {
        let model = Edition.model(Settings.model)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", #"export PATH="$HOME/.local/bin:$HOME/.devbar/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; exec claude "$@""#,
                       "ideaforge", "-p", "--output-format", "json", "--tools", "", "--no-session-persistence",
                       "--disable-slash-commands", "--setting-sources", "project", "--settings", authSettings().path,
                       "--append-system-prompt", system, "--json-schema", schema, "--model", model, prompt]
        p.currentDirectoryURL = Store.shared.dir
        var env = ProcessInfo.processInfo.environment.filter {
            !["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID"].contains($0.key)
        }
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = FileHandle.nullDevice

        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 150, execute: killer)
        DispatchQueue.global().async {
            do { try p.run() } catch {
                DispatchQueue.main.async { done(.failure(Failure(errorDescription: "Couldn't start Claude: \(error.localizedDescription)"))) }
                return
            }
            let o = out.fileHandleForReading.readDataToEndOfFile()
            let e = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            Edition.logUsage(task: task, model: model, output: o)
            let obj = try? JSONSerialization.jsonObject(with: o) as? [String: Any]
            let result: Result<[String: Any], Error>
            if let s = obj?["structured_output"] as? [String: Any] {
                result = .success(s)
            } else {
                var msg = (obj?["result"] as? String) ?? String(decoding: e, as: UTF8.self)
                msg = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                if p.terminationReason == .uncaughtSignal { msg = "Claude took too long (over 2½ minutes)." }
                result = .failure(Failure(errorDescription: msg.isEmpty ? "Claude returned nothing (exit \(p.terminationStatus))." : String(msg.suffix(300))))
            }
            DispatchQueue.main.async { done(result) }
        }
    }

    // MARK: Shape (raw thought → one or more cards)

    static let persona = """
    You turn a raw, possibly messy thought into crisp backlog cards for someone who builds small macOS \
    apps and AI agents. The thought may be half-formed, in mixed language, or hold several \
    ideas at once — split distinct ideas into separate cards, but keep one idea as one card. Restate each \
    idea in plain, simple English so anyone can understand it.

    For each card:
    - title: short and specific, starts with a verb, at most 60 characters.
    - summary: one or two sentences — what it does and who it helps.
    - why: one sentence on the value.
    - type: "agent" for a brand-new app or agent, "enhancement" to add to an existing app, "fix" when \
    something is broken, "chore" for housekeeping (archive, delete, clean up, docs).
    - app: the existing app it belongs to, exactly as named in the list you're given; empty for a new agent.
    - home: where it ships. "personal" if it is generic and useful to anyone (fine on public GitHub); \
    "work" if it touches an employer's systems, internal data, customers or colleagues; "local" if it \
    should stay private on this Mac. For an existing app, use that app's home. Empty if truly unclear.
    - priority: "high" only if the thought says it is urgent or blocking, "low" if it is a someday idea, else "med".
    - steps: 3 to 6 short, concrete build steps.
    - helpers: names of people the thought says could help or should be asked; else empty.
    - tags: up to 3 short lowercase tags.
    - similar: numbers of ideas already on the board that this card overlaps with or duplicates; else empty.
    Never invent facts that aren't in the thought; keep unknowns out rather than guessing.
    """

    static let shapeSchema = """
    {"type":"object","required":["ideas"],"properties":{"ideas":{"type":"array","minItems":1,"items":{"type":"object",
    "required":["title","summary","why","type","app","home","priority","steps","helpers","tags","similar"],"properties":{
    "title":{"type":"string"},"summary":{"type":"string"},"why":{"type":"string"},
    "type":{"type":"string","enum":["agent","enhancement","fix","chore"]},"app":{"type":"string"},
    "home":{"type":"string","enum":["personal","work","local",""]},
    "priority":{"type":"string","enum":["high","med","low"]},
    "steps":{"type":"array","items":{"type":"string"}},"helpers":{"type":"array","items":{"type":"string"}},
    "tags":{"type":"array","items":{"type":"string"}},"similar":{"type":"array","items":{"type":"integer"}}}}}}}
    """

    /// Pending ideas as "#n [stage] title — summary", for prompts that should know the board.
    static func boardLines(except id: String? = nil) -> [String] {
        Store.shared.ideas.filter { ($0.pending || $0.stage == "parked") && $0.id != id }.map { i in
            let sum = (i.summary ?? "").isEmpty ? "" : " — \(i.summary!)"
            return "#\(i.n ?? 0) [\(i.stage)] \(i.name)\(i.app.map { $0.isEmpty ? "" : " (for \($0))" } ?? "")\(sum)"
        }
    }

    static func shape(_ thought: String, id: String, single: Bool, done: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let apps = Fleet.apps().map { a in "\(a["name"]!) — \(a["home"]!.isEmpty ? "unknown" : a["home"]!)" }
        // Only the editions with the Claude tools look for duplicates (it makes every prompt longer).
        let board = Edition.claudeTools ? boardLines(except: id) : []
        let prompt = """
        Existing apps (name — home):
        \(apps.isEmpty ? "(none found)" : apps.joined(separator: "\n"))
        \(board.isEmpty ? "" : "\nIdeas already on the board:\n" + board.joined(separator: "\n") + "\n")
        \(single ? "Return exactly ONE card for this thought." : "Shape this thought into one or more cards.")
        Thought:
        \(thought)
        """
        let system = Edition.personaNote.isEmpty ? persona : persona + "\n\n" + Edition.personaNote
        run(task: "Shape ideas", system: system, schema: shapeSchema, prompt: prompt) { r in
            switch r {
            case .success(let s):
                if let cards = s["ideas"] as? [[String: Any]], !cards.isEmpty { done(.success(cards)) }
                else { done(.failure(Failure(errorDescription: "Claude returned no cards."))) }
            case .failure(let e): done(.failure(e))
            }
        }
    }

    // MARK: Ask (a question about one idea)

    static let askPersona = """
    You help someone think through one idea from their backlog of apps and AI agents to build. Answer \
    their question about it directly and practically, in plain English, at most 150 words. Use short \
    "- " bullet lines when listing things; no headings, no bold. If the question asks for a plan or \
    build steps, also return them in `steps` (3 to 8 short, concrete steps); otherwise return [] for steps. \
    Don't invent facts about their systems or people; say what you'd need to know instead.
    """
    static let askSchema = """
    {"type":"object","required":["answer","steps"],"properties":{"answer":{"type":"string"},
    "steps":{"type":"array","items":{"type":"string"}}}}
    """

    static func ask(brief: String, question: String, id: String, done: @escaping (Result<[String: Any], Error>) -> Void) {
        let board = boardLines(except: id)
        let people = Edition.people()
        let prompt = """
        The idea:
        \(brief)
        \(board.isEmpty ? "" : "\nOther ideas on the board (for context):\n" + board.prefix(40).joined(separator: "\n") + "\n")
        \(people.isEmpty ? "" : "\nPeople on my team (name any who fit when asked who could help):\n" + people.joined(separator: ", ") + "\n")
        Question:
        \(question)
        """
        let system = Edition.personaNote.isEmpty ? askPersona : askPersona + "\n\n" + Edition.personaNote
        run(task: "Ask about an idea", system: system, schema: askSchema, prompt: prompt, done: done)
    }

    // MARK: What next (pick from the whole board)

    static let nextPersona = """
    You look at someone's backlog of apps and AI agents to build and pick what they should do next. \
    Pick up to 3 pending ideas (never shipped, parked or removed ones). Favour finishing what is already \
    being built, anything urgent or blocking, and quick wins with clear value. For each pick give one \
    plain sentence on why now. Then one short sentence of overall advice in `note` (e.g. too much in \
    progress, something stale to park).
    """
    static let nextSchema = """
    {"type":"object","required":["picks","note"],"properties":{"picks":{"type":"array","maxItems":3,"items":{"type":"object",
    "required":["n","why"],"properties":{"n":{"type":"integer"},"why":{"type":"string"}}}},"note":{"type":"string"}}}
    """

    static func whatNext(_ board: String, done: @escaping (Result<[String: Any], Error>) -> Void) {
        let prompt = "Today is \(Date().formatted(date: .complete, time: .omitted)).\n\nThe board:\n\(board)"
        let system = Edition.personaNote.isEmpty ? nextPersona : nextPersona + "\n\n" + Edition.personaNote
        run(task: "What to build next", system: system, schema: nextSchema, prompt: prompt, done: done)
    }

    // MARK: Build (hand a card to an interactive Claude Code session in Terminal)

    /// Writes the prompt and a .command script, then opens it: Terminal runs `claude` in the app's folder.
    /// (A .command file needs no Automation permission, unlike scripting Terminal.)
    static func build(brief: String, app: String, number: Int) -> Bool {
        let path = Fleet.apps().first { $0["name"]!.caseInsensitiveCompare(app) == .orderedSame }?["path"] ?? ""
        let dir = path.isEmpty ? NSHomeDirectory() : path
        let fresh = path.isEmpty
        var prompt = """
        I want to build this idea from my \(Edition.name) board (#\(number)):

        \(brief)

        """
        prompt += fresh
            ? "\(app.isEmpty ? "It's a new app or agent." : "It's for \(app), but I couldn't find its folder.") Look around before you start, suggest a folder name in ~, and confirm the plan with me first."
            : "The code for \(app) is in this folder. Read it first, then propose a short plan and confirm it with me before making changes."
        if !Edition.buildNote.isEmpty { prompt += "\n\n" + Edition.buildNote }
        let runs = Store.shared.dir.appendingPathComponent("build", isDirectory: true)
        try? FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        let promptFile = runs.appendingPathComponent("idea-\(number).md")
        let script = runs.appendingPathComponent("idea-\(number).command")
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }
        let sh = """
        #!/bin/zsh -l
        # Opened by \(Edition.name): a Claude Code session for idea #\(number).
        export PATH="$HOME/.local/bin:$HOME/.devbar/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
        cd \(q(dir)) || exit 1
        clear
        echo "\(Edition.symbol)  \(Edition.name) → Claude Code · idea #\(number)"
        exec claude "$(cat \(q(promptFile.path)))"

        """
        do {
            try prompt.write(to: promptFile, atomically: true, encoding: .utf8)
            try sh.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch { return false }
        return NSWorkspace.shared.open(script)
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let board = Board()

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
            return ("ok", "\(ideas.filter { $0.pending }.count) pending · \(building) building")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        NexusBeacon.attach(item)   // lets the app live in its parent's (Nexus or Citadel) menu
        item.button?.toolTip = "\(Edition.name) — your next apps and agents"
        updateTitle()
        store.onChange = { [weak self] in
            self?.updateTitle()
            self?.board.push()
            NexusBeacon.beat()
        }
        if CommandLine.arguments.contains("--board") || store.demo { board.show() }
    }

    func updateTitle() {
        let count = Store.shared.ideas.filter { $0.pending }.count
        item.button?.title = Settings.showCount && count > 0 ? "\(Edition.symbol) \(count)" : Edition.symbol
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let ideas = Store.shared.ideas
        menu.addItem(action("Open Board", #selector(openBoard), "b"))
        menu.addItem(action("Capture a Thought…", #selector(capture), "n"))
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
        menu.addItem(.separator())
        if Edition.claudeTools && !next.isEmpty { menu.addItem(action("🎯 What Should I Build Next?", #selector(whatNext))) }
        menu.addItem(action("Copy Pending Checklist", #selector(copyChecklist)))
        menu.addItem(settingsItem())
        menu.addItem(action("Help & Source on \(Edition.repoLabel)", #selector(openHelp)))
        menu.addItem(.separator())
        menu.addItem(action("Quit \(Edition.name)", #selector(quit), "q"))
    }

    func settingsItem() -> NSMenuItem {
        let it = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let m = NSMenu()
        m.addItem(groupHeader("Shaping"))
        m.addItem(switchRow("Shape new thoughts with Claude", Settings.autoShape, #selector(switchShape(_:))))
        m.addItem(segmentRow("Claude model", Edition.models.map { App.short($0.1) }, Edition.models.firstIndex { $0.0 == Settings.model } ?? 0, #selector(segModel(_:))))
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
    @objc func openIdea(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String else { return }
        board.show(then: "forge.openCard(\(Board.js(id)))")
    }
    @objc func captureClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { NSSound.beep(); return }
        board.show(then: "forge.capture(\(Board.js(text)))")
    }
    @objc func whatNext() { board.show(then: "forge.whatNext()") }
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

    static func js(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(decoding: d, as: UTF8.self) + "[0]"
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func show(then script: String? = nil) {
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
        NSApp.setActivationPolicy(.regular)   // Dock icon + ⌘-Tab while the window is open
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func run(_ s: String) {
        if ready { web?.evaluateJavaScript(s, completionHandler: nil) } else { queued.append(s) }
    }

    /// Sends the whole state to the page: ideas, your apps, settings.
    func push() {
        guard web != nil else { return }
        let ideas = (try? JSONSerialization.jsonObject(with: Store.shared.data)) ?? ["version": 1, "ideas": []]
        let state: [String: Any] = [
            "doc": ideas,
            "apps": Fleet.apps(),
            "people": Edition.people(),
            "claude": Claude.available,
            "edition": ["name": Edition.name, "symbol": Edition.symbol, "flavor": Edition.flavor, "claudeTools": Edition.claudeTools,
                        "repo": Edition.repoURL, "repoLabel": Edition.repoLabel,
                        "models": Edition.models.map { [$0.0, $0.1] }, "appearances": Edition.appearances.map { [$0.0, $0.1] }],
            "demo": Store.shared.demo,
            "file": Store.shared.file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
            "settings": ["appearance": Settings.appearance, "model": Settings.model, "autoShape": Settings.autoShape,
                         "showCount": Settings.showCount, "login": SMAppService.mainApp.status == .enabled],
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: state) else { return }
        web?.evaluateJavaScript("forge.load(\(String(decoding: d, as: UTF8.self)))", completionHandler: nil)
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let msg = m.body as? [String: Any], let cmd = msg["cmd"] as? String else { return }
        switch cmd {
        case "ready":
            ready = true
            push()
            queued.forEach { web?.evaluateJavaScript($0, completionHandler: nil) }
            queued = []
        case "save":
            guard let doc = msg["doc"], let d = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) else { return }
            Store.shared.save(d)
            (NSApp.delegate as? App)?.updateTitle()
            NexusBeacon.beat()
        case "shape":
            guard let id = msg["id"] as? String, let text = msg["text"] as? String else { return }
            let single = msg["single"] as? Bool ?? false
            Claude.shape(text, id: id, single: single) { [weak self] r in
                switch r {
                case .success(let cards):
                    let d = (try? JSONSerialization.data(withJSONObject: cards)) ?? Data("[]".utf8)
                    self?.run("forge.shaped(\(Board.js(id)), \(String(decoding: d, as: UTF8.self)), null)")
                case .failure(let e):
                    self?.run("forge.shaped(\(Board.js(id)), null, \(Board.js(e.localizedDescription)))")
                }
            }
        case "ask":
            guard let id = msg["id"] as? String, let brief = msg["brief"] as? String, let q = msg["q"] as? String else { return }
            Claude.ask(brief: brief, question: q, id: id) { [weak self] r in
                switch r {
                case .success(let s):
                    let d = (try? JSONSerialization.data(withJSONObject: s)) ?? Data("{}".utf8)
                    self?.run("forge.answered(\(Board.js(id)), \(String(decoding: d, as: UTF8.self)), null)")
                case .failure(let e):
                    self?.run("forge.answered(\(Board.js(id)), null, \(Board.js(e.localizedDescription)))")
                }
            }
        case "next":
            guard let board = msg["board"] as? String else { return }
            Claude.whatNext(board) { [weak self] r in
                switch r {
                case .success(let s):
                    let d = (try? JSONSerialization.data(withJSONObject: s)) ?? Data("{}".utf8)
                    self?.run("forge.nextPicks(\(String(decoding: d, as: UTF8.self)), null)")
                case .failure(let e):
                    self?.run("forge.nextPicks(null, \(Board.js(e.localizedDescription)))")
                }
            }
        case "build":
            guard let brief = msg["brief"] as? String, let n = msg["n"] as? Int else { return }
            let ok = Claude.build(brief: brief, app: msg["app"] as? String ?? "", number: n)
            run("forge.built(\(ok))")
        case "copy":
            if let t = msg["text"] as? String { Board.copy(t) }
        case "setting":
            guard let k = msg["key"] as? String else { return }
            let app = NSApp.delegate as? App
            switch k {
            case "appearance": if let v = msg["value"] as? String { Settings.appearance = v; Settings.applyAppearance() }
            case "model": if let v = msg["value"] as? String { Settings.model = v; Edition.modelChanged() }
            case "autoShape": if let v = msg["value"] as? Bool { Settings.autoShape = v }
            case "showCount": if let v = msg["value"] as? Bool { Settings.showCount = v; app?.updateTitle() }
            case "login": app?.toggleLogin()
            default: break
            }
            push()
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
