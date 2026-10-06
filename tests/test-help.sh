#!/usr/bin/env bash
set -euo pipefail
TEST_NAME="public CLI help and parser contract"
# shellcheck source=tests/test-common.sh
source tests/test-common.sh
BIN="$PWD/iconforge.sh"
EXPECTED_VERSION="$(tr -d '[:space:]' < VERSION)"
OUTPUT="$TEST_DIR/output.log"
mkdir -p "$TEST_DIR"
export XDG_CONFIG_HOME="$PWD/$TEST_DIR/config-home"
assert_contains() { grep -F -- "$1" "$OUTPUT" >/dev/null || { test_fail "Expected help to contain: $1"; exit 1; }; }
assert_not_contains() { ! grep -F -- "$1" "$OUTPUT" >/dev/null || { test_fail "Help unexpectedly contains: $1"; exit 1; }; }
assert_status() {
  local expected="$1" actual=0; shift
  "$BIN" "$@" >"$OUTPUT" 2>&1 || actual=$?
  [[ "$actual" -eq "$expected" ]] || { test_fail "Expected status $expected from '$*', got $actual"; cat "$OUTPUT"; exit 1; }
}
"$BIN" > "$OUTPUT"
for text in forge config inspect apply restore refresh nuke doctor capabilities completion '-h, --help' '-v, --version'; do assert_contains "$text"; done
assert_not_contains '-V, --version'
"$BIN" help -- apply > "$OUTPUT"
for text in '-i, --icon' '-a, --all' '-s, --strategy' '-n, --nuke' '-d, --dry-run' '-v, --verbose' '--from' 'the-hearth'; do assert_contains "$text"; done
for removed in --icon-root --refresh-caches --force-asset --no-resign; do assert_not_contains "$removed"; done
"$BIN" restore --help > "$OUTPUT"
assert_contains '-n, --nuke'
assert_contains '-d, --dry-run'
"$BIN" config --help > "$OUTPUT"
for text in 'config set the-forge' 'config set the-hearth' 'config get' 'config unset' 'default-directory'; do assert_contains "$text"; done
"$BIN" nuke -h > "$OUTPUT"
assert_contains 'iconforge nuke'
assert_contains 'refuses to run as root'
[[ "$("$BIN" -v)" == "iconforge v$EXPECTED_VERSION" ]]
[[ "$("$BIN" --version)" == "iconforge v$EXPECTED_VERSION" ]]
assert_status 0 refresh --help
assert_status 0 help doctor
assert_status 0 capabilities
assert_status 0 completion bash
assert_status 2 completion unknown
assert_status 2 -V
assert_status 2 help unknown
assert_status 2 help apply -h
assert_status 2 config
assert_status 2 config set default-directory
assert_status 2 config get unknown
assert_status 2 config set default-directory one two
assert_status 2 apply --icon
assert_status 2 apply --all
assert_status 2 apply Example -i one.icns --icon two.icns
assert_status 2 apply Example -i one.icns -s native --strategy internal-icns
assert_status 2 restore
assert_status 2 inspect one two
assert_status 2 tests -r
assert_status 2 help -- ''
assert_status 2 inspect -- ''
assert_status 2 apply -i one.icns -- ''
assert_status 2 apply -a -- ''
assert_status 2 restore -- ''
assert_status 2 nuke -d -- ''
assert_status 2 forge "$TEST_IMAGE1" -o '' -d
assert_status 2 forge "$TEST_IMAGE1" .ICNS -d
assert_status 2 apply -- Firefox nuke
assert_status 2 apply Firefox --from=
test_pass "$TEST_NAME passed"
