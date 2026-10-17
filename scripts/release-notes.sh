#!/bin/bash
# Use this version's changelog entry as the GitHub Release body.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
awk -v version="$RELEASE_VERSION" '
/^## / {
    if (printing) exit
    if ($2 == version) { printing = 1; found = 1 }
    next
}
printing { print }
END { if (!found) exit 1 }
' "$PROJECT_DIR/CHANGELOG.md"
