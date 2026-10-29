# Changelog

## 1.4.0 — 2026-10-29

- **🎨 Style** in Settings: the board can wear one of 14 designs (Standard, Skeuomorphic, Flat, Material,
  Neumorphic, Glassmorphism, Liquid Glass, Claymorphism, Neo-brutalism, Swiss minimal, Bento grid, Retro,
  Aurora, Cyber). Each has a light and a dark look, so Appearance still applies. It changes at once.
- With [Nexus](https://github.com/Sravankumartangudu/nexus) 1.12 installed, the Style can also be picked in
  the common settings (🎨 Style per App); both always show the same one.

## 1.3.2 — 2026-10-17

- A card whose 🚀 Deploy stopped short but whose change got installed anyway (for example finished by hand)
  now reads **✅ Finished outside the deploy · installed x.y**, and the old error is folded under
  "Where the deploy stopped" instead of showing in red.
- 🚀 Deploy's install step is surer: it knows the project's own scripts may quit and replace the app, and
  deploying Idea Forge itself swaps the app in the background after the deploy replies, so quitting the app
  doesn't cut the deploy off before the install.

## 1.3.1 — 2026-10-17

- 🚀 **Deploy** is now the first button in a built card's bottom bar, so it's easy to find; ⚡ Auto-build reads
  ⚡ Rebuild there once a build is done.
- 🚀 Deploy can now install an app that's running: it quits it with pkill and copies the new one over it.
  Before, it tried osascript and rm -rf, which are blocked, so the install stopped.

## 1.3.0 — 2026-10-17

- ⚡ **Auto-build no longer means shipped.** A finished build stays in Building, marked **✅ Built · not
  deployed**, instead of jumping to Shipped. Cards an earlier version moved to Shipped go back to Building
  until they're really installed.
- **Deploy tracker**: built cards show where the change has got to: **Built › Committed › Pushed › Released ›
  Installed**. It's read from the app folder's git, its tags and the installed app, and checked again every
  minute. Projects without a remote, tags or an app skip those steps.
- 🚀 **Deploy** (click twice to confirm): Claude Code commits, pushes, tags, releases and installs the change
  the way that project ships, following its README, changelog and scripts and the git name and host the repo already uses. It stages files by name,
  checks the remote's tags before tagging, and can't force-push, rewrite history or delete. Each deploy
  stops at $5 or 45 minutes, and **⏹ Stop deploy** stops it.
- Once the installed app has the change, the card moves to Shipped by itself. Shipping it yourself works
  too: the tracker follows along either way.

## 1.2.1 — 2026-10-17

- Starting a build (⚡ Auto-build, or 🚀 Claude Code / Codex) now closes the card, so you see it land in
  Building, where it flashes.

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
