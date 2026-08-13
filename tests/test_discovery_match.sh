#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="discovery and matching"
source tests/test_common.sh
source ./lib/iconforge/common.sh
source ./lib/iconforge/config.sh
source ./lib/iconforge/discovery.sh
source ./lib/iconforge/match.sh

assert_equals() {
  [[ "$1" == "$2" ]] || { echo "❌ Expected '$1' == '$2'"; exit 1; }
}

create_fake_app() {
  local root="$1"
  local app_name="$2"
  local bundle_id="$3"
  local display_name="$4"
  local bundle_name="$5"
  local app_dir="$root/$app_name.app"

  mkdir -p "$app_dir/Contents"
  cat > "$app_dir/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleDisplayName</key>
  <string>$display_name</string>
  <key>CFBundleName</key>
  <string>$bundle_name</string>
</dict>
</plist>
EOF
}

HOME="$TEST_DIR/home"
ICONFORGE_USER_APPLICATIONS_DIR="$HOME/Applications"
ICONFORGE_SYSTEM_APPLICATIONS_DIR="$TEST_DIR/system-applications"
mkdir -p "$ICONFORGE_USER_APPLICATIONS_DIR" "$ICONFORGE_SYSTEM_APPLICATIONS_DIR"

create_fake_app "$HOME/Applications" "Visual Studio Code" "com.microsoft.VSCode" "Visual Studio Code" "Visual Studio Code"
create_fake_app "$HOME/Applications" "Google Chrome" "com.google.Chrome" "Google Chrome" "Google Chrome"
create_fake_app "$HOME/Applications" "Google Chrome Dev" "com.google.Chrome.dev" "Google Chrome Dev" "Google Chrome Dev"
mkdir -p "$ICONFORGE_SYSTEM_APPLICATIONS_DIR/Adobe Photoshop 2026"
create_fake_app "$ICONFORGE_SYSTEM_APPLICATIONS_DIR/Adobe Photoshop 2026" "Adobe Photoshop 2026" "com.adobe.Photoshop" "Adobe Photoshop 2026" "Adobe Photoshop 2026"

discover_applications
[[ "${#DISCOVERED_APP_RECORDS[@]}" -ge 3 ]] || { echo "❌ Expected discovered apps"; exit 1; }

ICONFORGE_CONFIG_APPLICATION_KEYS=("code" "chrome" "chrome-dev" "photoshop" "ghost")
ICONFORGE_CONFIG_APP_ALIASES=(
  "code"$'\t'"Visual Studio Code"
  "chrome"$'\t'"Google Chrome"
  "chrome-dev"$'\t'"Google Chrome Dev"
  "photoshop"$'\t'"Adobe Photoshop 2026"
  "ghost"$'\t'"Google"
)
ICONFORGE_CONFIG_APP_BUNDLE_IDS=(
  "code"$'\t'"com.microsoft.VSCode"
)
ICONFORGE_CONFIG_APP_PATHS=()
ICONFORGE_CONFIG_EXCLUSIONS=()

match_configured_application "code"
assert_equals "$MATCH_STATUS" "matched-bundle-id"
assert_equals "$(discovered_app_bundle_id "$MATCH_RECORD")" "com.microsoft.VSCode"

match_configured_application "chrome-dev"
assert_equals "$MATCH_STATUS" "matched-name"
assert_equals "$(discovered_app_bundle_id "$MATCH_RECORD")" "com.google.Chrome.dev"

match_configured_application "photoshop"
assert_equals "$MATCH_STATUS" "matched-name"
assert_equals "$(discovered_app_path "$MATCH_RECORD")" "$ICONFORGE_SYSTEM_APPLICATIONS_DIR/Adobe Photoshop 2026/Adobe Photoshop 2026.app"

set +e
match_configured_application "ghost"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Ambiguous match should fail closed"; exit 1; }
assert_equals "$MATCH_STATUS" "ambiguous-partial"

set +e
match_configured_application "missing-app"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Missing app should not succeed"; exit 1; }
assert_equals "$MATCH_STATUS" "missing"

echo "🎉 $TEST_NAME passed"
