#!/usr/bin/env bash
# Quick debug run without packaging an .app bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift run --package-path "$ROOT" SevenMac
