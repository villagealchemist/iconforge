#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="colored test status output"
source tests/test-common.sh

OUTPUT="$TEST_DIR/status.log"
ESCAPE=$'\033['

mkdir -p "$TEST_DIR"
{
  test_pass "pass message"
  test_fail "fail message"
  test_run "run message"
  test_skip "skip message"
  test_info "info message"
} >"$OUTPUT"

expected_statuses=(
  "${TEST_COLOR_GREEN}✓ [PASS]${TEST_COLOR_RESET}"
  "${TEST_COLOR_RED}✗ [FAIL]${TEST_COLOR_RESET}"
  "${TEST_COLOR_CYAN}▸ [RUN]${TEST_COLOR_RESET}"
  "${TEST_COLOR_YELLOW}○ [SKIP]${TEST_COLOR_RESET}"
  "${TEST_COLOR_BRIGHT_MAGENTA}ⓘ [INFO]${TEST_COLOR_RESET}"
)

for expected in "${expected_statuses[@]}"; do
  grep -F "$expected" "$OUTPUT" >/dev/null || {
    test_fail "Redirected output is missing an expected colored status"
    exit 1
  }
done

grep -F "$ESCAPE" "$OUTPUT" >/dev/null || {
  test_fail "Redirected output is missing ANSI color sequences"
  exit 1
}

test_pass "$TEST_NAME passed"
