#!/usr/bin/env bash
set -euo pipefail
TEST_NAME="forge and hearth CLI integration"
# shellcheck source=tests/test-common.sh
source tests/test-common.sh
BIN="$PWD/iconforge.sh"
BASE="$PWD/$TEST_DIR"
FORGE="$BASE/the workshop"
HEARTH="$BASE/finished icons"
APPS="$BASE/apps"
EMPTY="$BASE/empty"
OUTPUT="$BASE/output.log"
export XDG_CONFIG_HOME="$BASE/config"
mkdir -p "$FORGE" "$HEARTH" "$APPS" "$EMPTY"
export ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$APPS"
export ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY"
export ICONFORGE_TEST_APPLICATIONS_DIR="$EMPTY"
export ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$EMPTY"
export ICONFORGE_TEST_CORE_SERVICES_DIR="$EMPTY"

assert_contains() { grep -F -- "$1" "$OUTPUT" >/dev/null || { test_fail "Missing output: $1"; cat "$OUTPUT"; exit 1; }; }
assert_status() {
  local expected="$1" actual=0; shift
  "$BIN" "$@" >"$OUTPUT" 2>&1 || actual=$?
  [[ "$actual" -eq "$expected" ]] || { test_fail "Expected $expected, got $actual: $*"; cat "$OUTPUT"; exit 1; }
}
create_app() {
  mkdir -p "$1/Contents/Resources"
  /usr/bin/plutil -create xml1 "$1/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string org.iconforge.fixture.Firefox "$1/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleName -string Firefox "$1/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleDisplayName -string Firefox "$1/Contents/Info.plist"
}
create_app "$APPS/Firefox.app"
"$BIN" config set the-forge "$FORGE" >/dev/null
"$BIN" config set the-hearth "$HEARTH" >/dev/null
[[ "$("$BIN" config get the-forge)" == "$FORGE" ]]
[[ "$("$BIN" config get the-hearth)" == "$HEARTH" ]]
"$BIN" forge "$TEST_IMAGE1" Firefox >/dev/null
assert_file_exists "$FORGE/Firefox.icns"
[[ ! -e "$HEARTH/Firefox.icns" ]]
cp "$FORGE/Firefox.icns" "$HEARTH/Firefox.icns"
assert_status 0 apply Firefox --dry-run
assert_contains "$HEARTH/Firefox.icns"
assert_contains "$APPS/Firefox.app"
assert_status 0 apply Firefox nuke --dry-run
assert_contains 'Planned Nuke'
assert_status 0 apply --all --dry-run --nuke
assert_contains 'Would apply: 1'
# Dry runs must not leave a Finder custom icon.
if "$PWD/iconforge-native-icon/iconforge-native-icon" present "$APPS/Firefox.app"; then
  test_fail 'Dry-run mutated the app'; exit 1
fi
# Real writes are limited to a disposable fixture, with no real cache clearing.
assert_status 0 apply Firefox
"$PWD/iconforge-native-icon/iconforge-native-icon" test "$APPS/Firefox.app"
assert_status 0 restore Firefox

mkdir -p "$HEARTH/alternate"
cp "$HEARTH/Firefox.icns" "$HEARTH/alternate/firefox.icns"
assert_status 1 apply Firefox --dry-run
assert_contains 'Multiple icons match'
rm "$HEARTH/alternate/firefox.icns"

# Setting/unsetting one key does not destroy the other or future preferences.
PLIST="$XDG_CONFIG_HOME/iconforge/config.plist"
/usr/bin/plutil -insert future_setting -string keep-me "$PLIST"
"$BIN" config unset the-forge >/dev/null
[[ "$("$BIN" config get the-hearth)" == "$HEARTH" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :future_setting' "$PLIST")" == keep-me ]]
"$BIN" config set default-directory "$FORGE" >/dev/null
assert_status 0 config show
assert_contains 'source: default-directory (legacy)'
assert_contains 'source: the-hearth'

# Explicit selection bypasses even malformed unrelated configuration.
printf 'invalid plist\n' > "$PLIST"
assert_status 0 apply Firefox --icon="$HEARTH/Firefox.icns" --dry-run
assert_status 0 apply Firefox --from="$HEARTH" --dry-run
assert_status 0 apply --all --from="$HEARTH" --dry-run
assert_status 1 config set the-hearth "$HEARTH"
[[ "$(cat "$PLIST")" == 'invalid plist' ]]
rm "$PLIST"
"$BIN" config set the-hearth "$HEARTH" >/dev/null

# A second installation must not become a first-match-wins mutation.
mkdir -p "$BASE/other-apps"
create_app "$BASE/other-apps/Firefox.app"
assert_status 1 apply Firefox --app-root "$BASE/other-apps" --dry-run
assert_status 0 apply "$BASE/other-apps/Firefox.app" --dry-run

assert_status 0 doctor "$APPS/Firefox.app"
assert_status 0 capabilities
assert_status 0 completion bash
assert_contains '_iconforge_complete'
assert_status 2 apply -- Firefox nuke
assert_status 2 apply Firefox --icon one.icns --from "$HEARTH"
assert_status 2 apply --all --strategy internal-icns

test_pass "$TEST_NAME passed"
