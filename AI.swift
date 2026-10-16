// AI.swift — the AI behind shaping, asking, sparking, reading pages and finding challenges.
//
// Two kinds of provider: the local Claude Code CLI (no key, uses your own Claude sign-in) and HTTP APIs —
// Anthropic, OpenAI, Google Gemini, OpenRouter, any OpenAI-compatible server, and Ollama on this Mac.
// Keys live in the macOS Keychain, never in a file. Model lists come live from each provider (refreshed
// daily and on demand) with a built-in list for when you're offline. Each edition picks which providers
// it offers (Edition.providers).

import AppKit
import Security

/// One AI service the app can talk to.
struct Provider {
    enum Key: String { case none, required, optional }
    let id: String
    let name: String
    /// What the board calls the AI: "✨ Shaping with Claude".
    let word: String
    let key: Key
    /// Default server address; "" = fixed endpoint, no address field.
    let defaultBase: String
    /// Where to get a key (or the app).
    let help: String
    /// Shown until the live list arrives, and when offline. The first is the default.
    let fallback: [(String, String)]
}

enum AI {
    struct Failure: LocalizedError { let errorDescription: String? }

    static let all: [Provider] = [
        Provider(id: "claude-code", name: "Claude Code (installed app)", word: "Claude", key: .none, defaultBase: "",
                 help: "https://claude.com/claude-code", fallback: []),
        Provider(id: "anthropic", name: "Anthropic · Claude API", word: "Claude", key: .required, defaultBase: "",
                 help: "https://console.anthropic.com/settings/keys",
                 fallback: [("claude-sonnet-5-5", "Claude Sonnet 5.5"), ("claude-opus-5-5", "Claude Opus 5.5"),
                            ("claude-fable-5-1", "Claude Fable 5.1"), ("claude-haiku-4-5", "Claude Haiku 4.5")]),
        Provider(id: "openai", name: "OpenAI", word: "GPT", key: .required, defaultBase: "",
                 help: "https://platform.openai.com/api-keys", fallback: [("gpt-5", "GPT-5"), ("gpt-5-mini", "GPT-5 mini")]),
        Provider(id: "gemini", name: "Google Gemini", word: "Gemini", key: .required, defaultBase: "",
                 help: "https://aistudio.google.com/apikey",
                 fallback: [("gemini-2.5-flash", "Gemini 2.5 Flash"), ("gemini-2.5-pro", "Gemini 2.5 Pro")]),
        Provider(id: "openrouter", name: "OpenRouter · many models, one key", word: "AI", key: .required, defaultBase: "",
                 help: "https://openrouter.ai/keys", fallback: [("openrouter/auto", "Auto · OpenRouter picks")]),
        Provider(id: "ollama", name: "Ollama · on this Mac, free", word: "AI", key: .none, defaultBase: "http://localhost:11434",
                 help: "https://ollama.com/download", fallback: []),
        Provider(id: "compatible", name: "OpenAI-compatible (LM Studio, Groq, Mistral…)", word: "AI", key: .optional,
                 defaultBase: "http://localhost:1234/v1", help: "", fallback: []),
    ]
    /// The providers this edition offers.
    static var offered: [Provider] { all.filter { Edition.providers.contains($0.id) } }

    private static let d = UserDefaults.standard

    // MARK: Which provider and model

    static var current: Provider {
        let id = d.string(forKey: "provider")
        if let p = offered.first(where: { $0.id == id }) { return p }
        // First run: Claude Code when it's installed, else the first API.
        if claudeInstalled, let p = offered.first(where: { $0.id == "claude-code" }) { return p }
        return offered.first { $0.id != "claude-code" } ?? offered[0]
    }
    static func setProvider(_ id: String) {
        guard offered.contains(where: { $0.id == id }) else { return }
        d.set(id, forKey: "provider")
    }

    /// Model choices for a provider: live list if we have one, else the built-in one. A chosen model that
    /// isn't on the list (typed by hand, or retired) stays at the top so it never silently changes.
    static func modelOptions(_ p: Provider) -> [(String, String)] {
        if p.id == "claude-code" { return Edition.models }
        var opts = cache[p.id]?.models ?? []
        if opts.isEmpty { opts = p.fallback }
        if let cur = d.string(forKey: "model." + p.id), !cur.isEmpty, !opts.contains(where: { $0.0 == cur }) { opts.insert((cur, cur), at: 0) }
        return opts
    }
    /// The picker's value for a provider.
    static func model(_ p: Provider) -> String {
        if p.id == "claude-code" { return Settings.model }
        if let m = d.string(forKey: "model." + p.id), !m.isEmpty { return m }
        let opts = modelOptions(p)
        if let f = p.fallback.first, opts.contains(where: { $0.0 == f.0 }) { return f.0 }
        return opts.first?.0 ?? ""
    }
    static func setModel(_ m: String, for p: Provider) {
        if p.id == "claude-code" { Settings.model = m; Edition.modelChanged() } else { d.set(m, forKey: "model." + p.id) }
    }
    /// The model a task actually runs on (Claude Code's picker value can mean "follow the parent app").
    static func runModel(_ p: Provider) -> String { p.id == "claude-code" ? Edition.model(Settings.model) : model(p) }

    static func base(_ p: Provider) -> String {
        let b = (d.string(forKey: "base." + p.id) ?? "").trimmingCharacters(in: .whitespaces)
        return (b.isEmpty ? p.defaultBase : b).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    static func setBase(_ b: String, for p: Provider) { d.set(b.trimmingCharacters(in: .whitespaces), forKey: "base." + p.id) }

    // MARK: Keys (Keychain; a plain flag remembers which exist, so drawing the board never opens the Keychain)

    private static let service = (Bundle.main.bundleIdentifier ?? "ideaforge") + ".ai"
    private static var keys: [String: String] = [:]

    static func hasKey(_ p: Provider) -> Bool { d.bool(forKey: "hasKey." + p.id) }
    static func key(_ p: Provider) -> String {
        if let k = keys[p.id] { return k }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: p.id, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        let k = SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "" : ""
        keys[p.id] = k
        return k
    }
    static func setKey(_ key: String?, for p: Provider) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: p.id]
        SecItemDelete(q as CFDictionary)
        let k = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        keys[p.id] = k
        d.set(!k.isEmpty, forKey: "hasKey." + p.id)
        guard !k.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(k.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: Ready?

    static func installed(_ cmd: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", #"export PATH="$HOME/.local/bin:$HOME/.devbar/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; command -v "$1" >/dev/null"#, "ideaforge", cmd]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        // Not waitUntilExit(): it spins the main run loop, and a menu request arriving meanwhile (Nexus asks
        // for the menu at launch) reads AI.current while this lazy check is still running, which crashes.
        let gone = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in gone.signal() }
        do { try p.run() } catch { return false }
        gone.wait()
        return p.terminationStatus == 0
    }
    static let claudeInstalled = installed("claude")
    static let codexInstalled = installed("codex")

