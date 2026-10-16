#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/Codex Usage.app"
if [ ! -x "$APP_DIR/Contents/MacOS/CodexUsage" ]; then
    /bin/bash "$PROJECT_DIR/scripts/build.sh"
fi
open "$APP_DIR"
