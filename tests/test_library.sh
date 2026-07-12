#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="icon library resolution"
source tests/test_common.sh
source ./lib/iconforge/common.sh
source ./lib/iconforge/library.sh

assert_equals() {
  [[ "$1" == "$2" ]] || { echo "❌ Expected '$1' == '$2'"; exit 1; }
}

ICON_ROOT="$TEST_DIR/icon-root"
mkdir -p "$ICON_ROOT/code" "$ICON_ROOT/spotify" "$ICON_ROOT/chrome" "$ICON_ROOT/figma"

cp "$TEST_IMAGE1" "$ICON_ROOT/code/code.icns"
cp "$TEST_IMAGE1" "$ICON_ROOT/spotify/alt.icns"
cp "$TEST_IMAGE1" "$ICON_ROOT/chrome/one.icns"
cp "$TEST_IMAGE1" "$ICON_ROOT/chrome/two.icns"
cp "$TEST_IMAGE1" "$ICON_ROOT/figma/figma.png"

scan_icon_library "$ICON_ROOT"
assert_equals "${#ICON_LIBRARY_KEYS[@]}" "4"

resolve_icon_library_entry "$ICON_ROOT" "code"
assert_equals "$ICON_LIBRARY_RESOLUTION_STATUS" "ready"
assert_equals "$ICON_LIBRARY_RESOLVED_ICNS" "$ICON_ROOT/code/code.icns"

resolve_icon_library_entry "$ICON_ROOT" "spotify"
assert_equals "$ICON_LIBRARY_RESOLUTION_STATUS" "ready"
assert_equals "$ICON_LIBRARY_RESOLVED_ICNS" "$ICON_ROOT/spotify/alt.icns"

set +e
resolve_icon_library_entry "$ICON_ROOT" "chrome"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Ambiguous icon selection should fail"; exit 1; }
assert_equals "$ICON_LIBRARY_RESOLUTION_STATUS" "ambiguous-icns"

set +e
resolve_icon_library_entry "$ICON_ROOT" "figma"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ PNG-only icon should not be treated as ready"; exit 1; }
assert_equals "$ICON_LIBRARY_RESOLUTION_STATUS" "needs-forge"

echo "🎉 $TEST_NAME passed"
