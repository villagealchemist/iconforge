#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="config parsing and precedence"
source tests/test_common.sh
source ./lib/iconforge/common.sh
source ./lib/iconforge/config.sh

assert_equals() {
  [[ "$1" == "$2" ]] || { echo "❌ Expected '$1' == '$2'"; exit 1; }
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || { echo "❌ Expected output to contain '$2'"; exit 1; }
}

CONFIG_HOME="$TEST_DIR/home"
CONFIG_PATH="$CONFIG_HOME/.config/iconforge/config.plist"
mkdir -p "$(dirname "$CONFIG_PATH")"

cat > "$CONFIG_PATH" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>icon_root</key>
  <string>~/icons/from-config</string>
  <key>exclusions</key>
  <array>
    <string>ignored-app</string>
  </array>
  <key>applications</key>
  <dict>
    <key>code</key>
    <dict>
      <key>aliases</key>
      <array>
        <string>Visual Studio Code</string>
      </array>
      <key>bundle_id</key>
      <string>com.microsoft.VSCode</string>
      <key>strategy</key>
      <string>auto</string>
    </dict>
    <key>chrome</key>
    <dict>
      <key>app_path</key>
      <string>~/Applications/Google Chrome.app</string>
      <key>strategy</key>
      <string>fileicon</string>
    </dict>
    <key>arc</key>
    <dict>
      <key>strategy</key>
      <string>native</string>
    </dict>
  </dict>
</dict>
</plist>
EOF

HOME="$CONFIG_HOME" config_load "$CONFIG_PATH"
assert_equals "$ICONFORGE_CONFIG_ICON_ROOT" "$CONFIG_HOME/icons/from-config"
assert_equals "$(config_lookup_value chrome ICONFORGE_CONFIG_APP_PATHS)" "$CONFIG_HOME/Applications/Google Chrome.app"
assert_equals "$(config_lookup_value code ICONFORGE_CONFIG_APP_BUNDLE_IDS)" "com.microsoft.VSCode"
assert_equals "$(config_lookup_value chrome ICONFORGE_CONFIG_APP_STRATEGIES)" "fileicon"
assert_equals "$(config_lookup_value arc ICONFORGE_CONFIG_APP_STRATEGIES)" "native"
assert_equals "$(config_get_aliases code)" "Visual Studio Code"
config_is_excluded ignored-app

HOME="$CONFIG_HOME" ICONFORGE_ICON_ROOT="$HOME/from-env" resolved_root="$(resolve_icon_root "")"
assert_equals "$resolved_root" "$CONFIG_HOME/from-env"

# The quoted tilde exercises Icon Forge's own path expansion.
# shellcheck disable=SC2088
HOME="$CONFIG_HOME" ICONFORGE_ICON_ROOT="$HOME/from-env" resolved_root="$(resolve_icon_root "~/from-cli")"
assert_equals "$resolved_root" "$CONFIG_HOME/from-cli"

unset ICONFORGE_ICON_ROOT
ICONFORGE_CONFIG_ICON_ROOT=""
if resolve_icon_root "" >/dev/null; then
  echo "❌ Missing icon-root configuration should fail"
  exit 1
fi

BAD_CONFIG="$TEST_DIR/bad-config.plist"
cat > "$BAD_CONFIG" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>applications</key>
  <dict>
    <key>broken</key>
    <dict>
      <key>strategy</key>
      <string>banana</string>
    </dict>
  </dict>
</dict>
</plist>
EOF

set +e
config_load "$BAD_CONFIG"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Invalid strategy should fail"; exit 1; }
assert_contains "$ICONFORGE_CONFIG_ERROR" "Invalid strategy"

echo "🎉 $TEST_NAME passed"
