#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="invalid output directory"
source tests/test-common.sh

test_run "$TEST_NAME"

BAD_DIR="/System/Library"

set +e
"$ICONFORGE" "$TEST_IMAGE1" -o "$BAD_DIR" -k >/dev/null 2>&1
EXIT_CODE=$?
set -e

test_info "iconforge exited with: $EXIT_CODE"

if [[ "$EXIT_CODE" -eq 0 ]]; then
  test_fail "iconforge unexpectedly succeeded writing to a protected path"
  exit 1
else
  test_pass "Correctly failed on unwritable output path"
  test_pass "$TEST_NAME passed"
fi

exit 0
