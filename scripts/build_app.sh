#!/usr/bin/env bash
# Builds SevenMac.app for Apple Silicon (arm64) and bundles the 7zz engine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SevenMac"
CONFIG="release"
BUILD_DIR="$ROOT/build"
mkdir -p "$ROOT/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
APP="$BUILD_DIR/$APP_NAME.app"

bash "$ROOT/scripts/make_icon.sh"

echo "==> Building Swift package (arm64, $CONFIG)"
swift build --disable-sandbox --cache-path "$ROOT/.build/cache" --package-path "$ROOT" -c "$CONFIG" --arch arm64

BIN="$(swift build --disable-sandbox --cache-path "$ROOT/.build/cache" --package-path "$ROOT" -c "$CONFIG" --arch arm64 --show-bin-path)/$APP_NAME"

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
  echo "error: bundled 7zz is required for release builds" >&2
  exit 1
fi

cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cp "$ROOT/Resources/bin/License.txt" "$APP/Contents/Resources/7-Zip-License.txt"
cp "$ROOT/Resources/bin/readme.txt" "$APP/Contents/Resources/7-Zip-Readme.txt"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/SevenMac-License.txt"
echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Done: $APP"
echo "    open \"$APP\""
