#!/bin/bash
# Builds a universal (Apple silicon + Intel) release "Dhaka Sky.app", with the screen saver inside it,
# and installs it into ~/Applications. Pass --no-install to only build it (used by release.sh).
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${VERSION:-2.0}
swift build -c release --arch arm64
swift build -c release --arch x86_64
./build-saver.sh --no-install
APP="build/Dhaka Sky.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/arm64-apple-macosx/release/DhakaSky .build/x86_64-apple-macosx/release/DhakaSky -output "$APP/Contents/MacOS/DhakaSky"
# The app installs this copy into ~/Library/Screen Savers on launch.
cp -R "build/Dhaka Sky.saver" "$APP/Contents/Resources/"
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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"
[[ "${1:-}" == "--no-install" ]] && { echo "Built: $APP"; exit 0; }
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Dhaka Sky.app"
cp -R "$APP" "$HOME/Applications/"
echo "Installed: $HOME/Applications/Dhaka Sky.app (it installs the screen saver when it starts)"
