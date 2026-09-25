#!/usr/bin/env bash
# Integration checks using the bundled engine; works with Command Line Tools, no Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
chmod +x Resources/bin/7zz
swiftc -parse-as-library -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  Sources/SevenMac/Core/*.swift Sources/SevenMac/Model/BrowserModel.swift \
  Tests/SevenMacTests/ArchiveTests.swift -o .build/checks/archive-tests
.build/checks/archive-tests
