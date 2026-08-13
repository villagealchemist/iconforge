#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="concurrent forge temp isolation"
source tests/test-common.sh

SOURCE_ONE="$TEST_DIR/source-one"
SOURCE_TWO="$TEST_DIR/source-two"
OUTPUT_ONE="$TEST_DIR/output-one"
OUTPUT_TWO="$TEST_DIR/output-two"
TEMP_ROOT="$TEST_DIR/temp"
LOG_ONE="$TEST_DIR/one.log"
LOG_TWO="$TEST_DIR/two.log"

mkdir -p "$SOURCE_ONE" "$SOURCE_TWO" "$OUTPUT_ONE" "$OUTPUT_TWO" "$TEMP_ROOT"
cp "$TEST_IMAGE2" "$SOURCE_ONE/shared.jpg"
cp "$TEST_IMAGE2" "$SOURCE_TWO/shared.jpg"

ICONFORGE_TMP_DIR="$TEMP_ROOT" "$ICONFORGE" forge "$SOURCE_ONE/shared.jpg" -o "$OUTPUT_ONE" -q >"$LOG_ONE" 2>&1 &
pid_one=$!
ICONFORGE_TMP_DIR="$TEMP_ROOT" "$ICONFORGE" forge "$SOURCE_TWO/shared.jpg" -o "$OUTPUT_TWO" -q >"$LOG_TWO" 2>&1 &
pid_two=$!

if ! wait "$pid_one"; then
  cat "$LOG_ONE"
  exit 1
fi
if ! wait "$pid_two"; then
  cat "$LOG_TWO"
  exit 1
fi

assert_file_exists "$OUTPUT_ONE/shared.icns"
assert_file_exists "$OUTPUT_TWO/shared.icns"

if find "$TEMP_ROOT" -mindepth 1 -print -quit | grep -q .; then
  echo "❌ Forge left temporary conversion files behind"
  exit 1
fi

echo "🎉 $TEST_NAME passed"
