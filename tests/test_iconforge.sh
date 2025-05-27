#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="basic single image with override"
source tests/test_common.sh

OVERRIDE="MyIcon"
ICNS="$TEST_DIR/$OVERRIDE/$OVERRIDE.icns"
PNG="$TEST_DIR/$OVERRIDE/$OVERRIDE.png"

echo "🧪 Test: $TEST_NAME"

mkdir -p "$TEST_DIR"
"$ICONFORGE" "$TEST_IMAGE1" "$OVERRIDE" -o "$TEST_DIR" -k

assert_file_exists "$ICNS"
assert_file_exists "$PNG"

echo "🎉 $TEST_NAME passed"
