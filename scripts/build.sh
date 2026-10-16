#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
cd "$PROJECT_DIR"
swift build "${SWIFT_OPTIONS[@]}" -c release -debug-info-format none
PRODUCT_DIR="$(swift build "${SWIFT_OPTIONS[@]}" -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Codex Usage.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PRODUCT_DIR/CodexUsage" "$APP_DIR/Contents/MacOS/CodexUsage"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
swift "$PROJECT_DIR/scripts/make-icon.swift" "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
printf '\n已构建：%s\n' "$APP_DIR"
