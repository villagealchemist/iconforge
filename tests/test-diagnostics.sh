#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="diagnostic reports"
source tests/test-common.sh

ROOT="$PWD"
REPORT_ROOT="$PWD/$TEST_DIR/reports"
HARNESS="$PWD/$TEST_DIR/harness.sh"
FALLBACK_REPORT=""
mkdir -p "$REPORT_ROOT"

cleanup_reports() {
  if [[ "$FALLBACK_REPORT" == /tmp/iconforge-report.*/report.log ]]; then
    rm -rf "${FALLBACK_REPORT%/report.log}"
  fi
  cleanup
}
trap 'cleanup_reports || true' EXIT

cat >"$HARNESS" <<'HARNESS'
#!/usr/bin/env bash
set -euo pipefail
ICONFORGE_ROOT="$1"
scenario="$2"
source "$ICONFORGE_ROOT/lib/iconforge/common.sh"
source "$ICONFORGE_ROOT/lib/iconforge/diagnostics.sh"
source "$ICONFORGE_ROOT/lib/iconforge/match.sh"
diagnostics_start "$scenario" 'argument with spaces'
[[ "${ICONFORGE_DIAGNOSTIC_CAPTURE:-}" == 1 ]]
case "$scenario" in
  failure*)
    printf 'stdout line %s\n' {1..256}
    printf 'stderr line %s\n' {1..256} >&2
    printf 'last stdout %s\n' "$scenario"
    printf 'last stderr %s\n' "$scenario" >&2
    exit 2
    ;;
  substitution)
    captured="$(printf 'Error: failure inside command substitution\n' >&2; exit 7)"
    ;;
  capture-failure)
    kill -KILL "$ICONFORGE_REPORT_STDOUT_PID"
    exit 0
    ;;
  signal-*)
    printf 'last stdout before signal\n'
    printf 'last stderr before signal\n' >&2
    kill -"${scenario#signal-}" "$$"
    exit 99
    ;;
  tty)
    iconforge_input_is_tty
    printf 'terminal prompt remains available\n'
    ;;
esac
HARNESS

assert_contains() {
  grep -F -- "$2" "$1" >/dev/null || {
    test_fail "Expected $1 to contain '$2'"
    cat "$1"
    exit 1
  }
}

assert_status() {
  [[ "$1" -eq "$2" ]] || { test_fail "Expected status $1, got $2"; exit 1; }
}

run_case() {
  local name="$1"
  local expected="$2"
  local status=0
  TMPDIR="$REPORT_ROOT" bash "$HARNESS" "$ROOT" "$name" >"$TEST_DIR/$name.stdout" 2>"$TEST_DIR/$name.stderr" || status=$?
  assert_status "$expected" "$status"
}

report_path() {
  sed -n 's/^Full diagnostic report: //p' "$1"
}

assert_private_report() {
  local report="$1"
  [[ -f "$report" && ! -L "$report" ]] || { test_fail "Missing diagnostic report: $report"; exit 1; }
  [[ "$(stat -f '%Lp' "$report")" == 600 ]] || { test_fail "Report is not private"; exit 1; }
  [[ "$(stat -f '%Lp' "${report%/report.log}")" == 700 ]] || { test_fail "Report directory is not private"; exit 1; }
  [[ ! -e "${report%/report.log}/stdout" && ! -e "${report%/report.log}/stderr" ]] || {
    test_fail "Capture FIFOs remain after completion"
    exit 1
  }
}

run_case failure 2
report="$(report_path "$TEST_DIR/failure.stderr")"
assert_private_report "$report"
assert_contains "$report" 'last stdout failure'
assert_contains "$report" 'last stderr failure'
assert_contains "$report" 'stdout line 256'
assert_contains "$report" 'stderr line 256'
assert_contains "$report" 'Exit status: 2'
assert_contains "$report" 'Command: iconforge failure argument\ with\ spaces'
test_pass "Failure status and final output are retained in a private report"

status=0
TMPDIR="$REPORT_ROOT" "$ICONFORGE" --no-such-option >"$TEST_DIR/cli.stdout" 2>"$TEST_DIR/cli.stderr" || status=$?
assert_status 2 "$status"
report="$(report_path "$TEST_DIR/cli.stderr")"
assert_private_report "$report"
assert_contains "$report" 'Unknown global flag: --no-such-option'
assert_contains "$report" 'Exit status: 2'

