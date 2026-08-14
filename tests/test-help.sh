#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="final CLI help and parser contract"
source tests/test-common.sh

BIN="$PWD/iconforge.sh"
OUTPUT="$TEST_DIR/output.log"
mkdir -p "$TEST_DIR"

assert_contains() {
  grep -F -- "$1" "$OUTPUT" >/dev/null || { test_fail "Expected help to contain: $1"; exit 1; }
}

assert_not_contains() {
  ! grep -F -- "$1" "$OUTPUT" >/dev/null || { test_fail "Help unexpectedly contains: $1"; exit 1; }
}

assert_status() {
  local expected="$1"
  shift
  set +e
  "$BIN" "$@" >"$OUTPUT" 2>&1
  local actual=$?
  set -e
  [[ "$actual" -eq "$expected" ]] || { test_fail "Expected status $expected from '$*', got $actual"; exit 1; }
}

"$BIN" >"$OUTPUT"
for text in "forge" "inspect" "apply" "restore" "nuke" "-h, --help" "-v, --version"; do
  assert_contains "$text"
done
assert_not_contains "refresh"
assert_not_contains "-V, --version"

"$BIN" help -- apply >"$OUTPUT"
for text in "-i, --icon" "-a, --all" "-s, --strategy" "-n, --nuke" "-d, --dry-run" "-v, --verbose"; do
  assert_contains "$text"
done
for removed in "--icon-root" "--refresh-caches" "--force-asset" "--no-resign"; do
  assert_not_contains "$removed"
done

"$BIN" restore --help >"$OUTPUT"
assert_contains "-n, --nuke"
assert_contains "-d, --dry-run"

"$BIN" nuke -h >"$OUTPUT"
assert_contains "iconforge nuke"
assert_contains "refuses to run as root"

[[ "$("$BIN" -v)" == "iconforge v2.0.0" ]] || { test_fail "Root -v did not print v2.0.0"; exit 1; }
[[ "$("$BIN" --version)" == "iconforge v2.0.0" ]] || { test_fail "Root --version did not print v2.0.0"; exit 1; }

assert_status 2 -V
assert_status 2 refresh
assert_status 2 help unknown
assert_status 2 help apply -h
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

test_pass "$TEST_NAME passed"
