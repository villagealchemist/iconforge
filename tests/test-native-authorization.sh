#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="native authorization guidance"
source tests/test-common.sh

if [[ "$EUID" -eq 0 ]]; then
  test_skip "Nonwritable app checks require an unprivileged account"
  exit 0
fi

BIN="$PWD/iconforge.sh"
REAL_HELPER="$PWD/iconforge-native-icon/iconforge-native-icon"
ABS_TEST_DIR="$PWD/$TEST_DIR"
FIXTURES="$ABS_TEST_DIR/space apostrophe' dollar\$ semicolon;"
APPS="$FIXTURES/apps"
ICONS="$FIXTURES/icons"
FAKE_BIN="$FIXTURES/bin"
LOGS="$ABS_TEST_DIR/logs"
OUTPUT="$LOGS/output"
APP="$APPS/Protected Tool.app"
ICON="$ICONS/Protected Tool.icns"
HELPER="$FAKE_BIN/native-helper"
mkdir -p "$APP/Contents/Resources" "$ICONS" "$FAKE_BIN" "$LOGS" "$ABS_TEST_DIR/empty"
plutil -create xml1 "$APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.example.protected "$APP/Contents/Info.plist"
plutil -insert CFBundleName -string 'Protected Tool' "$APP/Contents/Info.plist"
printf 'existing custom icon\n' >"$APP/"$'Icon\r'
make_test_icns "$TEST_IMAGE1" "$ICON"

cat >"$HELPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  set|remove) printf '%s\0' "$@" >>"$ICONFORGE_TEST_LOG_DIR/mutation"; exit 1 ;;
  present|test) [[ -f "$2/"$'Icon\r' ]] ;;
  *) exec "$ICONFORGE_REAL_HELPER" "$@" ;;
esac
EOF
cat >"$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >"$ICONFORGE_TEST_LOG_DIR/sudo-args"
EOF
chmod +x "$HELPER" "$FAKE_BIN/sudo"
chmod a-w "$APP"
[[ ! -w "$APP" ]] || { test_fail "Fixture app is still writable"; exit 1; }

snapshot_app() {
  stat -f '%p %m' "$APP"
  shasum -a 256 "$APP/Contents/Info.plist" "$APP/"$'Icon\r'
  find "$APP" -print | sort
}
snapshot_app >"$LOGS/before"

run_cli() {
  PATH="$FAKE_BIN:$PATH" XDG_CONFIG_HOME="$ABS_TEST_DIR/config" \
    ICONFORGE_NATIVE_ICON="$HELPER" ICONFORGE_REAL_HELPER="$REAL_HELPER" \
    ICONFORGE_TEST_LOG_DIR="$LOGS" ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$APPS" \
    ICONFORGE_TEST_USER_APPLICATIONS_DIR="$ABS_TEST_DIR/empty" \
    ICONFORGE_TEST_APPLICATIONS_DIR="$ABS_TEST_DIR/empty" \
    ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$ABS_TEST_DIR/empty" \
    "$BIN" "$@" >"$OUTPUT" 2>&1
}

assert_output() {
  grep -F -- "$1" "$OUTPUT" >/dev/null || {
    cat "$OUTPUT"; test_fail "Missing output: $1"; exit 1;
  }
}

assert_unchanged() {
  [[ ! -e "$LOGS/mutation" && ! -e "$LOGS/sudo-args" ]] || {
    test_fail "CLI invoked a mutating helper operation or sudo"; exit 1;
  }
  snapshot_app >"$LOGS/after"
  cmp -s "$LOGS/before" "$LOGS/after" || { test_fail "Protected app changed"; exit 1; }
}

assert_retry() {
  local retry_command
  local shell_bin
  retry_command="$(sed -n 's/^  \(sudo -- .*\)$/\1/p' "$OUTPUT")"
  [[ -n "$retry_command" && "$retry_command" != *$'\n'* ]] || {
    test_fail "Expected exactly one explicit helper authorization command"; exit 1;
  }
  printf '%s\0' -- "$HELPER" "$@" >"$LOGS/expected-args"
  for shell_bin in /bin/bash /bin/zsh; do
    PATH="$FAKE_BIN:$PATH" ICONFORGE_TEST_LOG_DIR="$LOGS" \
      "$shell_bin" -fc "$retry_command"
    cmp -s "$LOGS/expected-args" "$LOGS/sudo-args" || {
      test_fail "Authorization command changed arguments in $shell_bin"; exit 1;
    }
    rm "$LOGS/sudo-args"
  done
  assert_unchanged
}

if run_cli apply "$APP" -i "$ICON"; then
  test_fail "Protected native apply should fail without mutation"; exit 1
fi
assert_output "IconForge did not modify the application."
assert_output "Enter your Mac administrator password"
assert_output "After it succeeds, refresh icons if needed with: iconforge nuke"
assert_unchanged
assert_retry set "$APP" "$ICON"

if run_cli restore "$APP"; then
  test_fail "Protected native restore should fail without mutation"; exit 1
fi
assert_output "IconForge did not modify the application."
assert_unchanged
assert_retry remove "$APP"

run_cli apply "$APP" -i "$ICON" --dry-run
assert_output "The real native icon write would need authorization"
assert_output "[dry-run]"
assert_unchanged
run_cli restore "$APP" --dry-run
assert_output "The real native icon removal would need authorization"
assert_output "Planned removal of Finder custom icon"
assert_unchanged

if run_cli apply --all "$ICONS"; then
  test_fail "An all-protected bulk apply should fail without mutation"; exit 1
fi
assert_output "Applied: 0"
assert_output "Needs authorization: 1"
assert_unchanged
assert_retry set "$APP" "$ICON"

if run_cli apply --all "$ICONS" --dry-run; then
  test_fail "A protected bulk dry-run should retain its failure status"; exit 1
fi
assert_output "Would apply: 0"
assert_output "Needs authorization: 1"
assert_unchanged

test_pass "$TEST_NAME passed"
