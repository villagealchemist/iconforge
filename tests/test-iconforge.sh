#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="root dispatch and image-first CLI"
source tests/test-common.sh

BIN="$PWD/iconforge.sh"
OUTPUT_DIR="$PWD/$TEST_DIR/output"
LOG="$PWD/$TEST_DIR/output.log"
mkdir -p "$OUTPUT_DIR"
export XDG_CONFIG_HOME="$PWD/$TEST_DIR/config-home"

"$BIN" "$TEST_IMAGE1" "My Icon" -o "$OUTPUT_DIR" -k
assert_file_exists "$OUTPUT_DIR/My Icon.icns"
assert_file_exists "$OUTPUT_DIR/My Icon.png"

"$BIN" forge "$TEST_IMAGE1" "Dry Icon" -o "$OUTPUT_DIR" -d >"$LOG" 2>&1
[[ ! -e "$OUTPUT_DIR/Dry Icon.icns" ]] || { test_fail "Forge dry-run created output"; exit 1; }

set +e
"$BIN" froge >"$LOG" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 2 ]] || { test_fail "Command typo should be a usage error"; exit 1; }
grep -F "Unknown command or unsupported input image" "$LOG" >/dev/null || { test_fail "Command typo was not diagnosed"; exit 1; }

cp "$TEST_IMAGE1" "$TEST_DIR/-leading.png"
(
  cd "$TEST_DIR"
  "$BIN" -- -leading.png
)
assert_file_exists "$TEST_DIR/-leading.icns"

set +e
"$BIN" -- "$TEST_DIR/not-an-image.txt" >"$LOG" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 2 ]] || { test_fail "Root -- accepted an unsupported input"; exit 1; }

test_pass "$TEST_NAME passed"
