#!/usr/bin/env bash
# Builds SevenMac.app for Apple Silicon (arm64) and bundles the 7zz engine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SevenMac"
CONFIG="release"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Building Swift package (arm64, $CONFIG)"
swift build --package-path "$ROOT" -c "$CONFIG" --arch arm64

BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" --arch arm64 --show-bin-path)/$APP_NAME"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [ -f "$ROOT/Resources/bin/7zz" ]; then
  cp "$ROOT/Resources/bin/7zz" "$APP/Contents/Resources/bin/7zz"
  chmod +x "$APP/Contents/Resources/bin/7zz"
  xattr -dr com.apple.quarantine "$APP/Contents/Resources/bin/7zz" 2>/dev/null || true
else
  echo "!! Resources/bin/7zz missing - the app will fall back to /opt/homebrew/bin/7zz"
fi

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "   (no icon yet - run scripts/make_icon.sh first if you want one)"
fi

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "   codesign skipped"

echo "==> Done: $APP"
echo "    open \"$APP\""
