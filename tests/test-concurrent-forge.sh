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

TMPDIR="$TEMP_ROOT" "$ICONFORGE" forge "$SOURCE_ONE/shared.jpg" -o "$OUTPUT_ONE" >"$LOG_ONE" 2>&1 &
pid_one=$!
TMPDIR="$TEMP_ROOT" "$ICONFORGE" forge "$SOURCE_TWO/shared.jpg" -o "$OUTPUT_TWO" >"$LOG_TWO" 2>&1 &
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

SHARED_OUTPUT="$TEST_DIR/shared-output"
SHARED_LOG_ONE="$TEST_DIR/shared-one.log"
SHARED_LOG_TWO="$TEST_DIR/shared-two.log"
mkdir -p "$SHARED_OUTPUT"
cp "$TEST_IMAGE1" "$SOURCE_ONE/shared.png"
set +e
TMPDIR="$TEMP_ROOT" "$ICONFORGE" forge "$SOURCE_ONE/shared.png" -o "$SHARED_OUTPUT" >"$SHARED_LOG_ONE" 2>&1 &
shared_pid_one=$!
TMPDIR="$TEMP_ROOT" "$ICONFORGE" forge "$SOURCE_TWO/shared.jpg" -o "$SHARED_OUTPUT" >"$SHARED_LOG_TWO" 2>&1 &
shared_pid_two=$!
wait "$shared_pid_one"
shared_status_one=$?
wait "$shared_pid_two"
shared_status_two=$?
set -e

if [[ "$shared_status_one" -eq 0 && "$shared_status_two" -eq 0 ]]; then
  test_fail "Concurrent same-target forge silently overwrote an output"
  exit 1
fi
if [[ "$shared_status_one" -ne 0 && "$shared_status_two" -ne 0 ]]; then
  cat "$SHARED_LOG_ONE"
  cat "$SHARED_LOG_TWO"
  test_fail "Concurrent same-target forge kept neither complete run"
  exit 1
fi
assert_file_exists "$SHARED_OUTPUT/shared.icns"
"$PWD/iconforge-native-icon/iconforge-native-icon" validate "$SHARED_OUTPUT/shared.icns"

if find "$TEMP_ROOT" -mindepth 1 -maxdepth 1 ! -name 'iconforge-report.*' -print -quit | grep -q .; then
  test_fail "Forge left temporary conversion files behind"
  exit 1
fi

report_count=0
while IFS= read -r -d '' report_directory; do
  report_count=$((report_count + 1))
  report="$report_directory/report.log"
  [[ -f "$report" && ! -L "$report" ]] || {
    test_fail "Concurrent forge retained an invalid diagnostic report"
    exit 1
  }
  grep -Fx 'Exit status: 1' "$report" >/dev/null || {
    test_fail "The failed concurrent run did not complete its diagnostic report"
    exit 1
  }
  if find "$report_directory" -mindepth 1 ! -name report.log -print -quit | grep -q .; then
    test_fail "Concurrent forge retained capture pipes or temporary report files"
    exit 1
  fi
done < <(find "$TEMP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'iconforge-report.*' -print0)
[[ "$report_count" -eq 1 ]] || {
  test_fail "Expected exactly one diagnostic report for the failed concurrent run"
  exit 1
}

test_pass "$TEST_NAME passed"
