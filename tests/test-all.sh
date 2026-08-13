#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Running all automated iconforge tests..."
echo

mkdir -p tmp  # ensure temp log dir exists

PASS=0
FAIL=0

for test_file in tests/test-*.sh; do
  case "$test_file" in
    *test-all.sh|*test-common.sh|*test-env.sh)
      echo "⏩ Skipping meta script: $test_file"
      continue
      ;;
  esac

  echo "▶️  $test_file"

  # Run each test with isolated stderr capture
  LOG_FILE="tmp/$(basename "$test_file").log"
  if bash "$test_file" >"$LOG_FILE" 2>&1; then
    echo "✅ Passed: $test_file"
    ((PASS+=1))
  else
    echo "❌ Failed: $test_file"
    echo "🔍 Output:"
    cat "$LOG_FILE"
    ((FAIL+=1))
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
