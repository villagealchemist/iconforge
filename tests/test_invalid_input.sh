#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="invalid input file"
source tests/test_common.sh

echo "🧪 Test: $TEST_NAME"

BAD="$TEST_DIR/not_an_image.txt"
mkdir -p "$TEST_DIR"
echo "definitely not an image" > "$BAD"

if "$ICONFORGE" "$BAD" -o "$TEST_DIR"; then
  echo "❌ Should have failed on unsupported input"
  exit 1
else
  echo "✅ Gracefully skipped unsupported file"
fi

echo "🎉 $TEST_NAME passed"
