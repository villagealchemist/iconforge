#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="duplicate base name rejection"
source tests/test-common.sh

test_run "$TEST_NAME"

# Simulate two files with the same base name but different extensions
mkdir -p "$TEST_DIR"
cp "$TEST_IMAGE1" "$TEST_DIR/icon.png"
cp "$TEST_IMAGE2" "$TEST_DIR/icon.jpg"

if "$ICONFORGE" "$TEST_DIR/icon.png" "$TEST_DIR/icon.jpg" -o "$TEST_DIR"; then
  test_fail "Should have failed due to duplicate base name"
  exit 1
else
  test_pass "Properly rejected duplicate base names"
fi

test_pass "$TEST_NAME passed"
