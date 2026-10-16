#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
cd "$PROJECT_DIR"
# Some Command Line Tools SwiftBuild versions omit TestingMacros from resolved plugins.
# Load the compiler's bundled macro library explicitly so a clean rebuild works too.
SWIFT_BIN="$(xcrun --find swiftc)"
TEST_MACROS="$(dirname "$SWIFT_BIN")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
TEST_OPTIONS=()
if [ -f "$TEST_MACROS" ]; then
    TEST_OPTIONS=(-Xswiftc -load-plugin-library -Xswiftc "$TEST_MACROS")
fi
swift test "${SWIFT_OPTIONS[@]}" --disable-xctest --enable-swift-testing "${TEST_OPTIONS[@]}"
