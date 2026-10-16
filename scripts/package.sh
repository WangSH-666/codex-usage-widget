#!/bin/bash
# Build a portable app archive and a checksum for a GitHub Release.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [ "${1:-}" != "--skip-build" ]; then bash scripts/build.sh; fi
VERSION="$(tr -d '[:space:]' < VERSION)"
ARCH="$(uname -m)"
APP_DIR="$PROJECT_DIR/dist/Codex Usage.app"
ARCHIVE="Codex-Usage-${VERSION}-macOS-${ARCH}.zip"
codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$PROJECT_DIR/dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
printf 'Release archive: %s\n' "$PROJECT_DIR/dist/$ARCHIVE"
