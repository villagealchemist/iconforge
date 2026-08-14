#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="recursive bulk icon discovery"
source tests/test-common.sh
source ./lib/iconforge/common.sh
source ./lib/iconforge/discovery.sh
source ./lib/iconforge/library.sh

ROOT="$TEST_DIR/_explicit-root"
VALID="$TEST_DIR/valid.icns"
mkdir -p "$ROOT/nested" "$ROOT/.hidden" "$ROOT/_private" "$ROOT/App.app" "$ROOT/Upper.APP" \
  "$ROOT/generated.iconset" "$ROOT/Generated.ICONSET"
make_test_icns "$TEST_IMAGE1" "$VALID"
cp "$VALID" "$ROOT/Café Studio.icns"
cp "$VALID" "$ROOT/nested/Second App.icns"
cp "$VALID" "$ROOT/.hidden/Hidden.icns"
cp "$VALID" "$ROOT/_private/Private.icns"
cp "$VALID" "$ROOT/.Hidden File.icns"
cp "$VALID" "$ROOT/_Private File.icns"
cp "$VALID" "$ROOT/App.app/Bundled.icns"
cp "$VALID" "$ROOT/Upper.APP/Upper Bundled.icns"
cp "$VALID" "$ROOT/generated.iconset/Generated.icns"
cp "$VALID" "$ROOT/Generated.ICONSET/Upper Generated.icns"
cp "$VALID" "$ROOT/nested/Second App_ugly.icns"
cp "$VALID" "$ROOT/nested/Second App_UGLY.ICNS"
ln -s "$VALID" "$ROOT/Linked.icns"

scan_icon_library "$ROOT"
[[ "${#ICON_LIBRARY_FILES[@]}" -eq 2 ]] || { test_fail "Expected 2 eligible ICNS files, got ${#ICON_LIBRARY_FILES[@]}"; exit 1; }
[[ "${ICON_LIBRARY_KEYS[0]}" == "Café Studio" ]] || { test_fail "Unicode filename key was not preserved"; exit 1; }
[[ "${ICON_LIBRARY_KEYS[1]}" == "Second App" ]] || { test_fail "Nested filename key was not preserved"; exit 1; }
[[ "${ICON_LIBRARY_NORMALIZED_KEYS[0]}" == "café studio" ]] || { test_fail "Unicode normalization mismatch"; exit 1; }

for rejected_root in "$TEST_DIR/.hidden-root" "$TEST_DIR/Icons.APP" "$TEST_DIR/Icons.ICONSET"; do
  mkdir -p "$rejected_root"
  cp "$VALID" "$rejected_root/Eligible.icns"
  set +e
  scan_icon_library "$rejected_root" >"$TEST_DIR/rejected-root.log" 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || { test_fail "Unsafe bulk root was accepted: $rejected_root"; exit 1; }
  [[ "${#ICON_LIBRARY_FILES[@]}" -eq 0 ]] || { test_fail "Rejected root retained an icon manifest"; exit 1; }
done

test_pass "$TEST_NAME passed"
