#!/bin/bash
# Builds "Mr Box.app" into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/Mr Box.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O main.swift -o "$APP/Contents/MacOS/MrBox" -framework Cocoa -framework WebKit
cp index.html mrbox.png organize.py "$APP/Contents/Resources/"

# App icon from Mr. Box
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s mrbox-icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) mrbox-icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Mr. Box</string>
  <key>CFBundleDisplayName</key><string>Mr. Box</string>
  <key>CFBundleIdentifier</key><string>com.praneet.mr-box</string>
  <key>CFBundleExecutable</key><string>MrBox</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDownloadsFolderUsageDescription</key><string>Mr. Box files new downloads into your 2026 project folders.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Mr. Box files new Desktop items into your 2026 project folders.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Mr. Box files new documents into your 2026 project folders.</string>
</dict></plist>
PLIST

codesign --force --deep -s - "$APP"
echo "Built: $APP"
