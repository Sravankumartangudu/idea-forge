// Edition.swift — what makes this the personal Idea Forge (github.com).
//
// The work edition builds from the same core — main.swift, AI.swift, Extras.swift, board.html,
// demo.json — with its own Edition.swift. Everything that differs between the two lives in this one file.
// This edition is for anyone: pick any AI (Claude Code, Anthropic, OpenAI, Gemini, OpenRouter, Ollama or
// an OpenAI-compatible server). It never reads your screen, browser or other apps.

import AppKit
import WebKit

enum Edition {
    static let name = "Idea Forge"
    /// Menu-bar emoji (unique across the fleet).
    static let symbol = "💡"
    /// Folder in Application Support, and the window's saved-frame name.
    static let folder = "IdeaForge"
    /// "personal" or "work": picks the board's colours.
    static let flavor = "personal"
    static let repoURL = "https://github.com/Sravankumartangudu/idea-forge"
    static let repoLabel = "GitHub"
    /// Where the update check looks ("" = no update check).
    static let releasesAPI = "https://api.github.com/repos/Sravankumartangudu/idea-forge/releases/latest"
    /// Let people keep ideas.json in a folder they pick (iCloud Drive, Dropbox…).
    static let dataFolderChoice = true

    /// The AIs on offer (ids from AI.all), in picker order.
    static let providers = ["claude-code", "anthropic", "openai", "gemini", "openrouter", "ollama", "compatible"]

    /// Claude Code's model picker: (stored value, label).
    static var models: [(String, String)] { [("haiku", "Haiku · fast"), ("sonnet", "Sonnet"), ("opus", "Opus · best")] }
    static var defaultModel: String { "sonnet" }
    /// The model a Claude Code task runs on, from the picker's value.
    static func model(_ own: String) -> String { own }

    /// Appearance picker: (stored value, label).
    static var appearances: [(String, String)] { [("system", "System"), ("light", "Light"), ("dark", "Dark")] }
    static var defaultAppearance: String { "system" }
    /// "system", "light" or "dark", from the picker's value.
    static func appearance(_ own: String) -> String { own }

    /// Extra guidance for every AI task, after the shared persona.
    static let personaNote = ""
    /// Extra guidance for a Claude Code or Codex build session.
    static let buildNote = ""

    /// Offer 📎 page reading (the browser tab, plus the systems below) behind a Settings switch that starts
    /// off. Never in this edition: it doesn't look at your screen or browser at all.
    static let pageReading = false

    /// Connected systems the AI can read on its own (shown on the board); none here.
    static let toolsLabel = ""
    /// True when a page is read with the edition's own tools instead of its text. Never here.
    static func readsWithTools(_ url: String) -> Bool { false }
    /// Claude Code arguments that give a task read-only tools; nil = no tools.
    static func toolArgs(_ dir: URL) -> [String]? { nil }
    /// Extra instructions when a page is read with tools, and for 🔍 Find challenges with tools.
    static let captureNote = ""
    static let findNote = ""

    /// Names suggested in "Who can help" besides the ones you add in Settings.
    static func people() -> [String] { [] }

    /// Called once at launch; `changed` re-applies settings when something outside the app changes them.
    static func setUp(changed: @escaping () -> Void) {
        FleetStyles.start(app: name) { changed() }
    }
    /// Called after the Claude Code model picker changes.
    static func modelChanged() {}
    /// Called after every Claude Code call, with the CLI's JSON output.
    static func logUsage(task: String, model: String, output: Data) {}
    /// Called once the menu-bar item is set up.
    static func started() {}
    /// An extra item for the bottom of the menu, or nil.
    static func menuItem() -> NSMenuItem? { nil }
    /// Called for every command the board sends.
    static func boardAction(_ cmd: String) {}
    /// The 14 design styles (FleetStyles): the board wears the pick; Settings › Style and Nexus › 🎨 Style per App change it.
    static var extraState: [String: Any] {
        ["uiStyle": FleetStyles.pick, "styles": FleetStyles.list, "styleFleet": FleetStyles.parentInstalled,
         "styleWhere": "🎨 Style per App"]
    }
    /// A Settings key the core doesn't handle itself.
    static func setting(_ key: String, _ value: Any?) {
        if key == "style", let v = value as? String { FleetStyles.choose(v) }
    }
    /// The board's web view, right after it is created.
    static func webCreated(_ web: WKWebView) { FleetStyles.wear(web) }
}
