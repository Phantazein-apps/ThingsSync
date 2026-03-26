#!/bin/bash
# ThingsSync installer — run with:
#   curl -fsSL https://raw.githubusercontent.com/Phantazein-apps/ThingsSync/main/install.sh | bash
set -e

APP="ThingsSync.app"
DEST="/Applications/$APP"
TMP="$(mktemp -d)"
ZIP="$TMP/ThingsSync.zip"
TAG="${1:-latest}"

echo ""
echo "  🔄 ThingsSync Installer"
echo "  Things 3 ↔ Notion Sync"
echo ""

# Download latest release
echo "  📥 Downloading..."
if [ "$TAG" = "latest" ]; then
    URL=$(curl -fsSL https://api.github.com/repos/Phantazein-apps/ThingsSync/releases/latest \
        | grep "browser_download_url.*\.zip" | head -1 | cut -d '"' -f 4)
else
    URL="https://github.com/Phantazein-apps/ThingsSync/releases/download/$TAG/ThingsSync-$TAG.zip"
fi

curl -fsSL -o "$ZIP" "$URL"

# Extract
echo "  📦 Installing to /Applications..."
cd "$TMP"
unzip -q "$ZIP"

# Kill existing
pkill -f "$APP" 2>/dev/null && sleep 1 || true

# Install
[ -d "$DEST" ] && rm -rf "$DEST"
cp -R "$APP" "$DEST"

# Remove quarantine flag
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# Cleanup
rm -rf "$TMP"

echo "  ✅ Installed!"
echo ""
echo "  🚀 Launching..."
open "$DEST"
echo ""
echo "  Look for the ✓ icon in your menu bar."
echo ""
