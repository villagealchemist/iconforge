#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="configured forge and bulk directory defaults"
source tests/test-common.sh
unset XDG_CONFIG_HOME || true

BIN="$PWD/iconforge.sh"
ABS_TEST_DIR="$PWD/$TEST_DIR"
FAKE_HOME="$ABS_TEST_DIR/home"
DEFAULT_OUTPUT="$ABS_TEST_DIR/default output"
EXPLICIT_OUTPUT="$ABS_TEST_DIR/explicit output"
MISSING_OUTPUT="$ABS_TEST_DIR/missing/created-by-forge"
APPS="$ABS_TEST_DIR/apps"
EMPTY="$ABS_TEST_DIR/empty"
BULK_DEFAULT="$ABS_TEST_DIR/bulk default"
BULK_EXPLICIT="$ABS_TEST_DIR/bulk explicit"
CHROME_ALIAS_LIBRARY="$ABS_TEST_DIR/chrome aliases"
OUTPUT="$ABS_TEST_DIR/output.log"

mkdir -p "$FAKE_HOME" "$DEFAULT_OUTPUT" "$EXPLICIT_OUTPUT" "$APPS" "$EMPTY" "$BULK_DEFAULT" "$BULK_EXPLICIT" "$CHROME_ALIAS_LIBRARY"

HOME="$FAKE_HOME" "$BIN" config set default-directory "$DEFAULT_OUTPUT" >/dev/null
HOME="$FAKE_HOME" "$BIN" forge "$TEST_IMAGE1"
assert_file_exists "$DEFAULT_OUTPUT/i-just-wanna-be-an-icon.icns"

HOME="$FAKE_HOME" "$BIN" "$TEST_IMAGE2"
assert_file_exists "$DEFAULT_OUTPUT/pls-oh-pls-convert-me-to-icns.icns"

HOME="$FAKE_HOME" "$BIN" forge "$TEST_IMAGE1" --output "$EXPLICIT_OUTPUT"
assert_file_exists "$EXPLICIT_OUTPUT/i-just-wanna-be-an-icon.icns"
[[ "$(HOME="$FAKE_HOME" "$BIN" config get default-directory)" == "$DEFAULT_OUTPUT" ]] || {
  test_fail "An explicit forge output changed the saved default"
  exit 1
}

create_app() {
  local app="$1"
  local bundle_id="$2"
  local display_name="$3"
  local bundle_name="$4"

  mkdir -p "$app/Contents"
  /usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleDisplayName -string "$display_name" "$app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleName -string "$bundle_name" "$app/Contents/Info.plist"
}

create_app "$APPS/Google Chrome.app" com.google.Chrome "Google Chrome" Chrome
create_app "$APPS/Google Chrome Dev.app" com.google.Chrome.dev "Google Chrome Dev" "Chrome Dev"
create_app "$APPS/Visual Studio Code.app" com.microsoft.VSCode "Visual Studio Code" Code
make_test_icns "$TEST_IMAGE1" "$BULK_DEFAULT/google-chrome.icns"
cp "$BULK_DEFAULT/google-chrome.icns" "$BULK_DEFAULT/google-chrome-dev.icns"
cp "$BULK_DEFAULT/google-chrome.icns" "$BULK_EXPLICIT/visual-studio-code.icns"

HOME="$FAKE_HOME" "$BIN" config set default-directory "$BULK_DEFAULT" >/dev/null
set +e
HOME="$FAKE_HOME" "$BIN" apply >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 2 ]] || { test_fail "A configured default made bare apply scan implicitly"; exit 1; }
grep -F "iconforge apply -a [directory]" "$OUTPUT" >/dev/null || {
  test_fail "Bare apply did not remain an explicit usage error"
  exit 1
}
HOME="$FAKE_HOME" \
ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$APPS" \
ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY" \
ICONFORGE_TEST_APPLICATIONS_DIR="$EMPTY" \
ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$EMPTY" \
  "$BIN" apply --all --dry-run --verbose >"$OUTPUT" 2>&1
grep -F "google-chrome: would-apply ($APPS/Google Chrome.app)" "$OUTPUT" >/dev/null || {
  test_fail "Bare bulk apply did not use the configured Chrome Stable icon"
  exit 1
}
grep -F "google-chrome-dev: would-apply ($APPS/Google Chrome Dev.app)" "$OUTPUT" >/dev/null || {
  test_fail "Bare bulk apply did not independently match Chrome Dev"
  exit 1
}
grep -F "Would apply: 2" "$OUTPUT" >/dev/null || { test_fail "Configured bulk summary was incorrect"; exit 1; }

HOME="$FAKE_HOME" \
ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$APPS" \
ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY" \
ICONFORGE_TEST_APPLICATIONS_DIR="$EMPTY" \
ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$EMPTY" \
  "$BIN" apply --all "$BULK_EXPLICIT" --dry-run --verbose >"$OUTPUT" 2>&1
grep -F "visual-studio-code: would-apply ($APPS/Visual Studio Code.app)" "$OUTPUT" >/dev/null || {
  test_fail "An explicit bulk directory did not override the saved default"
  exit 1
}
! grep -F "google-chrome:" "$OUTPUT" >/dev/null || {
  test_fail "Explicit bulk apply also scanned the configured default"
  exit 1
}

cp "$BULK_DEFAULT/google-chrome.icns" "$CHROME_ALIAS_LIBRARY/google-chrome.icns"
cp "$BULK_DEFAULT/google-chrome.icns" "$CHROME_ALIAS_LIBRARY/chrome.icns"
set +e
HOME="$FAKE_HOME" \
ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$APPS" \
ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY" \
ICONFORGE_TEST_APPLICATIONS_DIR="$EMPTY" \
ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$EMPTY" \
  "$BIN" apply --all "$CHROME_ALIAS_LIBRARY" --dry-run >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Chrome Stable aliases were allowed to target one app"; exit 1; }
grep -F "Two icon keys resolve to the same app: chrome and google-chrome -> $APPS/Google Chrome.app" "$OUTPUT" >/dev/null || {
  test_fail "Chrome Stable alias collision was not explained"
  exit 1
}

HOME="$FAKE_HOME" "$BIN" config set default-directory "$MISSING_OUTPUT" >/dev/null
set +e
HOME="$FAKE_HOME" \
ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$APPS" \
ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY" \
ICONFORGE_TEST_APPLICATIONS_DIR="$EMPTY" \
ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$EMPTY" \
  "$BIN" apply --all --dry-run >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Bulk apply accepted a missing configured directory"; exit 1; }
grep -F "Icon directory not found: $MISSING_OUTPUT" "$OUTPUT" >/dev/null || {
  test_fail "Missing configured bulk directory error was unclear"
  exit 1
}

HOME="$FAKE_HOME" "$BIN" forge "$TEST_IMAGE1"
assert_file_exists "$MISSING_OUTPUT/i-just-wanna-be-an-icon.icns"

test_pass "$TEST_NAME passed"
