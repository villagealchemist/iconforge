#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="final integration test"
source tests/test_common.sh

echo "🧪 Test: $TEST_NAME"

"$ICONFORGE" "$TEST_IMAGE1" "$TEST_IMAGE2" -o "$TEST_DIR" -k

safe1=$(basename "$TEST_IMAGE1" | sed 's/\.[^.]*$//' | tr -cd '[:alnum:]_-')
safe2=$(basename "$TEST_IMAGE2" | sed 's/\.[^.]*$//' | tr -cd '[:alnum:]_-')

assert_file_exists "$TEST_DIR/$safe1/$safe1.icns"
assert_file_exists "$TEST_DIR/$safe2/$safe2.icns"
assert_file_exists "$TEST_DIR/$safe1/$safe1.png"
assert_file_exists "$TEST_DIR/$safe2/$safe2.png"

echo "🎉 $TEST_NAME passed"
