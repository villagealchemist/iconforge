#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="invalid input file"
source tests/test-common.sh

test_run "$TEST_NAME"

BAD="$TEST_DIR/not_an_image.txt"
mkdir -p "$TEST_DIR"
echo "definitely not an image" > "$BAD"

if "$ICONFORGE" "$BAD" -o "$TEST_DIR"; then
  test_fail "Should have failed on unsupported input"
  exit 1
else
  test_pass "Gracefully skipped unsupported file"
fi

test_pass "$TEST_NAME passed"
