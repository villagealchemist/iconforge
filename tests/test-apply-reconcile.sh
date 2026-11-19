#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="bulk apply preflight and reconciliation"
source tests/test-common.sh

BIN="$PWD/iconforge.sh"
REAL_HELPER="$PWD/iconforge-native-icon/iconforge-native-icon"
ABS_TEST_DIR="$PWD/$TEST_DIR"
APPS="$ABS_TEST_DIR/apps"
EMPTY="$ABS_TEST_DIR/empty"
ICONS="$ABS_TEST_DIR/icons"
FAKE_BIN="$ABS_TEST_DIR/fakebin"
LOGS="$ABS_TEST_DIR/logs"
HOME_DIR="$ABS_TEST_DIR/home"
OUTPUT="$ABS_TEST_DIR/output.log"
mkdir -p "$APPS" "$EMPTY" "$ICONS/nested" "$ICONS/.hidden" "$ICONS/_private" "$FAKE_BIN" "$LOGS" "$HOME_DIR/Library/Caches/darwin"

make_test_icns "$TEST_IMAGE1" "$ABS_TEST_DIR/one.icns"
make_test_icns "$TEST_IMAGE2" "$ABS_TEST_DIR/two.icns"

create_app() {
  local file_name="$1"
  local display_name="${2:-$1}"
  local app="$APPS/$file_name.app"
  mkdir -p "$app/Contents"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "com.example.$(printf '%s' "$file_name" | tr -cd '[:alnum:]')" "$app/Contents/Info.plist"
  plutil -insert CFBundleDisplayName -string "$display_name" "$app/Contents/Info.plist"
  plutil -insert CFBundleName -string "$display_name" "$app/Contents/Info.plist"
}

create_app Alpha
create_app "Beta Tool"
create_app "Partial Wonder"
create_app "Twin One"
create_app "Twin Two"

cp "$ABS_TEST_DIR/one.icns" "$ICONS/Alpha.icns"
cp "$ABS_TEST_DIR/two.icns" "$ICONS/nested/Beta Tool.icns"
cp "$ABS_TEST_DIR/one.icns" "$ICONS/nested/Wonder.icns"
cp "$ABS_TEST_DIR/one.icns" "$ICONS/Ghost.icns"
cp "$ABS_TEST_DIR/one.icns" "$ICONS/.hidden/Hidden.icns"
cp "$ABS_TEST_DIR/one.icns" "$ICONS/_private/Private.icns"

cat >"$FAKE_BIN/native-helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$ICONFORGE_TEST_LOG_DIR/native.log"
case "$1" in
  normalize|validate|path-key|link-exclusive|rename-exact|diagnose) exec "$ICONFORGE_REAL_HELPER" "$@" ;;
  user-home) printf '%s\n' "$HOME" ;;
  set)
    if [[ "${ICONFORGE_TEST_FAIL_APP:-}" == "${2##*/}" ]]; then
      printf 'Simulated native failure for %s\n' "$2" >&2
      exit 71
    fi
    : >"$ICONFORGE_TEST_LOG_DIR/set-${2##*/}"
    ;;
  test|present) [[ -f "$ICONFORGE_TEST_LOG_DIR/set-${2##*/}" ]] ;;
  remove) /bin/rm -f "$ICONFORGE_TEST_LOG_DIR/set-${2##*/}" ;;
  *) exit 64 ;;
esac
EOF
for tool in killall qlmanage rm touch; do
  cat >"$FAKE_BIN/$tool" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ICONFORGE_TEST_LOG_DIR/TOOL.log"
if [[ TOOL == rm && "${ICONFORGE_TEST_FAIL_RM:-}" == true && "$*" == *com.apple.iconservices.store* ]]; then
  printf 'Simulated cache removal failure\n' >&2
  exit 1
fi
if [[ TOOL == killall && "$*" == Finder ]]; then
  case "${ICONFORGE_TEST_PROCESS_STATE:-}" in
    absent) printf 'No matching processes belonging to you were found\n' >&2; exit 1 ;;
    denied) printf 'killall: Operation not permitted\n' >&2; exit 1 ;;
  esac
fi
EOF
  sed -i '' "s/TOOL/$tool/g" "$FAKE_BIN/$tool"
