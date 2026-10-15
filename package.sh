#!/bin/bash
# Packages Idea Forge into dist/IdeaForge-<version>.dmg, a drag-to-Applications installer.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh --universal
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" IdeaForge.app/Contents/Info.plist)
DMG="dist/IdeaForge-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R IdeaForge.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me First.txt" <<'TXT'
Installing Idea Forge

1. Drag Idea Forge onto the Applications folder.
2. Open Idea Forge from Applications. It isn't notarized by Apple, so the first time macOS
   says it can't be verified: go to System Settings > Privacy & Security, scroll down,
   click "Open Anyway", and confirm. You only need to do this once.
3. Idea Forge lives in the menu bar as 💡 (with how many ideas are pending).
   Click it > Open Board to see your ideas, drop in a thought, and drag cards along.
   Press ⌃⌥N anywhere to jot a thought without opening the board.
4. (Optional) Pick an AI in ⚙︎ Settings: Claude Code, Anthropic, OpenAI, Gemini, OpenRouter,
   Ollama (free, runs on your Mac) or any OpenAI-compatible server. API keys go in your Mac's
   Keychain. The AI turns thoughts into cards, sparks ideas for your challenges and suggests
   what to build next. The board works fine without one.

Idea Forge never reads your screen, browser or other apps.
Your ideas stay on this Mac, in ~/Library/Application Support/IdeaForge/ideas.json
(or a folder you pick in Settings, such as iCloud Drive).
Full guide: https://github.com/Sravankumartangudu/idea-forge#readme
TXT

mkdir -p dist
rm -f "$DMG"
hdiutil create -quiet -volname "Idea Forge" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
echo "Packaged $(pwd)/$DMG"
