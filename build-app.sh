#!/bin/bash
# Builds a release DhakaSky.app and installs it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="build/Dhaka Sky.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DhakaSky "$APP/Contents/MacOS/DhakaSky"
# App icon from Resources/AppIcon.png (regenerate with Resources/make-icon.swift).
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.shawon.DhakaSky</string>
  <key>CFBundleName</key><string>Dhaka Sky</string>
  <key>CFBundleDisplayName</key><string>Dhaka Sky</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>DhakaSky</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Dhaka Sky.app"
cp -R "$APP" "$HOME/Applications/"
echo "Installed: $HOME/Applications/Dhaka Sky.app"
./build-saver.sh
