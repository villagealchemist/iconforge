#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="batch input support"
source tests/test_common.sh

echo "🧪 Test: $TEST_NAME"

mkdir -p "$TEST_DIR"
"$ICONFORGE" "$TEST_IMAGE1" "$TEST_IMAGE2" -o "$TEST_DIR" -k

safe1=$(basename "$TEST_IMAGE1" | sed 's/\.[^.]*$//' | tr -cd '[:alnum:]_-')
safe2=$(basename "$TEST_IMAGE2" | sed 's/\.[^.]*$//' | tr -cd '[:alnum:]_-')

assert_file_exists "$TEST_DIR/$safe1/$safe1.icns"
assert_file_exists "$TEST_DIR/$safe2/$safe2.icns"

echo "🎉 $TEST_NAME passed"