    /// nil when the current provider can run, else what's missing, in plain words.
    static func problem(_ p: Provider = current) -> String? {
        switch p.id {
        case "claude-code": return claudeInstalled ? nil : "Claude Code isn't installed. Install it, or pick another AI in Settings."
        case "ollama": return model(p).isEmpty ? "No Ollama model yet. Start Ollama, run `ollama pull llama3.2`, then press ↻." : nil
        case "compatible": return base(p).isEmpty ? "Add the server address in Settings." : model(p).isEmpty ? "Pick or type a model in Settings." : nil
        default: return hasKey(p) ? (model(p).isEmpty ? "Pick a model in Settings." : nil) : "Add your \(p.name.components(separatedBy: " · ")[0]) key in Settings."
        }
    }
    static var ready: Bool { problem() == nil }

    /// Everything the board's AI settings need.
    static func state() -> [String: Any] {
        let p = current
        return ["provider": p.id, "word": p.word, "ready": problem(p) == nil, "problem": problem(p) ?? "",
                "model": model(p), "models": modelOptions(p).map { [$0.0, $0.1] },
                "modelsAt": cache[p.id]?.at.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                "modelsErr": modelErrors[p.id] ?? "", "loading": loading.contains(p.id),
                "providers": offered.map { ["id": $0.id, "name": $0.name, "key": $0.key.rawValue, "hasKey": hasKey($0),
                                            "base": $0.defaultBase.isEmpty ? "" : base($0), "help": $0.help] },
                "claude": claudeInstalled, "codex": codexInstalled]
    }

    // MARK: Live model lists (cached in models.json)

    private struct Cached { var at: Date?; var models: [(String, String)] }
    private static var cache: [String: Cached] = {
        guard let d = try? Data(contentsOf: cacheFile), let o = try? JSONSerialization.jsonObject(with: d) as? [String: [String: Any]] else { return [:] }
        return o.mapValues { v in
            Cached(at: (v["at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
                   models: (v["models"] as? [[String]] ?? []).compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil })
        }
    }()
    private static var cacheFile: URL { Store.shared.support.appendingPathComponent("models.json") }
    private static var loading = Set<String>()
    private static var modelErrors: [String: String] = [:]

    /// True when the current provider's list is missing or over a day old.
    static var modelsStale: Bool {
        let p = current
        guard p.id != "claude-code", problem(p) == nil || p.id == "ollama" else { return false }
        guard let at = cache[p.id]?.at else { return true }
        return Date().timeIntervalSince(at) > 24 * 3600
    }

    /// Fetches the provider's current models. `done` (main queue) gets an error message, or nil.
    static func refreshModels(_ p: Provider = current, done: ((String?) -> Void)? = nil) {
        guard p.id != "claude-code" else { done?(nil); return }
        if p.key == .required && !hasKey(p) { done?("Add a key first."); return }
        guard !loading.contains(p.id) else { done?(nil); return }
        loading.insert(p.id)
        let key = self.key(p), base = self.base(p)
        var url: URL?, headers: [String: String] = [:]
        switch p.id {
        case "anthropic": url = URL(string: "https://api.anthropic.com/v1/models?limit=100"); headers = ["x-api-key": key, "anthropic-version": "2023-06-01"]
        case "openai": url = URL(string: "https://api.openai.com/v1/models"); headers = ["Authorization": "Bearer " + key]
        case "gemini": url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200"); headers = ["x-goog-api-key": key]
        case "openrouter": url = URL(string: "https://openrouter.ai/api/v1/models")
        case "ollama": url = URL(string: base + "/api/tags")
        default: url = URL(string: base + "/models"); if !key.isEmpty { headers = ["Authorization": "Bearer " + key] }
        }
        guard let url else { loading.remove(p.id); done?("That server address doesn't look right."); return }
        send(url, headers, nil, timeout: 20) { r, _ in
            DispatchQueue.main.async {
                loading.remove(p.id)
                switch r {
                case .failure(let e):
                    modelErrors[p.id] = e.localizedDescription
                    done?(e.localizedDescription)
                case .success(let j):
                    let list = parseModels(p.id, j)
                    guard !list.isEmpty else { modelErrors[p.id] = "No models came back."; done?("No models came back."); return }
                    modelErrors[p.id] = nil
                    cache[p.id] = Cached(at: Date(), models: list)
                    saveCache()
                    // A local server's first list picks its first model.
                    if (d.string(forKey: "model." + p.id) ?? "").isEmpty, p.fallback.isEmpty { d.set(list[0].0, forKey: "model." + p.id) }
                    done?(nil)
                }
            }
        }
    }

    private static func parseModels(_ id: String, _ j: [String: Any]) -> [(String, String)] {
        let rows = j["data"] as? [[String: Any]] ?? j["models"] as? [[String: Any]] ?? []
        switch id {
        case "anthropic":
            return rows.sorted { ($0["created_at"] as? String ?? "") > ($1["created_at"] as? String ?? "") }
                .compactMap { r in (r["id"] as? String).map { ($0, r["display_name"] as? String ?? $0) } }
        case "openai":
            let skip = ["audio", "realtime", "transcribe", "tts", "image", "search", "embedding", "instruct", "moderation", "codex"]
            return rows.filter { r in
                let m = r["id"] as? String ?? ""
                return ["gpt-", "o1", "o3", "o4", "chatgpt-"].contains { m.hasPrefix($0) } && !skip.contains { m.contains($0) }
            }.sorted { ($0["created"] as? Int ?? 0) > ($1["created"] as? Int ?? 0) }
             .compactMap { r in (r["id"] as? String).map { ($0, $0) } }
        case "gemini":
            return rows.filter { r in
                let n = r["name"] as? String ?? ""
                return (r["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") && n.contains("gemini")
                    && !["embedding", "imagen", "tts", "image", "audio"].contains { n.contains($0) }
            }.compactMap { r in
                (r["name"] as? String).map { n in (n.replacingOccurrences(of: "models/", with: ""), r["displayName"] as? String ?? n) }
            }.sorted { $0.0 > $1.0 }
        case "openrouter":
            return Array(rows.sorted { ($0["created"] as? Int ?? 0) > ($1["created"] as? Int ?? 0) }
                .compactMap { r in (r["id"] as? String).map { ($0, r["name"] as? String ?? $0) } }.prefix(120))
        case "ollama":
            return rows.compactMap { r in (r["name"] as? String).map { ($0, $0) } }
        default:
            return rows.compactMap { r in (r["id"] as? String).map { ($0, $0) } }.sorted { $0.0 < $1.0 }
        }
    }

    private static func saveCache() {
        let iso = ISO8601DateFormatter()
        let o = cache.mapValues { c -> [String: Any] in ["at": c.at.map { iso.string(from: $0) } ?? "", "models": c.models.map { [$0.0, $0.1] }] }
        if let data = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted]) { try? data.write(to: cacheFile, options: .atomic) }
    }

