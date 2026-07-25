#!/usr/bin/env bash
# Converts Resources/AppIcon.iconset into Resources/AppIcon.icns (macOS only).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
echo "==> Wrote $ROOT/Resources/AppIcon.icns"
