#!/bin/bash
# Builds the app and publishes it as a GitHub release with a ready-to-run download.
# Usage: ./release.sh 2.0   (needs the GitHub CLI, logged in)
set -euo pipefail
cd "$(dirname "$0")"
export VERSION=${1:?usage: ./release.sh <version>}
./build-app.sh --no-install
OUT=build/release; rm -rf "$OUT"; mkdir -p "$OUT/dmg"
# Zip: the simplest download.
ditto -c -k --keepParent "build/Dhaka Sky.app" "$OUT/DhakaSky-$VERSION.zip"
# Disk image with a shortcut to Applications for drag-and-drop installing.
cp -R "build/Dhaka Sky.app" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Dhaka Sky" -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/DhakaSky-$VERSION.dmg" >/dev/null
gh release create "v$VERSION" "$OUT/DhakaSky-$VERSION.dmg" "$OUT/DhakaSky-$VERSION.zip" \
  --title "Dhaka Sky $VERSION" --notes-file docs/release-notes.md
