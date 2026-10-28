#!/bin/bash
# Builds "Dhaka Sky.saver" (the same scene as a screen saver, which macOS can show over the lock screen)
# and installs it into ~/Library/Screen Savers.
set -euo pipefail
cd "$(dirname "$0")"
SRC=Sources/DhakaSky
# The scene, art and weather code only; the app shell (menu, windows, sound, settings UI) stays out.
FILES=()
for f in "$SRC"/*.swift; do
  case "$(basename "$f")" in
    main.swift|AppDelegate.swift|LockScreen.swift|SettingsWindow.swift|WallpaperWindow.swift|SoundScape.swift|Snapshot.swift|CustomImages.swift) ;;
    *) FILES+=("$f") ;;
  esac
done
SAVER="build/Dhaka Sky.saver"
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
# Universal binary, so the saver loads on Apple silicon and Intel Macs.
for arch in arm64 x86_64; do
  swiftc -O -module-name DhakaSkySaver -emit-library -target $arch-apple-macos14.0 \
    -o "build/saver-$arch" "${FILES[@]}" Saver/SaverView.swift \
    -framework ScreenSaver -framework SpriteKit -framework AppKit -framework Vision
done
lipo -create build/saver-arm64 build/saver-x86_64 -output "$SAVER/Contents/MacOS/DhakaSky"
rm -f build/saver-arm64 build/saver-x86_64
sips -z 512 512 Resources/AppIcon.png --out "$SAVER/Contents/Resources/thumbnail@2x.png" >/dev/null
sips -z 256 256 Resources/AppIcon.png --out "$SAVER/Contents/Resources/thumbnail.png" >/dev/null
cat > "$SAVER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.shawon.DhakaSky.saver</string>
  <key>CFBundleName</key><string>Dhaka Sky</string>
  <key>CFBundleExecutable</key><string>DhakaSky</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>NSPrincipalClass</key><string>DhakaSkySaverView</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force -s - "$SAVER"
mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$HOME/Library/Screen Savers/Dhaka Sky.saver"
cp -R "$SAVER" "$HOME/Library/Screen Savers/"
echo "Installed: $HOME/Library/Screen Savers/Dhaka Sky.saver"
