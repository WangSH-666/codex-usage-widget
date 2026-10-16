#!/bin/bash
# Keep compiler and SwiftPM caches inside this project, including sandboxed builds.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swift-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
SWIFT_OPTIONS=(--disable-sandbox --scratch-path "$PROJECT_DIR/.build" --cache-path "$PROJECT_DIR/.build/swiftpm/cache" --config-path "$PROJECT_DIR/.build/swiftpm/config" --security-path "$PROJECT_DIR/.build/swiftpm/security")
