#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="automated test suite"
source tests/test-common.sh

test_run "Running all automated Icon Forge tests"
echo

mkdir -p tmp  # ensure temp log dir exists

PASS=0
FAIL=0

for test_file in tests/test-*.sh; do
  case "$test_file" in
    *test-all.sh|*test-common.sh|*test-env.sh)
      test_skip "Meta script: $test_file"
      continue
      ;;
  esac

  test_run "$test_file"

  # Run each test with isolated stderr capture
  LOG_FILE="tmp/$(basename "$test_file").log"
  if bash "$test_file" >"$LOG_FILE" 2>&1; then
    test_pass "$test_file"
    ((PASS+=1))
  else
    test_fail "$test_file"
    test_info "Captured output:"
    cat "$LOG_FILE"
    ((FAIL+=1))
  fi

  echo
done

test_info "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
  test_fail "One or more tests failed"
  exit 1
else
  test_pass "All tests passed"
  exit 0
fi
