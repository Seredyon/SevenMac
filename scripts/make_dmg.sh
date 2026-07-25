#!/bin/bash
# Packs build/SevenMac.app into a classic drag-to-Applications DMG.
# Run scripts/build_app.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/SevenMac.app"
DMG="build/SevenMac.dmg"
STAGE="build/dmg-stage"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found - run scripts/build_app.sh first" >&2
  exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "SevenMac" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Created $DMG"