    // MARK: Running a task

    /// One structured turn on the current provider. `tools` lets an edition's Claude Code run read its
    /// connected systems (Edition.toolArgs). `done` gets the JSON object, or an error, on the main queue.
    static func run(task: String, system: String, schema: String, prompt: String, tools: Bool = false,
                    done: @escaping (Result<[String: Any], Error>) -> Void) {
        let p = current
        let finish: (Result<[String: Any], Error>) -> Void = { r in DispatchQueue.main.async { done(r) } }
        if let why = problem(p) { finish(.failure(Failure(errorDescription: why))); return }
        let system = Edition.personaNote.isEmpty ? system : system + "\n\n" + Edition.personaNote
        if p.id == "claude-code" { runCLI(task: task, system: system, schema: schema, prompt: prompt, tools: tools, done: finish); return }
        call(p, system: system, schema: schema, prompt: prompt, done: finish)
    }

    /// A tiny call to check the provider, key and model work.
    static func test(_ done: @escaping (Bool, String) -> Void) {
        let start = Date(), p = current
        run(task: "Test connection", system: "Reply with ok set to true.", schema: #"{"type":"object","required":["ok"],"properties":{"ok":{"type":"boolean"}}}"#,
            prompt: "Are you there?") { r in
            switch r {
            case .success: done(true, "✓ Connected · \(runModel(p)) · \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
            case .failure(let e): done(false, e.localizedDescription)
            }
        }
    }

    private static func parse(_ text: String) -> [String: Any]? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}"), a < b { t = String(t[a...b]) }
        return (try? JSONSerialization.jsonObject(with: Data(t.utf8))) as? [String: Any]
    }
    private static let badShape = Failure(errorDescription: "The AI's reply wasn't in the expected shape. Try again, or pick a bigger model.")

    private static func call(_ p: Provider, system: String, schema: String, prompt: String,
                             done: @escaping (Result<[String: Any], Error>) -> Void) {
        let model = self.model(p), key = self.key(p), base = self.base(p)
        let schemaObj = (try? JSONSerialization.jsonObject(with: Data(schema.utf8))) as? [String: Any] ?? [:]
        let jsonNote = "\n\nReply with only one JSON object (no prose, no code fences) that matches this JSON schema:\n" + schema
        func text(_ r: Result<[String: Any], Error>, _ pick: ([String: Any]) -> String?) -> Result<[String: Any], Error> {
            r.flatMap { j in pick(j).flatMap(parse).map { .success($0) } ?? .failure(badShape) }
        }
        switch p.id {
        case "anthropic":
            let body: [String: Any] = ["model": model, "max_tokens": 8192, "system": system,
                                       "messages": [["role": "user", "content": prompt]],
                                       "tools": [["name": "reply", "description": "Return your reply.", "input_schema": schemaObj]],
                                       "tool_choice": ["type": "tool", "name": "reply"]]
            send(URL(string: "https://api.anthropic.com/v1/messages")!, ["x-api-key": key, "anthropic-version": "2023-06-01"], body) { r, _ in
                done(r.flatMap { j in
                    let blocks = j["content"] as? [[String: Any]] ?? []
                    if let input = blocks.first(where: { $0["type"] as? String == "tool_use" })?["input"] as? [String: Any] { return .success(input) }
                    return parse(blocks.compactMap { $0["text"] as? String }.joined()).map { .success($0) } ?? .failure(badShape)
                })
            }
        case "gemini":
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
            let h = ["x-goog-api-key": key]
            func body(_ strict: Bool) -> [String: Any] {
                var gen: [String: Any] = ["responseMimeType": "application/json"]
                if strict { gen["responseJsonSchema"] = schemaObj }
                return ["systemInstruction": ["parts": [["text": strict ? system : system + jsonNote]]],
                        "contents": [["role": "user", "parts": [["text": prompt]]]], "generationConfig": gen]
            }
            let pick: ([String: Any]) -> String? = { j in
                (((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?
                    .compactMap { $0["text"] as? String }.joined()
            }
            send(url, h, body(true)) { r, code in
                // Older models don't take a JSON schema: ask for JSON in words instead.
                if case .failure = r, code == 400 { send(url, h, body(false)) { r2, _ in done(text(r2, pick)) } } else { done(text(r, pick)) }
            }
        case "ollama":
            let body: [String: Any] = ["model": model, "stream": false, "format": schemaObj, "options": ["temperature": 0.3],
                                       "messages": [["role": "system", "content": system + jsonNote], ["role": "user", "content": prompt]]]
            send(URL(string: base + "/api/chat") ?? URL(string: "http://localhost:11434/api/chat")!, [:], body, timeout: 300) { r, _ in
                done(text(r) { ($0["message"] as? [String: Any])?["content"] as? String })
            }
        default:   // OpenAI, OpenRouter and OpenAI-compatible servers share the chat completions API.
            let root = p.id == "openai" ? "https://api.openai.com/v1" : p.id == "openrouter" ? "https://openrouter.ai/api/v1" : base
            guard let url = URL(string: root + "/chat/completions") else { done(.failure(Failure(errorDescription: "That server address doesn't look right."))); return }
            var h: [String: String] = key.isEmpty ? [:] : ["Authorization": "Bearer " + key]
            if p.id == "openrouter" { h["HTTP-Referer"] = Edition.repoURL; h["X-Title"] = Edition.name }
            // Strict schema first; servers that don't support it get "JSON please", then plain text.
            func attempt(_ mode: Int) {
                var body: [String: Any] = ["model": model, "messages": [["role": "system", "content": mode == 0 ? system : system + jsonNote],
                                                                         ["role": "user", "content": prompt]]]
                if mode == 0 { body["response_format"] = ["type": "json_schema", "json_schema": ["name": "reply", "schema": schemaObj, "strict": false]] }
                if mode == 1 { body["response_format"] = ["type": "json_object"] }
                send(url, h, body, timeout: p.id == "compatible" ? 300 : 150) { r, code in
                    if case .failure = r, [400, 422].contains(code), mode < 2 { attempt(mode + 1); return }
                    done(text(r) { (($0["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String })
                }
            }
            attempt(0)
        }
    }

    /// GET (body nil) or POST JSON. `done` runs on a background queue with the parsed object and status code.
    private static func send(_ url: URL, _ headers: [String: String], _ body: [String: Any]?, timeout: TimeInterval = 150,
                             _ done: @escaping (Result<[String: Any], Error>, Int) -> Void) {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = body == nil ? "GET" : "POST"
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let err = err as? URLError {
                let host = url.host ?? "the server"
                let msg: String
                switch err.code {
                case .notConnectedToInternet: msg = "You're offline."
                case .cannotConnectToHost, .cannotFindHost: msg = "Couldn't reach \(host). Is it running, and is the address right?"
                case .timedOut: msg = "\(host) took too long to answer."
                default: msg = err.localizedDescription
                }
                done(.failure(Failure(errorDescription: msg)), code); return
            }
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if (200..<300).contains(code), let j { done(.success(j), code); return }
            var msg = (j?["error"] as? [String: Any])?["message"] as? String ?? j?["error"] as? String ?? j?["message"] as? String ?? ""
            if msg.isEmpty {
                switch code {
                case 401, 403: msg = "The key was refused. Check it in Settings."
                case 404: msg = "Not found — the model or address may be wrong."
                case 429: msg = "Rate limit or quota reached. Wait a bit, or check your plan."
                default: msg = "The AI service answered \(code)."
                }
            } else if [401, 403].contains(code) { msg = "The key was refused: " + msg }
            done(.failure(Failure(errorDescription: String(msg.prefix(300)))), code)
        }.resume()
    }

    // MARK: Claude Code (the local CLI)

    /// Copies only the auth keys from ~/.claude/settings.json: user settings are skipped
    /// (`--setting-sources project`) so no allow-list or hook from them can ride along.
    static func authSettings() -> URL {
        let out = Store.shared.support.appendingPathComponent("auth-settings.json")
        let user = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        var auth: [String: Any] = ["enabledPlugins": [String: Any]()]
        if let d = try? Data(contentsOf: user), let all = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for k in ["apiKeyHelper", "env", "awsAuthRefresh", "awsCredentialExport", "forceLoginMethod"] { auth[k] = all[k] }
        }
        if let d = try? JSONSerialization.data(withJSONObject: auth) {
            try? d.write(to: out, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: out.path)
        }
        return out
    }

    private static func runCLI(task: String, system: String, schema: String, prompt: String, tools: Bool,
                               done: @escaping (Result<[String: Any], Error>) -> Void) {
        let model = runModel(current)
        let toolArgs = tools ? Edition.toolArgs(Store.shared.support) : nil
        var args = ["ideaforge", "-p", "--output-format", "json", "--no-session-persistence", "--disable-slash-commands",
                    "--setting-sources", "project"]
        // No tools: no MCP servers, plugins or built-ins at all. With tools: the edition's read-only set.
        args += toolArgs ?? ["--strict-mcp-config", "--tools", "", "--settings", authSettings().path]
        args += ["--append-system-prompt", system, "--json-schema", schema, "--model", model, prompt]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", #"export PATH="$HOME/.local/bin:$HOME/.devbar/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; exec claude "$@""#] + args
        p.currentDirectoryURL = Store.shared.support
        var env = ProcessInfo.processInfo.environment.filter {
            !["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID"].contains($0.key)
        }
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        env["MAX_MCP_OUTPUT_TOKENS"] = "40000"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = FileHandle.nullDevice

        let limit: TimeInterval = toolArgs == nil ? 150 : 360
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: killer)
        DispatchQueue.global().async {
            do { try p.run() } catch { done(.failure(Failure(errorDescription: "Couldn't start Claude: \(error.localizedDescription)"))); return }
            var o = Data(), e = Data()
            let g = DispatchGroup()
            g.enter(); DispatchQueue.global().async { o = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
            g.enter(); DispatchQueue.global().async { e = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
            p.waitUntilExit()
            killer.cancel()
            g.wait()
            DispatchQueue.main.async { Edition.logUsage(task: task, model: model, output: o) }
            let obj = try? JSONSerialization.jsonObject(with: o) as? [String: Any]
            if let s = obj?["structured_output"] as? [String: Any] { done(.success(s)); return }
            var msg = (obj?["result"] as? String) ?? String(decoding: e, as: UTF8.self)
            msg = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            if obj?["subtype"] as? String == "error_max_budget_usd" { msg = "Hit this task's spend cap." }
            if p.terminationReason == .uncaughtSignal { msg = "Claude took too long (over \(Int(limit / 60)) minutes)." }
            done(.failure(Failure(errorDescription: msg.isEmpty ? "Claude returned nothing (exit \(p.terminationStatus))." : String(msg.suffix(300)))))
        }
    }

    // MARK: - Prompts

    static let cardRules = """
    For each card:
    - title: short and specific, starts with a verb, at most 60 characters.
    - summary: one or two sentences — what it does and who it helps.
    - why: one sentence on the value.
    - type: "agent" for a brand-new app or agent, "enhancement" to add to an existing app, "fix" when \
    something is broken, "chore" for housekeeping (archive, delete, clean up, docs).
    - app: the existing app it belongs to, exactly as named in the list you're given; empty for a new agent.
    - group: the agent or app this idea belongs to, so related ideas sit together. For an existing app, \
    its name. For a new agent, a short name for that agent (2 to 3 words, e.g. "Meeting Buddy"). When the \
    idea adds to an agent or app already on the board, use that group's name exactly as written there.
    - home: where it ships. "personal" if it is generic and useful to anyone (fine on public GitHub); \
    "work" if it touches an employer's systems, internal data, customers or colleagues; "local" if it \
    should stay private on this Mac. For an existing app, use that app's home. Empty if truly unclear.
    - priority: "high" only if it is urgent or blocking, "low" if it is a someday idea, else "med".
    - steps: 3 to 6 short, concrete build steps.
    - helpers: names of people the text says could help or should be asked; else empty.
    - tags: up to 3 short lowercase tags.
    - similar: numbers of ideas already on the board that this card overlaps with or duplicates; else empty.
    Never invent facts that aren't in the text; keep unknowns out rather than guessing.
    """

    static let challengeRules = """
    For each challenge:
    - title: short and specific, names the problem (not a fix), at most 70 characters.
    - detail: one or two sentences — what happens, who it slows down, and what it costs.
    - where: the tool, page or process where it shows up; empty if unknown.
    - often: "daily", "weekly", "monthly" or "rare" — your best guess from the text.
    - impact: "high" if it blocks work or wastes hours, "low" if it is a small annoyance, else "med".
    - same: the number of a challenge already on the list that is the same problem, else 0.
    Never invent facts; leave unknowns empty.
    """

    static let privacy = """
    Privacy: keep everything short, general and neutral. Never include names of people, customers, \
    companies or accounts, email addresses, phone numbers, record or org IDs, or quoted text from the \
    source. Write "a customer", "an engineer" or "a teammate" instead.
    """

    static let cardItem = """
    {"type":"object","required":["title","summary","why","type","app","group","home","priority","steps","helpers","tags","similar"],"properties":{
    "title":{"type":"string"},"summary":{"type":"string"},"why":{"type":"string"},"group":{"type":"string"},
    "type":{"type":"string","enum":["agent","enhancement","fix","chore"]},"app":{"type":"string"},
    "home":{"type":"string","enum":["personal","work","local",""]},
    "priority":{"type":"string","enum":["high","med","low"]},
    "steps":{"type":"array","items":{"type":"string"}},"helpers":{"type":"array","items":{"type":"string"}},
    "tags":{"type":"array","items":{"type":"string"}},"similar":{"type":"array","items":{"type":"integer"}}}}
    """
    static func challengeItem(extra: Bool = false) -> String {
        """
        {"type":"object","required":["title","detail","where","often","impact","same"\(extra ? #","source","url""# : "")],"properties":{
        "title":{"type":"string"},"detail":{"type":"string"},"where":{"type":"string"},
        "often":{"type":"string","enum":["daily","weekly","monthly","rare"]},
        "impact":{"type":"string","enum":["high","med","low"]},"same":{"type":"integer"}\(extra ? #","source":{"type":"string"},"url":{"type":"string"}"# : "")}}
        """
    }

    /// Pending ideas as "#n [stage] title — summary", for prompts that should know the board.
    static func boardLines(except id: String? = nil) -> [String] {
        Store.shared.ideas.filter { ($0.pending || $0.stage == "parked") && $0.id != id }.map { i in
            let sum = (i.summary ?? "").isEmpty ? "" : " — \(i.summary!)"
            let g = i.groupName.isEmpty ? "" : " {group: \(i.groupName)}"
            return "#\(i.n ?? 0) [\(i.stage)] \(i.name)\(i.app.map { $0.isEmpty ? "" : " (for \($0))" } ?? "")\(g)\(sum)"
        }
    }
    /// Open and solved challenges as "C#n [status] title — detail".
    static func challengeLines(except id: String? = nil) -> [String] {
        Store.shared.challenges.filter { ["open", "solved"].contains($0.stage) && $0.id != id }.map { c in
            "C#\(c.n ?? 0) [\(c.stage)] \(c.name)\((c.detail ?? "").isEmpty ? "" : " — " + c.detail!)"
        }
    }
    private static func appLines() -> String {
        let apps = Fleet.apps().map { a in "\(a["name"]!) — \(a["home"]!.isEmpty ? "unknown" : a["home"]!)" }
        return apps.isEmpty ? "(none found)" : apps.joined(separator: "\n")
    }
    private static func section(_ title: String, _ lines: [String], max: Int = 60) -> String {
        lines.isEmpty ? "" : "\n\(title):\n" + lines.prefix(max).joined(separator: "\n") + "\n"
    }

    // MARK: Shape (raw thought → one or more cards)

    static let persona = """
    You turn a raw, possibly messy thought into crisp backlog cards for someone who builds small macOS \
    apps and AI agents. The thought may be half-formed, in mixed language, or hold several \
    ideas at once — split distinct ideas into separate cards, but keep one idea as one card. Restate each \
    idea in plain, simple English so anyone can understand it.

    """ + cardRules

    static let shapeSchema = #"{"type":"object","required":["ideas"],"properties":{"ideas":{"type":"array","minItems":1,"items":"# + cardItem + "}}}"

    static func shape(_ thought: String, id: String, single: Bool, done: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let prompt = """
        Existing apps (name — home):
        \(appLines())
        \(section("Ideas already on the board", boardLines(except: id)))
        \(single ? "Return exactly ONE card for this thought." : "Shape this thought into one or more cards.")
        Thought:
        \(thought)
        """
        run(task: "Shape ideas", system: persona, schema: shapeSchema, prompt: prompt) { r in
            done(r.flatMap { s in
                let cards = s["ideas"] as? [[String: Any]] ?? []
                return cards.isEmpty ? .failure(Failure(errorDescription: "The AI returned no cards.")) : .success(cards)
            })
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
        let prompt = """
        The idea:
        \(brief)
        \(section("Other ideas on the board (for context)", boardLines(except: id), max: 40))
        \(section("People I can ask (name any who fit when asked who could help)", [Settings.allPeople.joined(separator: ", ")].filter { !$0.isEmpty }))
        Question:
        \(question)
        """
        run(task: "Ask about an idea", system: askPersona, schema: askSchema, prompt: prompt, done: done)
    }

    // MARK: What next (pick from the whole board)

    static let nextPersona = """
    You look at someone's backlog of apps and AI agents to build and pick what they should do next. \
    Pick up to 3 pending ideas (never shipped, parked or removed ones). Favour finishing what is already \
    being built, anything urgent or blocking, ideas that solve hot challenges (hit often, high impact), \
    and quick wins with clear value. For each pick give one plain sentence on why now. Then one short \
    sentence of overall advice in `note` (e.g. too much in progress, something stale to park).
    """
    static let nextSchema = """
    {"type":"object","required":["picks","note"],"properties":{"picks":{"type":"array","maxItems":3,"items":{"type":"object",
    "required":["n","why"],"properties":{"n":{"type":"integer"},"why":{"type":"string"}}}},"note":{"type":"string"}}}
    """

    static func whatNext(_ board: String, done: @escaping (Result<[String: Any], Error>) -> Void) {
        let prompt = "Today is \(Date().formatted(date: .complete, time: .omitted)).\n\nThe board:\n\(board)"
        run(task: "What to build next", system: nextPersona, schema: nextSchema, prompt: prompt, done: done)
    }

    // MARK: Challenges (shape one, spark ideas for one)

    static let challengePersona = """
    You turn a messy note about a recurring problem, pain point or slow manual task into one clear \
    challenge card, for someone who builds small apps and AI agents to remove such problems. Restate it \
    in plain, simple English.

    """ + challengeRules
    static let challengeSchema = challengeItem()

    static func shapeChallenge(_ text: String, id: String, done: @escaping (Result<[String: Any], Error>) -> Void) {
        let prompt = """
        \(section("Challenges already on the list", challengeLines(except: id)))
        The note:
        \(text)
        """
        run(task: "Shape challenges", system: challengePersona, schema: challengeSchema, prompt: prompt, done: done)
    }

    static let sparkPersona = """
    You suggest ideas that would remove or shrink one challenge — a recurring problem or slow manual task — \
    for someone who builds small macOS apps and AI agents. Suggest 1 to 3 genuinely different ideas: a new \
    agent, an enhancement to one of their existing apps (prefer this when an app clearly fits), or a fix. \
    Don't repeat ideas already on the board: when one comes close, put its number in `similar`. Restate \
    everything in plain, simple English.

    """ + cardRules
    static let sparkSchema = #"{"type":"object","required":["ideas"],"properties":{"ideas":{"type":"array","minItems":1,"maxItems":3,"items":"# + cardItem + "}}}"

    static func spark(_ challenge: String, done: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let prompt = """
        Existing apps (name — home):
        \(appLines())
        \(section("Ideas already on the board", boardLines()))
        The challenge:
        \(challenge)
        """
        run(task: "Spark ideas", system: sparkPersona, schema: sparkSchema, prompt: prompt) { r in
            done(r.flatMap { s in
                let cards = s["ideas"] as? [[String: Any]] ?? []
                return cards.isEmpty ? .failure(Failure(errorDescription: "The AI had no ideas for this one.")) : .success(cards)
            })
        }
    }

    // MARK: Read a page (📎 Capture)

    static let readPersona = """
    You read one page someone was looking at — a ticket, case, chat thread, doc or web page — and pull \
    out what could feed their backlog of apps and AI agents to build:
    - challenges: recurring problems, pain points or slow manual work the page shows someone struggling \
    with. Describe the problem, not a fix.
    - ideas: concrete apps, agents or enhancements the page suggests building.
    Return at most 2 of each, and nothing when the page shows neither — then say why in `note`.
    - label: a short neutral name for what the page is, e.g. "Support case", "Bug report", "Slack thread", \
    "Blog post".
    - source: the system or site, e.g. "GitHub", "Stack Overflow", or the site's name.

    """ + privacy + "\n\n" + challengeRules + "\n\n" + cardRules
    static let readSchema = """
    {"type":"object","required":["label","source","challenges","ideas","note"],"properties":{
    "label":{"type":"string"},"source":{"type":"string"},"note":{"type":"string"},
    "challenges":{"type":"array","maxItems":2,"items":\(challengeItem())},
    "ideas":{"type":"array","maxItems":2,"items":\(cardItem)}}}
    """

    static func readPage(_ page: Page, done: @escaping (Result<[String: Any], Error>) -> Void) {
        let tools = Settings.pageReading && current.id == "claude-code" && Edition.readsWithTools(page.url) && Edition.toolArgs(Store.shared.support) != nil
        var body = "Page: \(page.title.isEmpty ? "(no title)" : page.title)\nAddress: \(page.url.isEmpty ? "(none)" : page.url)\nApp: \(page.app)\n"
        if !page.selection.isEmpty { body += "\nThe part they selected:\n\(page.selection)\n" }
        // Pages an edition reads with its own tools are read there, at the source, not scraped.
        if !tools && !page.text.isEmpty { body += "\nPage text:\n\(page.text)\n" }
        let prompt = """
        \(Edition.captureNote.isEmpty || !tools ? "" : Edition.captureNote + "\n")
        Existing apps (name — home):
        \(appLines())
        \(section("Challenges already on the list", challengeLines()))
        \(section("Ideas already on the board", boardLines(), max: 40))
        \(body)
        """
        run(task: "Read a page", system: readPersona, schema: readSchema, prompt: prompt, tools: tools, done: done)
    }

    // MARK: Find challenges (look through signals; with tools, the edition's systems too)

    static let findPersona = """
    You look through signals from someone's work and find recurring challenges: problems, pain points or \
    slow manual tasks that a small app or AI agent could remove. Group signals about the same problem into \
    one challenge. Return up to 6, most valuable first; skip one-off trivia and anything already solved. \
    If a challenge is already on the list, set `same` to its number instead of repeating it. For each, \
    `source` says where you saw it (e.g. "GitHub issues", "Code TODOs") and `url` links to it when a signal \
    has a link, else "". In `note`, one sentence on what you looked through.

    """ + privacy + "\n\n" + challengeRules
    static let findSchema = """
    {"type":"object","required":["challenges","note"],"properties":{"note":{"type":"string"},
    "challenges":{"type":"array","maxItems":6,"items":\(challengeItem(extra: true))}}}
    """

    static func find(signals: String, done: @escaping (Result<[String: Any], Error>) -> Void) {
        // The edition's own connected systems are looked through only with page reading turned on.
        let tools = Settings.pageReading && current.id == "claude-code" && Edition.toolArgs(Store.shared.support) != nil && !Edition.findNote.isEmpty
        let prompt = """
        Today is \(Date().formatted(date: .complete, time: .omitted)).
        \(tools ? "\n" + Edition.findNote + "\n" : "")
        \(section("Challenges already on the list", challengeLines()))
        \(section("Ideas already on the board", boardLines(), max: 40))
        Signals from this Mac:
        \(signals.isEmpty ? "(none)" : signals)
        """
        run(task: "Find challenges", system: findPersona, schema: findSchema, prompt: prompt, tools: tools, done: done)
    }

    // MARK: Place ideas on the impact × effort grid

    static let placePersona = """
    You place backlog ideas on an impact × effort grid. For each idea decide:
    - impact: "high" if it saves real time, removes a frequent pain or unblocks something important; else "low".
    - effort: "low" if a small change to an app or a simple agent could do it in a day or two; "high" if it \
    needs a new app, integrations or a lot of work.
    Give one short reason in `why`. Use the idea numbers exactly as given.
    """
    static let placeSchema = """
    {"type":"object","required":["places"],"properties":{"places":{"type":"array","items":{"type":"object",
    "required":["n","impact","effort","why"],"properties":{"n":{"type":"integer"},
    "impact":{"type":"string","enum":["high","low"]},"effort":{"type":"string","enum":["low","high"]},"why":{"type":"string"}}}}}}
    """

    static func place(_ list: String, done: @escaping (Result<[String: Any], Error>) -> Void) {
        run(task: "Place ideas", system: placePersona, schema: placeSchema, prompt: "The ideas:\n\(list)", done: done)
    }

    // MARK: Build (hand a card to an interactive Claude Code or Codex session in Terminal)

    /// Writes the prompt and a .command script, then opens it: Terminal runs the tool in the app's folder.
    /// (A .command file needs no Automation permission, unlike scripting Terminal.)
    static func build(brief: String, app: String, number: Int, tool: String) -> Bool {
        let path = Fleet.apps().first { $0["name"]!.caseInsensitiveCompare(app) == .orderedSame }?["path"] ?? ""
        let dir = path.isEmpty ? NSHomeDirectory() : path
        let fresh = path.isEmpty
        let cli = tool == "codex" ? "codex" : "claude"
        let label = tool == "codex" ? "Codex" : "Claude Code"
        var prompt = """
        I want to build this idea from my \(Edition.name) board (#\(number)):

        \(brief)

        """
        prompt += fresh
            ? "\(app.isEmpty ? "It's a new app or agent." : "It's for \(app), but I couldn't find its folder.") Look around before you start, suggest a folder name in ~, and confirm the plan with me first."
            : "The code for \(app) is in this folder. Read it first, then propose a short plan and confirm it with me before making changes."
        if !Edition.buildNote.isEmpty { prompt += "\n\n" + Edition.buildNote }
        let promptFile = runs.appendingPathComponent("idea-\(number).md")
        do { try prompt.write(to: promptFile, atomically: true, encoding: .utf8) } catch { return false }
        return terminal(dir: dir, number: number, label: label, run: "exec \(cli) \"$(cat \(q(promptFile.path)))\"")
    }

    /// Reopens an ⚡ Auto-build's Claude Code session in Terminal, to review what it did or finish the job.
    static func resume(session: String, dir: String, number: Int) -> Bool {
        guard UUID(uuidString: session) != nil, FileManager.default.fileExists(atPath: dir) else { return false }
        return terminal(dir: dir, number: number, label: "Claude Code (⚡ Auto-build)", run: "exec claude --resume \(session)")
    }

    private static var runs: URL {
        let u = Store.shared.support.appendingPathComponent("build", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }

    private static func terminal(dir: String, number: Int, label: String, run: String) -> Bool {
        let script = runs.appendingPathComponent("idea-\(number).command")
        let sh = """
        #!/bin/zsh -l
        # Opened by \(Edition.name): a \(label) session for idea #\(number).
        export PATH="$HOME/.local/bin:$HOME/.devbar/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
        cd \(q(dir)) || exit 1
        clear
        echo "\(Edition.symbol)  \(Edition.name) → \(label) · idea #\(number)"
        \(run)

        """
        do {
            try sh.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch { return false }
        return NSWorkspace.shared.open(script)
    }
}

// MARK: - ⚡ Auto-build (Claude Code builds a card on its own, in the background)

/// A headless Claude Code run in the app's folder (or a new folder in ~ for a new agent) that makes the change
/// and gets it to build, then reports back so the card moves on by itself. It may edit files there and run the
/// project's build, but nothing that publishes or reaches out: user settings and MCP servers are skipped,
/// commit/push/release/install and network commands are denied, and each run has a spend cap and a time limit.
enum AutoBuild {
    private final class Job {
        let process: Process, dir: String
        var stopped = false, timedOut = false
        init(_ p: Process, _ dir: String) { process = p; self.dir = dir }
    }
    private static var jobs: [String: Job] = [:]
    /// Ids of the cards building right now.
    static var running: [String] { Array(jobs.keys) }

    static let minutes = 45
    static let budget = "5.00"
    private static let denied = ["git push", "git commit", "git tag", "git reset", "git checkout", "git restore", "git clean",
                                 "git stash", "git rebase", "git merge", "git branch", "git remote", "gh", "sudo", "rm -rf",
                                 "ditto", "open", "osascript", "pkill", "killall", "launchctl", "security", "defaults",
                                 "curl", "wget", "scp", "ssh"].map { "Bash(\($0):*)" }
    private static let schema = """
    {"type":"object","required":["ok","summary","stepsDone","tryIt","files","blocker"],"properties":{
    "ok":{"type":"boolean"},"summary":{"type":"string"},"stepsDone":{"type":"array","items":{"type":"integer"}},
    "tryIt":{"type":"string"},"files":{"type":"array","items":{"type":"string"}},"blocker":{"type":"string"}}}
    """

    /// "Standup bot for my team!" → "StandupBotForMyTeam".
    static func folderName(_ s: String) -> String {
        let words = s.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return name.isEmpty ? "NewAgent" : String(name.prefix(32))
    }

    /// Starts building card `id`; returns its dir, folder and session, or an error. `progress` gets short lines
    /// ("Editing board.html") and `done` the result: ok, summary, stepsDone, tryIt, files, blocker (Claude's
    /// reply), plus dir, folder, fresh, session, cost, and error/stopped when it didn't finish.
    static func start(id: String, n: Int, brief: String, app: String, name: String, steps: [String], dir lastDir: String,
                      progress: @escaping (String) -> Void, done: @escaping ([String: Any]) -> Void) -> Result<[String: String], AI.Failure> {
        func fail(_ s: String) -> Result<[String: String], AI.Failure> { .failure(AI.Failure(errorDescription: s)) }
        guard AI.claudeInstalled else { return fail("⚡ Auto-build needs Claude Code installed.") }
        guard jobs[id] == nil else { return fail("It's already building.") }
        let fm = FileManager.default, home = NSHomeDirectory()
        var dir = Fleet.apps().first { $0["name"]!.caseInsensitiveCompare(app) == .orderedSame }?["path"] ?? ""
        let fresh = dir.isEmpty
        if fresh {
            // A new agent gets its own folder in ~, named after the card; a second try reuses it.
            if lastDir.hasPrefix(home + "/"), fm.fileExists(atPath: lastDir) { dir = lastDir } else {
                let base = folderName(app.isEmpty ? name : app)
                var cand = base, k = 2
                while fm.fileExists(atPath: home + "/" + cand) { cand = base + String(k); k += 1 }
                dir = home + "/" + cand
                do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) } catch { return fail("Couldn't make ~/\(cand).") }
            }
        }
        guard !jobs.values.contains(where: { $0.dir == dir }) else { return fail("Another card is building in that folder. Wait for it to finish.") }
        let folder = (dir as NSString).lastPathComponent

        var prompt = """
        Build this idea from my \(Edition.name) board (#\(n)) on your own. Nobody is watching this run, so don't \
        ask me anything: make sensible choices and say what you chose in the summary.

        \(brief)

        """
        if !steps.isEmpty {
            prompt += "\nThe card's build steps, numbered:\n" + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") + "\n"
        }
        prompt += fresh
            ? "\nIt's a new app or agent, and this folder (~/\(folder)) is its home. If one of my apps in ~ is close to it, follow how that one is laid out and built (its build.sh and README); otherwise keep it small and simple, with a build.sh."
            : "\nThe code for \(app) is in this folder (~/\(folder)). Read enough of it to fit in with how it's written, then make the change."
        prompt += """


        Then build it the way this project builds (its build.sh, package.json scripts or tests) and fix whatever \
        breaks until it builds cleanly. Work only in this folder. Don't commit, push, tag, release, install or \
        launch anything, and don't bump the version: I'll review the changes and ship them myself.

        Reply with: ok (true only when the change is made and it builds), summary (what you built, 1 to 3 \
        sentences), stepsDone (the numbers of the build steps above that are now done), tryIt (how to try it, one \
        sentence), files (the files you changed or added), blocker (when ok is false, what stopped you and what I \
        need to do; else "").
        """
        if !Edition.buildNote.isEmpty { prompt += "\n\n" + Edition.buildNote }

        let model = Edition.model(Settings.model)
        let session = UUID().uuidString.lowercased()
        let args = ["ideaforge", "-p", "--output-format", "stream-json", "--verbose", "--session-id", session,
                    "--disable-slash-commands", "--setting-sources", "project", "--settings", AI.authSettings().path,
                    "--strict-mcp-config", "--permission-mode", "acceptEdits", "--allowedTools", "Bash",
                    "--disallowedTools"] + denied
            + ["--max-budget-usd", budget, "--json-schema", schema, "--model", model, prompt]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", #"export PATH="$HOME/.local/bin:$HOME/.devbar/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; exec claude "$@""#] + args
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        var env = ProcessInfo.processInfo.environment.filter {
            !["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID"].contains($0.key)
        }
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = FileHandle.nullDevice
        let job = Job(p, dir)
        do { try p.run() } catch { return fail("Couldn't start Claude: \(error.localizedDescription)") }
        jobs[id] = job
        let started = Date()

        // The whole run is kept next to the build scripts, for when something needs a closer look.
        let logURL = Store.shared.support.appendingPathComponent("build/idea-\(n)-auto.jsonl")
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)

        let killer = DispatchWorkItem { if p.isRunning { job.timedOut = true; p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(minutes * 60), execute: killer)
        DispatchQueue.global().async {
            var e = Data(), result: [String: Any]?, resultLine = Data()
            let g = DispatchGroup()
            g.enter(); DispatchQueue.global().async { e = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
            var buf = Data()
            while true {
                let chunk = out.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                log?.write(chunk)
                buf.append(chunk)
                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = Data(buf[buf.startIndex..<nl])
                    buf = Data(buf[buf.index(after: nl)...])
                    guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    if o["type"] as? String == "result" { result = o; resultLine = line }
                    else if let s = describe(o) { DispatchQueue.main.async { progress(s) } }
                }
            }
            p.waitUntilExit()
            killer.cancel()
            g.wait()
            try? log?.close()
            DispatchQueue.main.async {
                jobs[id] = nil
                if !resultLine.isEmpty { Edition.logUsage(task: "Auto-build", model: model, output: resultLine) }
                var r = (result?["structured_output"] as? [String: Any]) ?? [:]
                r["dir"] = dir; r["folder"] = folder; r["fresh"] = fresh; r["session"] = session
                r["minutes"] = Int((Date().timeIntervalSince(started) / 60).rounded())
                if let c = result?["total_cost_usd"] as? Double { r["cost"] = c }
                if r["ok"] == nil {
                    var msg = ((result?["result"] as? String) ?? String(decoding: e, as: UTF8.self)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if result?["subtype"] as? String == "error_max_budget_usd" { msg = "Hit the $\(budget) spend cap for one build." }
                    if job.timedOut { msg = "It took longer than \(minutes) minutes, so it was stopped." }
                    if job.stopped { msg = "Stopped."; r["stopped"] = true }
                    r["ok"] = false
                    r["error"] = msg.isEmpty ? "Claude stopped without a reply (exit \(p.terminationStatus))." : String(msg.suffix(300))
                }
                done(r)
            }
        }
        return .success(["dir": dir, "folder": folder, "session": session])
    }

    static func stop(_ id: String) {
        guard let j = jobs[id] else { return }
        j.stopped = true
        j.process.terminate()
    }
    static func stopAll() { jobs.keys.forEach(stop) }

    /// One short line for the card, from a stream event: what Claude is doing right now.
    private static func describe(_ o: [String: Any]) -> String? {
        guard o["type"] as? String == "assistant",
              let parts = (o["message"] as? [String: Any])?["content"] as? [[String: Any]],
              let use = parts.last(where: { $0["type"] as? String == "tool_use" }) else { return nil }
        let input = use["input"] as? [String: Any] ?? [:]
        let file = ((input["file_path"] as? String) ?? "").split(separator: "/").last.map(String.init) ?? ""
        switch use["name"] as? String ?? "" {
        case "Read": return "Reading \(file)"
        case "Edit", "MultiEdit": return "Editing \(file)"
        case "Write": return "Writing \(file)"
        case "Grep", "Glob": return "Looking through the code"
        case "WebFetch", "WebSearch": return "Looking something up"
        case "StructuredOutput": return "Wrapping up"
        case "TodoWrite":
            let todos = input["todos"] as? [[String: Any]] ?? []
            let doneCount = todos.filter { $0["status"] as? String == "completed" }.count
            let now = todos.first { $0["status"] as? String == "in_progress" }
            let what = (now?["activeForm"] as? String) ?? (now?["content"] as? String) ?? "Planning"
            return todos.isEmpty ? "Planning" : "\(what) · \(doneCount)/\(todos.count)"
        case "Bash":
            let d = (input["description"] as? String) ?? ""
            return d.isEmpty ? "Running " + String(((input["command"] as? String) ?? "").prefix(50)) : d
        case let other: return other.isEmpty ? nil : other
        }
    }
}
