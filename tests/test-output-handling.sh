#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="invalid output directory"
source tests/test-common.sh

echo "🧪 Test: $TEST_NAME"

BAD_DIR="/System/Library"

set +e
"$ICONFORGE" "$TEST_IMAGE1" -o "$BAD_DIR" -k >/dev/null 2>&1
EXIT_CODE=$?
set -e

echo "🚨 iconforge exited with: $EXIT_CODE"

if [[ "$EXIT_CODE" -eq 0 ]]; then
  echo "❌ iconforge unexpectedly succeeded writing to a protected path"
  exit 1
else
  echo "✅ Correctly failed on unwritable output path"
  echo "🎉 $TEST_NAME passed"
fi

exit 0
