#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="native icon helper interface"
source tests/test-common.sh

HELPER="$(pwd)/iconforge-native-icon/iconforge-native-icon"
APP="$TEST_DIR/Helper Test.app"
OUTPUT="$TEST_DIR/output.log"

assert_status() {
  local expected="$1"
  local actual="$2"
  [[ "$actual" -eq "$expected" ]] || { test_fail "Expected exit status $expected, got $actual"; exit 1; }
}

assert_output_contains() {
  local needle="$1"
  grep -F "$needle" "$OUTPUT" >/dev/null || { test_fail "Expected helper output to contain '$needle'"; exit 1; }
}

[[ -x "$HELPER" ]] || { test_fail "Native icon helper is not built: $HELPER"; exit 1; }

mkdir -p "$APP/Contents"
cp /dev/null "$APP/Contents/Info.plist"

set +e
"$HELPER" >"$OUTPUT" 2>&1
STATUS=$?
set -e
assert_status 64 "$STATUS"
assert_output_contains "usage:"

set +e
"$HELPER" test "$TEST_DIR/Missing.app" >"$OUTPUT" 2>&1
STATUS=$?
set -e
assert_status 66 "$STATUS"
assert_output_contains "app bundle not found or invalid"

set +e
"$HELPER" unknown "$APP" >"$OUTPUT" 2>&1
STATUS=$?
set -e
assert_status 64 "$STATUS"
assert_output_contains "unknown command"

set +e
"$HELPER" set "$APP" "$TEST_DIR/missing.icns" >"$OUTPUT" 2>&1
STATUS=$?
set -e
assert_status 66 "$STATUS"
assert_output_contains "icon file not found"

set +e
"$HELPER" test "$APP" >"$OUTPUT" 2>&1
STATUS=$?
set -e
assert_status 1 "$STATUS"
assert_output_contains "no usable Finder custom icon is set"

test_pass "$TEST_NAME passed"
