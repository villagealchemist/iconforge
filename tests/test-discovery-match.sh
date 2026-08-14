#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="application discovery and normalized matching"
source tests/test-common.sh
source ./lib/iconforge/common.sh
source ./lib/iconforge/discovery.sh
source ./lib/iconforge/match.sh

create_app() {
  local app="$1"
  local bundle_id="$2"
  local display_name="$3"
  mkdir -p "$app/Contents"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
  plutil -insert CFBundleDisplayName -string "$display_name" "$app/Contents/Info.plist"
  plutil -insert CFBundleName -string "$display_name" "$app/Contents/Info.plist"
}

ROOT="$PWD/$TEST_DIR/apps"
EMPTY="$PWD/$TEST_DIR/empty"
mkdir -p "$ROOT/Utilities" "$ROOT/Too/Deep" "$EMPTY"
create_app "$ROOT/Visual Studio Code.app" com.example.code "Visual Studio Code"
create_app "$ROOT/Google Chrome.app" com.example.chrome "Google Chrome"
create_app "$ROOT/Google Chrome Dev.app" com.example.chrome-dev "Google Chrome Dev"
create_app "$ROOT/Utilities/Café—Studio.app" com.example.cafe "Café—Studio"
create_app "$ROOT/Uppercase.APP" com.example.uppercase "Uppercase"
create_app "$ROOT/Too/Deep/Invisible.app" com.example.invisible "Invisible"

ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$ROOT"
ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY"
ICONFORGE_TEST_APPLICATIONS_DIR="$EMPTY"
ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$EMPTY"

discover_applications
[[ "${#DISCOVERED_APP_RECORDS[@]}" -eq 5 ]] || { test_fail "Discovery did not enforce depth two or case-insensitive .app matching"; exit 1; }

match_application_name "visual_studio-code.app"
[[ "$MATCH_STATUS" == matched-exact ]] || { test_fail "Expected exact punctuation-insensitive match"; exit 1; }
[[ "$(discovered_app_bundle_id "$MATCH_RECORD")" == com.example.code ]] || { test_fail "Exact match selected wrong app"; exit 1; }

match_application_name "café studio"
[[ "$MATCH_STATUS" == matched-exact ]] || { test_fail "Expected Unicode-normalized exact match"; exit 1; }

match_application_name "café"
[[ "$MATCH_STATUS" == matched-partial ]] || { test_fail "Expected a unique partial suggestion"; exit 1; }

set +e
match_application_name "chrome"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 && "$MATCH_STATUS" == ambiguous-partial ]] || { test_fail "Ambiguous partial did not fail closed"; exit 1; }

set +e
resolve_app_path "café" >"$TEST_DIR/output.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { test_fail "Noninteractive partial resolution should not auto-select"; exit 1; }
grep -F "Retry with the exact app path:" "$TEST_DIR/output.log" >/dev/null || { test_fail "Partial failure omitted exact retry guidance"; exit 1; }

[[ "$(resolve_app_path 'Visual Studio Code.app')" == "$(realpath -- "$ROOT/Visual Studio Code.app")" ]] || {
  test_fail "A bare installed app name with .app did not resolve"
  exit 1
}

[[ "$(resolve_app_path 'Uppercase.app')" == "$(realpath -- "$ROOT/Uppercase.APP")" ]] || {
  test_fail "An installed bundle with an uppercase .APP suffix did not resolve"
  exit 1
}

DUPLICATE_ROOT="$PWD/$TEST_DIR/duplicate-apps"
create_app "$DUPLICATE_ROOT/Visual Studio Code.app" com.example.code-copy "Visual Studio Code"
ICONFORGE_TEST_USER_APPLICATIONS_DIR="$DUPLICATE_ROOT"
set +e
(
  cd "$ROOT"
  resolve_app_path "Visual Studio Code.app"
) >"$TEST_DIR/duplicate-output.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { test_fail "A bare existing app bypassed duplicate name resolution"; exit 1; }
grep -F "Multiple installed applications share this exact match" "$TEST_DIR/duplicate-output.log" >/dev/null || {
  test_fail "A bare existing app did not report duplicate exact matches"
  exit 1
}
[[ "$(cd "$ROOT" && resolve_app_path './Visual Studio Code.app')" == "$(realpath -- "$ROOT/Visual Studio Code.app")" ]] || {
  test_fail "A dot-qualified app path did not bypass name lookup"
  exit 1
}
ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY"

set +e
resolve_app_path "Missing.app" >"$TEST_DIR/output.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { test_fail "A missing installed app name should fail"; exit 1; }
grep -F "Could not resolve app bundle" "$TEST_DIR/output.log" >/dev/null || {
  test_fail "Missing installed app name did not report resolver failure"
  exit 1
}

set +e
resolve_app_path "./Missing.app" >"$TEST_DIR/output.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { test_fail "A missing explicit app path should fail"; exit 1; }
grep -F "App bundle not found or invalid" "$TEST_DIR/output.log" >/dev/null || {
  test_fail "Missing explicit app path was not treated as a path"
  exit 1
}

test_pass "$TEST_NAME passed"
