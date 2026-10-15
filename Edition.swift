// Edition.swift — what makes this the personal Idea Forge (github.com).
//
// The work edition (Idea Forge Work, on work git) builds from the same core — main.swift, board.html,
// demo.json — with its own Edition.swift, which turns on the extra Claude tools and follows Citadel's
// shared settings. Everything that differs between the two lives in this one file.

import Foundation

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

    /// The extra Claude tools on the board: 💬 Ask Claude, 🎯 What next, 🚀 Build in Claude Code, duplicate spotting.
    static let claudeTools = false

    /// Model picker: (stored value, label).
    static var models: [(String, String)] { [("haiku", "Haiku · fast"), ("sonnet", "Sonnet"), ("opus", "Opus · best")] }
    static var defaultModel: String { "sonnet" }
    /// The model a Claude task runs on, from the picker's value.
    static func model(_ own: String) -> String { own }

    /// Appearance picker: (stored value, label).
    static var appearances: [(String, String)] { [("system", "System"), ("light", "Light"), ("dark", "Dark")] }
    static var defaultAppearance: String { "system" }
    /// "system", "light" or "dark", from the picker's value.
    static func appearance(_ own: String) -> String { own }

    /// Extra guidance for the shaper, after the shared persona.
    static let personaNote = ""
    /// Extra guidance for a Claude Code build session.
    static let buildNote = ""

    /// Names suggested in "Who can help" (and given to Claude when you ask who could help).
    static func people() -> [String] { [] }

    /// Called once at launch; `changed` re-applies settings when something outside the app changes them.
    static func setUp(changed: @escaping () -> Void) {}
    /// Called after the model picker changes.
    static func modelChanged() {}
    /// Called after every Claude call, with the CLI's JSON output.
    static func logUsage(task: String, model: String, output: Data) {}
}
