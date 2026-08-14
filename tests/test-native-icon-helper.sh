#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="native icon helper interface"
source tests/test-common.sh

HELPER="$(pwd)/iconforge-native-icon/iconforge-native-icon"
APP="$TEST_DIR/Helper Test.app"
OUTPUT="$TEST_DIR/output.log"
VALID_ICON="$TEST_DIR/valid.icns"

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
mkdir -p "$TEST_DIR"

ACCOUNT_HOME="$("$HELPER" user-home)"
[[ "$ACCOUNT_HOME" == /* && "$ACCOUNT_HOME" != / && -d "$ACCOUNT_HOME" ]] || {
  test_fail "Native helper returned an unsafe current-account home"
  exit 1
}
[[ "$(HOME=/private/tmp/.. "$HELPER" user-home)" == "$ACCOUNT_HOME" ]] || {
  test_fail "HOME poisoned the native current-account lookup"
  exit 1
}
set +e
"$HELPER" user-home extra >"$OUTPUT" 2>&1
STATUS=$?
set -e
assert_status 64 "$STATUS"
assert_output_contains "usage: iconforge-native-icon user-home"

mkdir -p "$APP/Contents"
cp /dev/null "$APP/Contents/Info.plist"
make_test_icns "$TEST_IMAGE1" "$VALID_ICON"

"$HELPER" validate "$VALID_ICON"

set +e
"$HELPER" validate "$TEST_IMAGE1" >"$OUTPUT" 2>&1
STATUS=$?
set -e
assert_status 66 "$STATUS"
assert_output_contains "not a valid ICNS container"

[[ "$("$HELPER" normalize 'Café—Studio.app')" == "café studio" ]] || {
  test_fail "Foundation normalization returned an unexpected token"
  exit 1
}
composed_path="$TEST_DIR/Café-Icon.icns"
decomposed_path="$TEST_DIR/$(printf 'Cafe\314\201-Icon.icns')"
[[ "$("$HELPER" path-key "$composed_path")" == "$("$HELPER" path-key "$decomposed_path")" ]] || {
  test_fail "Path collision keys did not canonicalize equivalent Unicode"
  exit 1
}
[[ "$("$HELPER" path-key "$TEST_DIR/a-b.icns")" != "$("$HELPER" path-key "$TEST_DIR/a_b.icns")" ]] || {
  test_fail "Path collision keys collapsed distinct punctuation"
  exit 1
}

printf 'exclusive source\n' >"$TEST_DIR/exclusive-source"
"$HELPER" link-exclusive "$TEST_DIR/exclusive-source" "$TEST_DIR/exclusive-target"
[[ "$TEST_DIR/exclusive-source" -ef "$TEST_DIR/exclusive-target" ]] || {
  test_fail "Exclusive link did not create the requested target"
  exit 1
}
mkdir "$TEST_DIR/exclusive-directory"
set +e
"$HELPER" link-exclusive "$TEST_DIR/exclusive-source" "$TEST_DIR/exclusive-directory" >"$OUTPUT" 2>&1
STATUS=$?
set -e
assert_status 1 "$STATUS"
if find "$TEST_DIR/exclusive-directory" -mindepth 1 -print -quit | grep -q .; then
  test_fail "Exclusive link treated the target as a directory"
  exit 1
fi

printf 'replacement bytes\n' >"$TEST_DIR/rename-source"
printf 'old bytes\n' >"$TEST_DIR/rename-target"
"$HELPER" rename-exact "$TEST_DIR/rename-source" "$TEST_DIR/rename-target"
[[ ! -e "$TEST_DIR/rename-source" && "$(<"$TEST_DIR/rename-target")" == 'replacement bytes' ]] || {
  test_fail "Exact rename did not replace the requested file"
  exit 1
}
printf 'directory race bytes\n' >"$TEST_DIR/rename-directory-source"
mkdir "$TEST_DIR/rename-directory-target"
set +e
"$HELPER" rename-exact "$TEST_DIR/rename-directory-source" "$TEST_DIR/rename-directory-target" >"$OUTPUT" 2>&1
STATUS=$?
set -e
assert_status 1 "$STATUS"
if find "$TEST_DIR/rename-directory-target" -mindepth 1 -print -quit | grep -q .; then
  test_fail "Exact rename treated the target as a destination directory"
  exit 1
fi

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
