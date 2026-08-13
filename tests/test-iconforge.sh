#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="basic single image with override"
source tests/test-common.sh

OVERRIDE="MyIcon"
ICNS="$TEST_DIR/$OVERRIDE.icns"
PNG="$TEST_DIR/$OVERRIDE.png"

test_run "$TEST_NAME"

mkdir -p "$TEST_DIR"
"$ICONFORGE" "$TEST_IMAGE1" "$OVERRIDE" -o "$TEST_DIR" -k

assert_file_exists "$ICNS"
assert_file_exists "$PNG"

DRY_OUTPUT="$TEST_DIR/dry"
"$ICONFORGE" forge "$TEST_IMAGE1" DryIcon -o "$DRY_OUTPUT" -q -n
[[ ! -e "$DRY_OUTPUT/DryIcon.icns" ]] || { test_fail "Forge dry-run created output"; exit 1; }

test_pass "$TEST_NAME passed"
