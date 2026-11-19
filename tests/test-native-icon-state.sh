#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="native icon persisted state"
source tests/test-common.sh

HELPER="$PWD/iconforge-native-icon/iconforge-native-icon"
APP="$PWD/$TEST_DIR/State Test.app"
ICON_FILE="$APP/"$'Icon\r'
VALID_ICON="$PWD/$TEST_DIR/valid.icns"
REPLACEMENT_ICON="$PWD/$TEST_DIR/replacement.icns"
OUTPUT="$TEST_DIR/output.log"

cleanup_state() {
  if [[ -d "$TEST_DIR" ]]; then
    chflags -R nouchg "$TEST_DIR" 2>/dev/null || true
  fi
  cleanup
}
trap 'cleanup_state || true' EXIT

expect_failure() {
  local status=0
  ICONFORGE_DIAGNOSTIC_CAPTURE=1 "$HELPER" "$@" >"$OUTPUT" 2>&1 || status=$?
  [[ "$status" -eq 1 ]] || {
    test_fail "Expected operation failure for $1, got status $status"
    cat "$OUTPUT"
    exit 1
  }
}

assert_output_contains() {
  grep -F -- "$1" "$OUTPUT" >/dev/null || {
    test_fail "Expected helper output to contain '$1'"
    cat "$OUTPUT"
    exit 1
  }
}

snapshot_icon() {
  xattr -px com.apple.FinderInfo "$APP"
  cksum "$ICON_FILE"
  xattr -px com.apple.FinderInfo "$ICON_FILE"
  xattr -px com.apple.ResourceFork "$ICON_FILE"
}

[[ -x "$HELPER" ]] || { test_fail "Native icon helper is not built: $HELPER"; exit 1; }
mkdir -p "$APP/Contents"
cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>org.iconforge.test.native-state</string>
  <key>CFBundleName</key><string>Native State Test</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
make_test_icns "$TEST_IMAGE1" "$VALID_ICON"
make_test_icns "$TEST_IMAGE2" "$REPLACEMENT_ICON"

"$HELPER" set "$APP" "$VALID_ICON"
"$HELPER" test "$APP"
"$HELPER" remove "$APP"
expect_failure test "$APP"
test_pass "Real AppKit set, verification, and removal work on a disposable app"

# The Finder flag and filename alone do not contain a usable icon.
touch "$ICON_FILE"
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$APP"
expect_failure test "$APP"
assert_output_contains "no usable Finder custom icon"

xattr -wx com.apple.ResourceFork 00000000 "$ICON_FILE"
expect_failure test "$APP"

# The declared data and map regions lie beyond this truncated resource header.
xattr -wx com.apple.ResourceFork 00000100000002000000000800000020 "$ICON_FILE"
expect_failure test "$APP"
test_pass "Empty and malformed resource forks are rejected"
rm "$ICON_FILE"
xattr -d com.apple.FinderInfo "$APP"

for locked_path in "$APP" "$ICON_FILE"; do
  display_path="${locked_path//$'\r'/\\r}"
  "$HELPER" set "$APP" "$VALID_ICON"
  snapshot_icon >"$TEST_DIR/before.txt"
  chflags uchg "$locked_path"

  expect_failure diagnose "$APP"
  assert_output_contains "locked"
  assert_output_contains "$display_path"
  snapshot_icon >"$TEST_DIR/after.txt"
  cmp "$TEST_DIR/before.txt" "$TEST_DIR/after.txt" || {
    test_fail "Diagnosis changed locked application icon data"
    exit 1
  }

  expect_failure set "$APP" "$REPLACEMENT_ICON"
  assert_output_contains "locked"
  assert_output_contains "$display_path"
  snapshot_icon >"$TEST_DIR/after.txt"
  cmp "$TEST_DIR/before.txt" "$TEST_DIR/after.txt" || {
    test_fail "Setting an icon changed locked application icon data"
    exit 1
  }

  expect_failure remove "$APP"
  assert_output_contains "locked"
  assert_output_contains "$display_path"
  snapshot_icon >"$TEST_DIR/after.txt"
  cmp "$TEST_DIR/before.txt" "$TEST_DIR/after.txt" || {
    test_fail "Removing an icon changed locked application icon data"
    exit 1
  }

  chflags nouchg "$locked_path"
  "$HELPER" test "$APP"
  "$HELPER" remove "$APP"
done
test_pass "Locked app directories and icon payloads fail without changing icon data"

test_pass "$TEST_NAME passed"
