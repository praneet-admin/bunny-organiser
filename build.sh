#!/bin/bash
# Builds "Bunny Organiser.app" into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/Bunny Organiser.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O main.swift -o "$APP/Contents/MacOS/BunnyOrganiser" -framework Cocoa -framework WebKit
cp index.html mascot.png "$APP/Contents/Resources/"

# App icon from the mascot
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s mascot.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) mascot.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Bunny Organiser</string>
  <key>CFBundleDisplayName</key><string>Bunny Organiser</string>
  <key>CFBundleIdentifier</key><string>com.praneet.bunny-organiser</string>
  <key>CFBundleExecutable</key><string>BunnyOrganiser</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDownloadsFolderUsageDescription</key><string>Bunny Organiser files new downloads into your 2026 project folders.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Bunny Organiser files new Desktop items into your 2026 project folders.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Bunny Organiser files new documents into your 2026 project folders.</string>
</dict></plist>
PLIST

codesign --force --deep -s - "$APP"
echo "Built: $APP"
