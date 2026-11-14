#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="native icon failure report"
source tests/test-common.sh

HELPER="$PWD/iconforge-native-icon/iconforge-native-icon"
OUTPUT="$TEST_DIR/output.log"
REPORT=""
MISSING_APP="$PWD/$TEST_DIR/Missing App.app"
MISSING_ICON="$PWD/$TEST_DIR/missing.icns"

cleanup_report() {
  if [[ "$REPORT" == /tmp/iconforge-native-report.* ]]; then
    rm -f -- "$REPORT"
  fi
  cleanup
}
trap 'cleanup_report || true' EXIT

assert_contains() {
  grep -F -- "$2" "$1" >/dev/null || {
    test_fail "Expected $1 to contain '$2'"
    cat "$1"
    exit 1
  }
}

[[ -x "$HELPER" ]] || { test_fail "Native icon helper is not built: $HELPER"; exit 1; }
mkdir -p "$TEST_DIR"
status=0
env -u ICONFORGE_DIAGNOSTIC_CAPTURE "$HELPER" set "$MISSING_APP" "$MISSING_ICON" >"$OUTPUT" 2>&1 || status=$?
REPORT="$(sed -n 's/^iconforge-native-icon: Full diagnostic report: //p' "$OUTPUT")"
[[ "$status" -eq 66 ]] || { test_fail "Standalone helper changed input-error status $status"; exit 1; }
[[ "$REPORT" == /tmp/iconforge-native-report.* && -f "$REPORT" && ! -L "$REPORT" ]] || {
  test_fail "Standalone helper did not produce a report"
  cat "$OUTPUT"
  exit 1
}
[[ "$(stat -f '%Lp' "$REPORT")" == 600 && "$(stat -f '%u' "$REPORT")" == "$(id -u)" ]] || {
  test_fail "Standalone report is not private to the current user"
  exit 1
}
assert_contains "$REPORT" 'IconForge native helper diagnostic report'
assert_contains "$REPORT" "Argument 2: $MISSING_APP"
assert_contains "$REPORT" "Argument 3: $MISSING_ICON"
assert_contains "$REPORT" "app bundle not found or invalid: $MISSING_APP"
assert_contains "$REPORT" "icon file not found: $MISSING_ICON"
assert_contains "$REPORT" 'Exit status: 66'
while IFS= read -r line; do
  case "$line" in
    'iconforge-native-icon: Full diagnostic report: '*) continue ;;
  esac
  message="${line#iconforge-native-icon: }"
  grep -Fx -- "$message" "$REPORT" >/dev/null || {
    test_fail "Standalone report omitted a diagnostic printed on stderr"
    exit 1
  }
done <"$OUTPUT"
test_pass "Standalone helper report retains all diagnostics, arguments, and exit status privately"

status=0
ICONFORGE_DIAGNOSTIC_CAPTURE=1 "$HELPER" set "$MISSING_APP" "$MISSING_ICON" >"$OUTPUT" 2>&1 || status=$?
[[ "$status" -eq 66 ]] || { test_fail "Captured helper changed input-error status $status"; exit 1; }
assert_contains "$OUTPUT" "app bundle not found or invalid: $MISSING_APP"
assert_contains "$OUTPUT" "icon file not found: $MISSING_ICON"
if grep -F 'diagnostic report:' "$OUTPUT"; then
  test_fail "Captured helper emitted a duplicate standalone report path"
  exit 1
fi
test_pass "CLI capture suppresses the standalone report without suppressing errors"

rm -f -- "$REPORT"
[[ ! -e "$REPORT" ]] || { test_fail "Standalone test report was not removed"; exit 1; }
REPORT=""
test_pass "$TEST_NAME passed"
