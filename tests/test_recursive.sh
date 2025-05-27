#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="recursive directory scan"
source tests/test_common.sh

echo "🧪 Test: $TEST_NAME"

IMG_DIR="$TEST_DIR/assets"
mkdir -p "$IMG_DIR"
cp "$TEST_IMAGE1" "$IMG_DIR/sample1.png"
cp "$TEST_IMAGE2" "$IMG_DIR/sample2.jpg"

"$ICONFORGE" -r "$IMG_DIR" -o "$TEST_DIR" -k

assert_file_exists "$TEST_DIR/sample1/sample1.icns"
assert_file_exists "$TEST_DIR/sample2/sample2.icns"

echo "🎉 $TEST_NAME passed"