mkdir "$REPORT_ROOT/success"
TMPDIR="$REPORT_ROOT/success" "$ICONFORGE" --version >"$TEST_DIR/version.stdout" 2>"$TEST_DIR/version.stderr"
printf 'iconforge v%s\n' "$(<VERSION)" >"$TEST_DIR/version.expected"
cmp "$TEST_DIR/version.expected" "$TEST_DIR/version.stdout"
[[ ! -s "$TEST_DIR/version.stderr" && -z "$(ls -A "$REPORT_ROOT/success")" ]] || {
  test_fail "Successful version output left diagnostics or reports"
  exit 1
}
test_pass "Successful CLI output is exact and leaves no reports"

TMPDIR="$REPORT_ROOT" bash "$HARNESS" "$ROOT" failure-first >"$TEST_DIR/first.stdout" 2>"$TEST_DIR/first.stderr" &
first_pid=$!
TMPDIR="$REPORT_ROOT" bash "$HARNESS" "$ROOT" failure-second >"$TEST_DIR/second.stdout" 2>"$TEST_DIR/second.stderr" &
second_pid=$!
status=0
wait "$first_pid" || status=$?
assert_status 2 "$status"
status=0
wait "$second_pid" || status=$?
assert_status 2 "$status"
first_report="$(report_path "$TEST_DIR/first.stderr")"
second_report="$(report_path "$TEST_DIR/second.stderr")"
[[ "$first_report" != "$second_report" ]] || { test_fail "Concurrent commands shared a report"; exit 1; }
assert_private_report "$first_report"
assert_private_report "$second_report"
assert_contains "$first_report" 'last stderr failure-first'
assert_contains "$second_report" 'last stderr failure-second'
if grep -F 'failure-second' "$first_report" || grep -F 'failure-first' "$second_report"; then
  test_fail "Concurrent reports contain another invocation's output"
  exit 1
fi
test_pass "Concurrent invocations retain separate complete reports"

status=0
TMPDIR="$REPORT_ROOT/does-not-exist" bash "$HARNESS" "$ROOT" failure-fallback >"$TEST_DIR/fallback.stdout" 2>"$TEST_DIR/fallback.stderr" || status=$?
assert_status 2 "$status"
FALLBACK_REPORT="$(report_path "$TEST_DIR/fallback.stderr")"
assert_private_report "$FALLBACK_REPORT"
assert_contains "$FALLBACK_REPORT" 'last stderr failure-fallback'
test_pass "Invalid TMPDIR falls back to a private report in /tmp"

run_case substitution 7
report="$(report_path "$TEST_DIR/substitution.stderr")"
assert_contains "$report" 'failure inside command substitution'
assert_contains "$report" 'Exit status: 7'
test_pass "Command substitution errors retain their output and exit status"

run_case capture-failure 0
report="$(report_path "$TEST_DIR/capture-failure.stderr")"
assert_private_report "$report"
assert_contains "$report" 'output capture failed; this report may be incomplete'
assert_contains "$report" 'Exit status: 0'
test_pass "Capture failure is reported without changing the command status"

for signal in HUP INT TERM; do
  case "$signal" in HUP) status=129 ;; INT) status=130 ;; TERM) status=143 ;; esac
  run_case "signal-$signal" "$status"
  report="$(report_path "$TEST_DIR/signal-$signal.stderr")"
  assert_private_report "$report"
  assert_contains "$report" 'last stdout before signal'
  assert_contains "$report" 'last stderr before signal'
  assert_contains "$report" "Exit status: $status"
done
test_pass "Interruptions preserve their status and drain both output streams"

TMPDIR="$REPORT_ROOT/success" /usr/bin/script -q "$TEST_DIR/terminal.log" bash "$HARNESS" "$ROOT" tty </dev/null >"$TEST_DIR/terminal.stdout" 2>"$TEST_DIR/terminal.stderr"
assert_contains "$TEST_DIR/terminal.log" 'terminal prompt remains available'
[[ -z "$(ls -A "$REPORT_ROOT/success")" ]] || { test_fail "Successful terminal check retained a report"; exit 1; }
test_pass "Output capture preserves terminal prompt detection"

test_pass "$TEST_NAME passed"
