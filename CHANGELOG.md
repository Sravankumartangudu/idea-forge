# Changelog

## 1.2.0 — 2026-10-17

- ⚡ **Auto-build**: one button in a card's drawer, and Claude Code builds the idea on its own in the
  background. It works in the app's folder for an enhancement, or in a new folder in ~ for a new agent.
  The card moves to Building straight away and shows what Claude is doing. When the project builds cleanly,
  the card moves to Shipped and the steps it finished are ticked. The drawer shows a summary, how to try
  it, the files it changed and **💬 Continue in Terminal**. If it can't finish, the card stays in Building
  with the reason.
- Guard rails: Auto-build skips your Claude settings and MCP servers. It can't commit, push, tag, release,
  install or reach the network, and each build stops at $5 or 45 minutes. **⏹ Stop build** stops it, and
  quitting the app stops it too. Nothing is committed, so you review the changes and ship them yourself.

## 1.1.2 — 2026-10-16

- The Stages | Groups switch now sits apart from the Ideas, Challenges and Matrix tabs, with a gap and a
  divider, so it no longer looks like a fourth and fifth tab.

## 1.1.1 — 2026-10-16

- Fixes a crash at launch that stopped the board from opening when Nexus or Citadel was running.

## 1.1.0 — 2026-10-15

- 🧗 **Challenges** tab: write down the problems that slow you down. The AI shapes each one and sparks ideas
  to solve it. Columns are Open (hottest first), Has ideas and Solved; a challenge is solved when its idea
  ships. Hitting the same problem again adds a hit instead of a duplicate.
- 🔍 **Find challenges** suggests challenges from the TODO/FIXME notes in your app folders and the open issues
  on your public GitHub repos. It can run once a day.
- **Pick your AI**: Claude Code, the Anthropic API, OpenAI, Google Gemini, OpenRouter, Ollama or any
  OpenAI-compatible server. Model lists load live from the provider and refresh daily. Keys stay in the
  Keychain. ⚡ Test connection checks the setup.
- **Groups**: keep the many ideas for one plan together. There's a Stages | Groups switch, ＋ New group, the AI
  fills in the group, and clicking a group chip filters the board to it.
- **Who added it**: every card shows 👤 You, ✨ AI or 🤝 Teammate, and you can filter by it.
- ✨ **Suggested** tray: what the AI comes up with waits there until you keep or dismiss it.
- ⊞ **Matrix** tab: impact × effort squares (Quick wins, Big bets, Fill-ins, Money pits). Drag cards into
  them, or let the AI place them.
- ⌃⌥N **quick capture** from anywhere, with an ⌃⌥⇧ option for when another app has the keys.
- 💬 Ask, 🎯 What next? and 🔁 Looks like #n now work with any AI you pick.
- 🚀 Build opens Claude Code or Codex in Terminal. 🐙 Open as issue files a card on the app's GitHub repo.
- Weekly digest notification, an update check against GitHub releases, and **Choose folder…** for the ideas
  file (for example iCloud Drive).
- Idea Forge never reads your screen, browser or other apps.

## 1.0.0 — 2026-10-15

First release.

- 💡 Menu-bar app showing your pending count, with a board window of five columns: Inbox, Shaped, Building, Shipped and Parked.
- Drop in a messy thought and Claude Code shapes it into cards: title, what it does, why it matters, type, priority, where it ships, which app it's for, build steps, who can help and tags. Several ideas in one thought become several cards.
- Drag cards between columns and reorder them. Build steps have a progress bar, 🤝 "Who can help" names show as avatars, and you can search and filter.
- 🗑 Remove, multi-select, and a bin with Restore.
- 📋 Copy the pending list as a Markdown checklist, or copy one idea as a brief to share.
- Ideas live in `~/Library/Application Support/IdeaForge/ideas.json` and reload live when edited elsewhere.
- Settings: appearance (System, Light or Dark), auto-shape, Claude model, menu-bar count and launch at login.
- Drag-to-Applications DMG for Apple silicon and Intel.
