#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Running all automated iconforge tests..."
echo

mkdir -p tmp  # ensure temp log dir exists

PASS=0
FAIL=0

for test_file in tests/test_*.sh; do
  case "$test_file" in
    *test_all.sh|*test_common.sh)
      echo "⏩ Skipping meta script: $test_file"
      continue
      ;;
  esac

  echo "▶️  $test_file"

  # Run each test with isolated stderr capture
  LOG_FILE="tmp/$(basename "$test_file").log"
  if bash "$test_file" >"$LOG_FILE" 2>&1; then
    echo "✅ Passed: $test_file"
    ((PASS++))
  else
    echo "❌ Failed: $test_file"
    echo "🔍 Output:"
    cat "$LOG_FILE"
    ((FAIL++))
  fi

  echo
done

echo "🔍 Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
  echo "❗ One or more tests failed"
  exit 1
else
  echo "🎉 All tests passed!"
  exit 0
fi
