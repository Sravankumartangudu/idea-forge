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
4. (Optional) Install Claude Code (https://claude.com/claude-code) and sign in, so Idea Forge
   can turn messy thoughts into clear cards. The board works fine without it.

Your ideas stay on this Mac, in ~/Library/Application Support/IdeaForge/ideas.json.
Full guide: https://github.com/Sravankumartangudu/idea-forge#readme
TXT

mkdir -p dist
rm -f "$DMG"
hdiutil create -quiet -volname "Idea Forge" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
echo "Packaged $(pwd)/$DMG"
