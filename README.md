# 💡 Idea Forge

A Mac menu-bar backlog for the apps and AI agents you want to build next.

Drop in a messy thought. Claude turns it into a clear card with a title, what it does, why it matters,
build steps and who could help. Then drag the card from **Inbox → Shaped → Building → Shipped**.

![Idea Forge board](docs/screenshots/board-light.png)

## Install

1. Download **IdeaForge-x.y.z.dmg** from [Releases](https://github.com/Sravankumartangudu/idea-forge/releases/latest).
2. Open it and drag **Idea Forge** onto **Applications**.
3. Open it from Applications. Apple hasn't notarized it, so the first time macOS says it can't be
   verified. To open it: **System Settings › Privacy & Security** → scroll down → **Open Anyway**.
   You only do this once.
4. Optional: install [Claude Code](https://claude.com/claude-code) and sign in, so Idea Forge can shape
   your thoughts. Without Claude, everything else works and you fill in cards by hand.

Idea Forge lives in the menu bar as 💡 next to your pending count. It needs macOS 13 or later and
runs on Apple silicon and Intel.

## Using it

| | |
|---|---|
| **Add a thought** | Type anything in the box at the top and press Return. If it holds several ideas, Claude splits them into separate cards. Turn off ✨ Shape to add a card as typed. |
| **Move cards** | Drag a card between columns, or up and down to set the order. You can also change the stage in the card's drawer. |
| **Open a card** | Click it. You can edit the title, type, priority, where it ships, which app it's for, steps, who can help and tags. |
| **Remove** | Use 🗑 Remove in the drawer, or **Select** several cards and remove them together. Removed cards go to the 🗑 bin, where you can restore them. |
| **Checklist** | 📋 Checklist copies all pending ideas as a Markdown checklist (`- [ ] #3 Build a receipt scanner agent`). |
| **Copy brief** | Copies one idea as a short Markdown brief to send to someone who can help. |
| **Find** | Press `/` to search. You can also filter by type, where it ships, or app. |

![A card's drawer](docs/screenshots/drawer.png)

### Columns

💭 **Inbox** holds raw thoughts. 📐 **Shaped** cards are clear and ready to pick up. 🔨 **Building** cards are in progress.
🚀 **Shipped** cards are done. 🧊 **Parked** cards are for not now, maybe later.

### Card fields

- **Type**: 🤖 New agent, ✨ Enhancement, 🐞 Fix or 🧹 Chore.
- **Priority**: 🔥 High, ⚡ Medium or 🌱 Low.
- **Where it ships**:
  - 🏠 **Personal**: a public repo that anyone can use and help build.
  - 💼 **Work**: your work's git.
  - 🔒 **Local**: stays on this Mac.
- **For app**: the app an enhancement is for. Leave it empty for a brand-new agent. Idea Forge suggests
  apps it finds in your home folder: any folder with a `build.sh` or `package.json`. Where an app ships comes from its git remote: github.com is personal, any other host is work, and no remote is local.
- **🤝 Who can help**: people to ask or hand the idea to. They show as avatars on the card.

### Settings (⚙︎)

- **Appearance**: System, Light or Dark.
- **Shape new thoughts automatically**: on by default.
- **Claude model**: Haiku, Sonnet (the default) or Opus.
- **Menu bar**: show or hide the pending count, and launch at login.

![Dark mode](docs/screenshots/board-dark.png)

## Your data

Your ideas live in a single JSON file on your Mac:

```
~/Library/Application Support/IdeaForge/ideas.json
```

Idea Forge watches the file, so edits made by another tool or an AI assistant appear on the board right away.
Nothing leaves your Mac, except the text of a thought you choose to shape. That text goes to Claude
through your own Claude Code sign-in.

```json
{ "version": 1, "ideas": [ {
  "id": "…", "n": 3, "title": "Build a receipt scanner agent",
  "summary": "…", "why": "…", "raw": "the thought as you typed it",
  "type": "agent | enhancement | fix | chore", "status": "inbox | shaped | building | shipped | parked | removed",
  "priority": "high | med | low", "home": "personal | work | local", "app": "",
  "steps": [ { "t": "Read text from a photo", "done": false } ],
  "helpers": ["Priya"], "tags": ["finance"], "order": 3,
  "created": "2026-10-03T09:00:00Z", "updated": "…"
} ] }
```

`n` is the card's number, shown as `#3`. A new card gets one more than the highest number on the board.

## Build from source

```bash
git clone https://github.com/Sravankumartangudu/idea-forge && cd idea-forge
./build.sh            # builds IdeaForge.app for this Mac
./package.sh          # universal build + dist/IdeaForge-<version>.dmg
open IdeaForge.app --args --demo     # sample board, never saves
```

| Flag | What it does |
|---|---|
| `--board` | Opens the board at launch. |
| `--demo` | Loads `demo.json` into memory and never writes to disk. Useful for screenshots. |
| `--checklist` | Prints the pending list as a Markdown checklist and quits. |

The app is plain Swift and AppKit. The board is a single `board.html` page in a WKWebView, and there are
no dependencies. Everything that sets this edition apart is in `Edition.swift`.

## License

[MIT](LICENSE) © 2026 Sravankumar Tangudu