done
cat >"$FAKE_BIN/getconf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$HOME/Library/Caches/darwin"
EOF
chmod +x "$FAKE_BIN"/*

run_bulk() {
  HOME="$HOME_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  ICONFORGE_TEST_LOG_DIR="$LOGS" \
  ICONFORGE_REAL_HELPER="$REAL_HELPER" \
  ICONFORGE_NATIVE_ICON="$FAKE_BIN/native-helper" \
  ICONFORGE_KILLALL_BIN="$FAKE_BIN/killall" \
  ICONFORGE_RM_BIN="$FAKE_BIN/rm" \
  ICONFORGE_TOUCH_BIN="$FAKE_BIN/touch" \
  ICONFORGE_GETCONF_BIN="${ICONFORGE_GETCONF_BIN:-$FAKE_BIN/getconf}" \
  ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$APPS" \
  ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY" \
  ICONFORGE_TEST_APPLICATIONS_DIR="$EMPTY" \
  ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$EMPTY" \
  "$BIN" "$@" >"$OUTPUT" 2>&1
}

assert_output() { grep -F -- "$1" "$OUTPUT" >/dev/null || { cat "$OUTPUT"; test_fail "Missing output: $1"; exit 1; }; }
count_lines() { [[ -f "$1" ]] && wc -l <"$1" | tr -d ' ' || printf '0\n'; }

run_bulk apply -a "$ICONS" -d -v
assert_output "Would apply: 2"
assert_output "Unmatched: 1"
assert_output "Declined: 1"
assert_output "Alpha: would-apply"
assert_output "Wonder: declined"
assert_output "Retry directly: iconforge apply"
[[ ! -e "$LOGS/set-Alpha.app" && ! -e "$LOGS/set-Beta Tool.app" ]] || { test_fail "Dry-run mutated an app"; exit 1; }

rm -f "$LOGS"/*.log "$LOGS"/set-*
run_bulk apply -a "$ICONS" -n -v
assert_output "Applied: 2"
assert_output "Unmatched: 1"
assert_output "Declined: 1"
[[ -e "$LOGS/set-Alpha.app" && -e "$LOGS/set-Beta Tool.app" ]] || { test_fail "Exact bulk matches were not applied"; exit 1; }
[[ "$(count_lines "$LOGS/killall.log")" -eq 3 ]] || { test_fail "Nuke did not run exactly once"; exit 1; }
[[ "$(count_lines "$LOGS/qlmanage.log")" -eq 1 ]] || { test_fail "Quick Look refresh did not run exactly once"; exit 1; }

rm -f "$LOGS"/set-*
# The Expect program reads its own environment variables; shell expansion is intentionally disabled.
# shellcheck disable=SC2016
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" \
  ICONFORGE_TEST_LOG_DIR="$LOGS" ICONFORGE_REAL_HELPER="$REAL_HELPER" \
  ICONFORGE_NATIVE_ICON="$FAKE_BIN/native-helper" ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$APPS" \
  ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY" ICONFORGE_TEST_APPLICATIONS_DIR="$EMPTY" \
  ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$EMPTY" ICONFORGE_TEST_BIN="$BIN" ICONFORGE_TEST_ICONS="$ICONS" \
  /usr/bin/expect -c '
    set timeout 30
    spawn $env(ICONFORGE_TEST_BIN) apply -a $env(ICONFORGE_TEST_ICONS) -d
    expect "Include all of these suggestions for this run?"
    send "y\r"
    expect eof
    set wait_result [wait]
    exit [lindex $wait_result 3]
  ' >"$OUTPUT" 2>&1
assert_output "Would apply: 3"
assert_output "Declined: 0"

AMBIGUOUS_ROOT="$ABS_TEST_DIR/ambiguous-icons"
mkdir -p "$AMBIGUOUS_ROOT"
cp "$ABS_TEST_DIR/one.icns" "$AMBIGUOUS_ROOT/Twin.icns"
rm -f "$LOGS"/set-*
set +e
run_bulk apply -a "$AMBIGUOUS_ROOT" -v
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "An all-ambiguous bulk run should fail without mutation"; exit 1; }
assert_output "Ambiguous: 1"
printf -v TWIN_ONE_RETRY '%q' "$APPS/Twin One.app"
printf -v TWIN_TWO_RETRY '%q' "$APPS/Twin Two.app"
assert_output "Retry directly: iconforge apply $TWIN_ONE_RETRY"
assert_output "Retry directly: iconforge apply $TWIN_TWO_RETRY"
[[ "$(grep -c '^Remedy: Retry directly:' "$OUTPUT")" -eq 2 ]] || {
  test_fail "Ambiguous bulk guidance did not print one exact retry per candidate"
  exit 1
}
[[ ! -e "$LOGS/set-Twin One.app" && ! -e "$LOGS/set-Twin Two.app" ]] || {
  test_fail "Ambiguous bulk matching mutated an application"
  exit 1
}

INVALID_ROOT="$ABS_TEST_DIR/invalid-icons"
mkdir -p "$INVALID_ROOT"
cp "$ABS_TEST_DIR/one.icns" "$INVALID_ROOT/Alpha.icns"
cp "$TEST_IMAGE1" "$INVALID_ROOT/Beta Tool.icns"
rm -f "$LOGS"/set-*
set +e
run_bulk apply -a "$INVALID_ROOT"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Malformed ICNS should fail preflight"; exit 1; }
[[ ! -e "$LOGS/set-Alpha.app" ]] || { test_fail "Malformed manifest partially applied"; exit 1; }

DUP_ROOT="$ABS_TEST_DIR/duplicate-icons"
mkdir -p "$DUP_ROOT/nested"
cp "$ABS_TEST_DIR/one.icns" "$DUP_ROOT/Alpha-Beta.icns"
cp "$ABS_TEST_DIR/two.icns" "$DUP_ROOT/nested/alpha beta.icns"
set +e
run_bulk apply -a "$DUP_ROOT"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Duplicate normalized keys should fail preflight"; exit 1; }
assert_output "Duplicate normalized icon key"

create_app "Twin File" "Twin Display"
TARGET_DUP_ROOT="$ABS_TEST_DIR/target-duplicate-icons"
mkdir -p "$TARGET_DUP_ROOT"
cp "$ABS_TEST_DIR/one.icns" "$TARGET_DUP_ROOT/Twin File.icns"
cp "$ABS_TEST_DIR/two.icns" "$TARGET_DUP_ROOT/Twin Display.icns"
set +e
run_bulk apply -a "$TARGET_DUP_ROOT"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Two keys resolving to one app should fail"; exit 1; }
assert_output "Two icon keys resolve to the same app"

ALL_ISSUES_ROOT="$ABS_TEST_DIR/all-preflight-issues"
mkdir -p "$ALL_ISSUES_ROOT/nested"
cp "$ABS_TEST_DIR/one.icns" "$ALL_ISSUES_ROOT/Alpha.icns"
cp "$TEST_IMAGE1" "$ALL_ISSUES_ROOT/Beta Tool.icns"
cp "$TEST_IMAGE1" "$ALL_ISSUES_ROOT/Ghost.icns"
cp "$ABS_TEST_DIR/one.icns" "$ALL_ISSUES_ROOT/Alpha-Beta.icns"
cp "$ABS_TEST_DIR/two.icns" "$ALL_ISSUES_ROOT/nested/alpha beta.icns"
cp "$ABS_TEST_DIR/one.icns" "$ALL_ISSUES_ROOT/Twin File.icns"
cp "$ABS_TEST_DIR/two.icns" "$ALL_ISSUES_ROOT/Twin Display.icns"
rm -f "$LOGS"/set-*
set +e
run_bulk apply -a "$ALL_ISSUES_ROOT"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Combined preflight errors should fail without writes"; exit 1; }
assert_output "Duplicate normalized icon key"
assert_output "Invalid ICNS file: $ALL_ISSUES_ROOT/Beta Tool.icns"
assert_output "Invalid ICNS file: $ALL_ISSUES_ROOT/Ghost.icns"
assert_output "Two icon keys resolve to the same app"
assert_output "no applications were modified"
[[ ! -e "$LOGS/set-Alpha.app" ]] || { test_fail "Combined preflight failure partially applied"; exit 1; }

PARTIAL_ROOT="$ABS_TEST_DIR/partial-icons"
mkdir -p "$PARTIAL_ROOT"
cp "$ABS_TEST_DIR/one.icns" "$PARTIAL_ROOT/Alpha.icns"
cp "$ABS_TEST_DIR/two.icns" "$PARTIAL_ROOT/Beta Tool.icns"
set +e
ICONFORGE_TEST_FAIL_APP=Alpha.app run_bulk apply -a "$PARTIAL_ROOT"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "A partially failed bulk operation should fail"; exit 1; }
assert_output "Finder icon application failed (helper status 71)"
assert_output "Alpha: failed"
assert_output "Applied: 1"
assert_output "Failed: 1"
assert_output "successful changes were retained"
[[ -e "$LOGS/set-Beta Tool.app" ]] || { test_fail "Bulk execution stopped before the independent second app"; exit 1; }

set +e
ICONFORGE_TEST_FAIL_APP=Alpha.app run_bulk apply "$APPS/Alpha.app" -i "$PARTIAL_ROOT/Alpha.icns"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Direct CLI failures must normalize helper status to 1"; exit 1; }
assert_output "Finder icon application failed (helper status 71)"

mkdir -p "$HOME_DIR/Library/Caches/com.apple.iconservices.store" "$HOME_DIR/Library/Caches/com.apple.iconservices"
rm -f "$LOGS/rm.log" "$LOGS/killall.log" "$LOGS/qlmanage.log"
set +e
ICONFORGE_TEST_FAIL_RM=true run_bulk apply "$APPS/Alpha.app" -i "$PARTIAL_ROOT/Alpha.icns" -n
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Cache refresh failure should return failure"; exit 1; }
assert_output "Could not remove icon cache: $HOME_DIR/Library/Caches/com.apple.iconservices.store"
assert_output "Applied Finder custom icon: $APPS/Alpha.app"
assert_output "The icon change has been retained"
[[ "$(count_lines "$LOGS/rm.log")" -ge 2 ]] || { test_fail "Cache cleanup stopped after one removal failed"; exit 1; }
[[ "$(count_lines "$LOGS/killall.log")" -eq 3 ]] || { test_fail "Independent process refresh steps were skipped"; exit 1; }
[[ "$(count_lines "$LOGS/qlmanage.log")" -eq 1 ]] || { test_fail "Quick Look refresh was skipped after cache failure"; exit 1; }

rm -f "$LOGS/killall.log" "$LOGS/qlmanage.log"
set +e
ICONFORGE_TEST_PROCESS_STATE=denied run_bulk nuke
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Process-control failure should not be silently ignored"; exit 1; }
assert_output "killall: Operation not permitted"
assert_output "Could not refresh Finder (killall status 1)"
[[ "$(count_lines "$LOGS/killall.log")" -eq 3 ]] || { test_fail "A process-control error skipped later processes"; exit 1; }
[[ "$(count_lines "$LOGS/qlmanage.log")" -eq 1 ]] || { test_fail "A process-control error skipped Quick Look"; exit 1; }

ICONFORGE_TEST_PROCESS_STATE=absent run_bulk nuke
assert_output "Icon caches refreshed"
if grep -F 'Could not refresh Finder' "$OUTPUT" >/dev/null; then
  test_fail "An absent process was reported as an error"
  exit 1
fi

cat >"$FAKE_BIN/getconf-fail" <<'EOF'
#!/usr/bin/env bash
printf 'Simulated cache-directory lookup failure\n' >&2
exit 1
EOF
chmod +x "$FAKE_BIN/getconf-fail"
rm -f "$LOGS/rm.log" "$LOGS/killall.log"
set +e
ICONFORGE_GETCONF_BIN="$FAKE_BIN/getconf-fail" run_bulk nuke
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Cache enumeration failure should not report complete success"; exit 1; }
assert_output "Simulated cache-directory lookup failure"
assert_output "Could not resolve the macOS current-user cache directory"
[[ "$(count_lines "$LOGS/rm.log")" -eq 2 ]] || { test_fail "Cache enumeration error skipped known cache paths"; exit 1; }
[[ "$(count_lines "$LOGS/killall.log")" -eq 3 ]] || { test_fail "Cache enumeration error skipped process refresh"; exit 1; }

SKIPPED_ROOT="$ABS_TEST_DIR/skipped-icons"
mkdir -p "$SKIPPED_ROOT"
cp "$ABS_TEST_DIR/one.icns" "$SKIPPED_ROOT/Alpha.icns"
cp "$ABS_TEST_DIR/one.icns" "$SKIPPED_ROOT/Twin.icns"
cp "$ABS_TEST_DIR/one.icns" "$SKIPPED_ROOT/Wonder.icns"
run_bulk apply -a "$SKIPPED_ROOT"
assert_output "Applied: 1"
assert_output "Ambiguous: 1"
assert_output "Declined: 1"
assert_output "Full diagnostic report:"
skipped_report="$(sed -n 's/^Full diagnostic report: //p' "$OUTPUT")"
[[ -f "$skipped_report" ]] || { test_fail "Skipped entries did not preserve their actionable report"; exit 1; }
grep -F 'Remedy: Retry directly:' "$skipped_report" >/dev/null || { test_fail "Skipped-entry report omitted recovery commands"; exit 1; }

set +e
run_bulk apply -a "$ICONS" -s native
STATUS=$?
set -e
[[ "$STATUS" -eq 2 ]] || { test_fail "Bulk strategy flag should be a usage error"; exit 1; }

test_pass "$TEST_NAME passed"
