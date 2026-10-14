#!/bin/bash
# Installs the latest Mr. Box into /Applications (or ~/Applications) and opens it.
#   curl -fsSL https://raw.githubusercontent.com/praneet-admin/mr-box/main/install.sh | bash
#
# Downloading with curl means macOS doesn't tag the app as "downloaded from the internet",
# so it opens without the unidentified-developer warning (Mr. Box isn't notarised by Apple yet).
set -euo pipefail

URL="https://github.com/praneet-admin/mr-box/releases/latest/download/Mr-Box-macOS.zip"
DEST="${MRBOX_INSTALL_DIR:-/Applications}"
mkdir -p "$DEST" 2>/dev/null || true
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "📦 Downloading Mr. Box…"
curl -fsSL "$URL" -o "$TMP/mrbox.zip"
ditto -x -k "$TMP/mrbox.zip" "$TMP"

pkill -x MrBox 2>/dev/null || true
rm -rf "$DEST/Mr Box.app"
mv "$TMP/Mr Box.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/Mr Box.app" 2>/dev/null || true

echo "✅ Installed to $DEST/Mr Box.app"
[ -n "${MRBOX_NO_OPEN:-}" ] || open "$DEST/Mr Box.app"
echo "   Mr. Box is in the top-right corner. Click Allow when he asks to see your folders."
command -v claude >/dev/null || [ -x "$HOME/.local/bin/claude" ] || \
  echo "   Tip: Organise needs the Claude Code CLI (https://claude.com/claude-code). Search works without it."
