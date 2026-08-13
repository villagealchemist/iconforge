#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="whole library reconciliation"
source tests/test-common.sh

ROOT_DIR="$(pwd)"
ROOT_ICONFORGE="$ROOT_DIR/iconforge.sh"
ABS_TEST_DIR="$ROOT_DIR/$TEST_DIR"
FAKE_BIN="$ABS_TEST_DIR/fakebin"
FAKE_LOG_DIR="$ABS_TEST_DIR/logs"

assert_contains() {
  [[ "$1" == *"$2"* ]] || { echo "❌ Expected output to contain '$2'"; exit 1; }
}

assert_equals() {
  [[ "$1" == "$2" ]] || { echo "❌ Expected '$1' == '$2'"; exit 1; }
}

assert_not_exists() {
  [[ ! -e "$1" ]] || { echo "❌ Unexpected path exists: $1"; exit 1; }
}

assert_file_contains() {
  local file_path="$1"
  local needle="$2"
  grep -F -- "$needle" "$file_path" >/dev/null || { echo "❌ Expected $file_path to contain '$needle'"; exit 1; }
}

assert_file_not_contains() {
  local file_path="$1"
  local needle="$2"
  [[ ! -f "$file_path" ]] || ! grep -F -- "$needle" "$file_path" >/dev/null || { echo "❌ Expected $file_path not to contain '$needle'"; exit 1; }
}

assert_line_count() {
  local file_path="$1"
  local expected_count="$2"
  local actual_count
  actual_count="$(wc -l < "$file_path" | tr -d ' ')"
  [[ "$actual_count" == "$expected_count" ]] || { echo "❌ Expected $file_path to have $expected_count lines, got $actual_count"; exit 1; }
}

setup_fake_bin() {
  mkdir -p "$FAKE_BIN" "$FAKE_LOG_DIR"

  cat > "$FAKE_BIN/touch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ICONFORGE_TEST_LOG_DIR}/touch.log"
EOF

  cat > "$FAKE_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ICONFORGE_TEST_LOG_DIR}/codesign.log"
case "$*" in
  *FailSign.app*)
    exit 1
    ;;
esac
EOF

  cat > "$FAKE_BIN/iconforge-native-icon" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ICONFORGE_TEST_LOG_DIR}/native-icon.log"
marker="${ICONFORGE_TEST_LOG_DIR}/native-${2##*/}"
case "${1:-}" in
  set)
    case "$*" in
      *FailSign.app*) exit 1 ;;
    esac
    : > "$marker"
    ;;
  test)
    [[ -f "$marker" ]]
    ;;
  remove)
    /bin/rm -f "$marker"
    ;;
  *)
    exit 1
    ;;
esac
EOF

  cat > "$FAKE_BIN/killall" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ICONFORGE_TEST_LOG_DIR}/killall.log"
EOF

  cat > "$FAKE_BIN/qlmanage" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ICONFORGE_TEST_LOG_DIR}/qlmanage.log"
EOF

  cat > "$FAKE_BIN/rm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ICONFORGE_TEST_LOG_DIR}/rm.log"
EOF

  chmod +x "$FAKE_BIN/touch" "$FAKE_BIN/codesign" "$FAKE_BIN/iconforge-native-icon" "$FAKE_BIN/killall" "$FAKE_BIN/qlmanage" "$FAKE_BIN/rm"
}

create_fake_app() {
  local app_dir="$1"
  local bundle_id="$2"
  local icon_mode="$3"
  local icon_name="${4:-AppIcon}"

  mkdir -p "$app_dir/Contents/Resources"

  case "$icon_mode" in
    loose)
      cp "$TEST_IMAGE1" "$app_dir/Contents/Resources/${icon_name}.icns"
      cat > "$app_dir/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleIconFile</key>
  <string>$icon_name</string>
</dict>
</plist>
EOF
      ;;
    asset)
      cp "$TEST_IMAGE1" "$app_dir/Contents/Resources/${icon_name}.icns"
      : > "$app_dir/Contents/Resources/Assets.car"
      cat > "$app_dir/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleIconName</key>
  <string>$icon_name</string>
</dict>
</plist>
EOF
      ;;
  esac
}

write_config() {
  local home_dir="$1"
  local icon_root="$2"

  mkdir -p "$home_dir/.config/iconforge"
  cat > "$home_dir/.config/iconforge/config.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>icon_root</key>
  <string>$icon_root</string>
  <key>exclusions</key>
  <array>
    <string>skipme</string>
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
    </dict>
    <key>figma</key>
    <dict>
      <key>aliases</key>
      <array>
        <string>Figma</string>
      </array>
    </dict>
    <key>arc</key>
    <dict>
      <key>aliases</key>
      <array>
        <string>Arc Browser</string>
      </array>
    </dict>
    <key>ghost</key>
    <dict>
      <key>aliases</key>
      <array>
        <string>Ghost App</string>
      </array>
    </dict>
    <key>ambiguous</key>
    <dict>
      <key>aliases</key>
      <array>
        <string>Google</string>
      </array>
    </dict>
    <key>failsign</key>
    <dict>
      <key>aliases</key>
      <array>
        <string>FailSign</string>
      </array>
      <key>strategy</key>
      <string>fileicon</string>
    </dict>
    <key>protected</key>
    <dict>
      <key>aliases</key>
      <array>
        <string>Protected</string>
      </array>
    </dict>
  </dict>
</dict>
</plist>
EOF
}

run_apply() {
  local output_file="$1"
  shift
  HOME="$ABS_TEST_DIR/home" \
  ICONFORGE_TEST_LOG_DIR="$FAKE_LOG_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  ICONFORGE_TOUCH_BIN=touch \
  ICONFORGE_CODESIGN_BIN=codesign \
  ICONFORGE_NATIVE_ICON="$FAKE_BIN/iconforge-native-icon" \
  ICONFORGE_KILLALL_BIN=killall \
  ICONFORGE_RM_BIN=rm \
  bash "$ROOT_ICONFORGE" apply "$@" >"$output_file" 2>&1
}

mkdir -p "$ABS_TEST_DIR"
setup_fake_bin

set +e
run_apply "$ABS_TEST_DIR/unconfigured-root.log" -a -n
UNCONFIGURED_ROOT_STATUS=$?
set -e
[[ "$UNCONFIGURED_ROOT_STATUS" -ne 0 ]] || { echo "❌ Unconfigured icon root should fail"; exit 1; }
assert_file_contains "$ABS_TEST_DIR/unconfigured-root.log" "Managed apply requires --icon-root"

set +e
run_apply "$ABS_TEST_DIR/missing-root.log" -a -r "$ABS_TEST_DIR/does-not-exist" -n
MISSING_ROOT_STATUS=$?
set -e
[[ "$MISSING_ROOT_STATUS" -ne 0 ]] || { echo "❌ Missing icon root should fail"; exit 1; }
assert_file_contains "$ABS_TEST_DIR/missing-root.log" "Icon library root not found"

ICON_ROOT="$ABS_TEST_DIR/icon-root"
HOME_DIR="$ABS_TEST_DIR/home"
OUTPUT="$ABS_TEST_DIR/output.log"
mkdir -p "$ICON_ROOT" "$HOME_DIR/Applications" "$HOME_DIR/Library/Caches"
: > "$HOME_DIR/Library/Caches/com.apple.iconservices.store"
write_config "$HOME_DIR" "$ICON_ROOT"

mkdir -p "$ICON_ROOT/code" "$ICON_ROOT/figma" "$ICON_ROOT/arc" "$ICON_ROOT/ghost" "$ICON_ROOT/ambiguous" "$ICON_ROOT/skipme" "$ICON_ROOT/pngonly" "$ICON_ROOT/multiicns" "$ICON_ROOT/failsign" "$ICON_ROOT/protected"
cp "$TEST_IMAGE2" "$ICON_ROOT/code/code.icns"
cp "$TEST_IMAGE2" "$ICON_ROOT/figma/figma.icns"
cp "$TEST_IMAGE2" "$ICON_ROOT/arc/arc.icns"
cp "$TEST_IMAGE2" "$ICON_ROOT/ghost/ghost.icns"
cp "$TEST_IMAGE2" "$ICON_ROOT/ambiguous/ambiguous.icns"
cp "$TEST_IMAGE2" "$ICON_ROOT/skipme/skipme.icns"
cp "$TEST_IMAGE2" "$ICON_ROOT/failsign/failsign.icns"
cp "$TEST_IMAGE2" "$ICON_ROOT/protected/protected.icns"
cp "$TEST_IMAGE1" "$ICON_ROOT/multiicns/one.icns"
cp "$TEST_IMAGE1" "$ICON_ROOT/multiicns/two.icns"
cp "$TEST_IMAGE1" "$ICON_ROOT/pngonly/pngonly.png"

create_fake_app "$HOME_DIR/Applications/Visual Studio Code.app" "com.microsoft.VSCode" loose "CodeIcon"
create_fake_app "$HOME_DIR/Applications/Figma.app" "com.figma.Desktop" loose "FigmaIcon"
create_fake_app "$HOME_DIR/Applications/Arc Browser.app" "company.thebrowser.Browser" asset "ArcIcon"
create_fake_app "$HOME_DIR/Applications/Google Chrome Dev.app" "com.google.Chrome.dev" loose "ChromeDevIcon"
create_fake_app "$HOME_DIR/Applications/Google Chrome.app" "com.google.Chrome" loose "ChromeIcon"
create_fake_app "$HOME_DIR/Applications/FailSign.app" "com.example.FailSign" loose "FailSignIcon"
create_fake_app "$HOME_DIR/Applications/SkipMe.app" "com.example.SkipMe" loose "SkipMeIcon"
create_fake_app "$HOME_DIR/Applications/Protected.app" "com.example.Protected" loose "ProtectedIcon"
chmod 0555 "$HOME_DIR/Applications/Protected.app" "$HOME_DIR/Applications/Protected.app/Contents" "$HOME_DIR/Applications/Protected.app/Contents/Resources"
chmod 0444 "$HOME_DIR/Applications/Protected.app/Contents/Info.plist" "$HOME_DIR/Applications/Protected.app/Contents/Resources/ProtectedIcon.icns"

ORIGINAL_CODE_SUM="$(shasum -a 256 "$HOME_DIR/Applications/Visual Studio Code.app/Contents/Resources/CodeIcon.icns" | awk '{print $1}')"
ORIGINAL_FIGMA_SUM="$(shasum -a 256 "$HOME_DIR/Applications/Figma.app/Contents/Resources/FigmaIcon.icns" | awk '{print $1}')"
set +e
run_apply "$OUTPUT" -v
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Mixed reconciliation run should return nonzero"; exit 1; }
assert_file_contains "$OUTPUT" "Icon Forge reconciliation"
assert_file_contains "$OUTPUT" "Applied: 3"
assert_file_contains "$OUTPUT" "Missing applications: 1"
assert_file_contains "$OUTPUT" "Ambiguous matches: 1"
assert_file_contains "$OUTPUT" "Needs forge: 1"
assert_file_contains "$OUTPUT" "Needs authorization: 1"
assert_file_contains "$OUTPUT" "Failed: 2"
assert_file_contains "$OUTPUT" "skipme: skipped"
assert_file_contains "$OUTPUT" "ambiguous: ambiguous"
assert_file_contains "$OUTPUT" "ghost: missing-app"
assert_file_contains "$OUTPUT" "pngonly: needs-forge"
assert_file_contains "$OUTPUT" "multiicns: failed"
assert_file_contains "$OUTPUT" "failsign: failed"
assert_file_contains "$OUTPUT" "protected: needs-authorization"
assert_not_exists "$HOME_DIR/Applications/Visual Studio Code.app/Contents/Resources/CodeIcon_ugly.icns"
assert_not_exists "$HOME_DIR/Applications/Figma.app/Contents/Resources/FigmaIcon_ugly.icns"
assert_not_exists "$HOME_DIR/Applications/Google Chrome.app/Contents/Resources/ChromeIcon_ugly.icns"
assert_not_exists "$HOME_DIR/Applications/SkipMe.app/Contents/Resources/SkipMeIcon_ugly.icns"
assert_equals "$(shasum -a 256 "$HOME_DIR/Applications/Visual Studio Code.app/Contents/Resources/CodeIcon.icns" | awk '{print $1}')" "$ORIGINAL_CODE_SUM"
assert_equals "$(shasum -a 256 "$HOME_DIR/Applications/Figma.app/Contents/Resources/FigmaIcon.icns" | awk '{print $1}')" "$ORIGINAL_FIGMA_SUM"
assert_not_exists "$HOME_DIR/Applications/FailSign.app/Contents/Resources/FailSignIcon_ugly.icns"
assert_line_count "$FAKE_LOG_DIR/killall.log" 3
assert_line_count "$FAKE_LOG_DIR/qlmanage.log" 1
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "set $HOME_DIR/Applications/Arc Browser.app $ICON_ROOT/arc/arc.icns"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "set $HOME_DIR/Applications/Visual Studio Code.app $ICON_ROOT/code/code.icns"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "set $HOME_DIR/Applications/Figma.app $ICON_ROOT/figma/figma.icns"
assert_file_not_contains "$FAKE_LOG_DIR/native-icon.log" "set $HOME_DIR/Applications/Protected.app"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"
assert_not_exists "$FAKE_LOG_DIR/native-icon.log.disabled"

rm -f "$FAKE_LOG_DIR/"*.log
set +e
run_apply "$OUTPUT" -a
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Reconciliation with remaining failures should return nonzero"; exit 1; }
assert_file_contains "$OUTPUT" "Applied: 3"
assert_file_contains "$OUTPUT" "Already correct: 0"
assert_file_contains "$OUTPUT" "Needs authorization: 1"
assert_file_contains "$OUTPUT" "Failed: 2"
assert_line_count "$FAKE_LOG_DIR/killall.log" 3

DRY_ICON_ROOT="$ABS_TEST_DIR/dry-icon-root"
DRY_HOME="$ABS_TEST_DIR/dry-home"
DRY_OUTPUT="$ABS_TEST_DIR/dry-output.log"
rm -rf "$DRY_ICON_ROOT" "$DRY_HOME"
mkdir -p "$DRY_ICON_ROOT/code" "$DRY_HOME/Applications" "$DRY_HOME/Library/Caches"
cp "$TEST_IMAGE2" "$DRY_ICON_ROOT/code/code.icns"
write_config "$DRY_HOME" "$DRY_ICON_ROOT"
create_fake_app "$DRY_HOME/Applications/Visual Studio Code.app" "com.microsoft.VSCode" loose "CodeIcon"
DRY_BEFORE_SUM="$(shasum -a 256 "$DRY_HOME/Applications/Visual Studio Code.app/Contents/Resources/CodeIcon.icns" | awk '{print $1}')"
rm -f "$FAKE_LOG_DIR/"*.log
HOME="$DRY_HOME" \
ICONFORGE_TEST_LOG_DIR="$FAKE_LOG_DIR" \
PATH="$FAKE_BIN:$PATH" \
ICONFORGE_TOUCH_BIN=touch \
ICONFORGE_CODESIGN_BIN=codesign \
ICONFORGE_NATIVE_ICON="$FAKE_BIN/iconforge-native-icon" \
ICONFORGE_KILLALL_BIN=killall \
ICONFORGE_RM_BIN=rm \
bash "$ROOT_ICONFORGE" apply -a -r "$DRY_ICON_ROOT" -n -v >"$DRY_OUTPUT" 2>&1
assert_file_contains "$DRY_OUTPUT" "Would apply: 1"
assert_file_contains "$DRY_OUTPUT" "code: would-apply"
assert_not_exists "$DRY_HOME/Applications/Visual Studio Code.app/Contents/Resources/CodeIcon_ugly.icns"
assert_equals "$(shasum -a 256 "$DRY_HOME/Applications/Visual Studio Code.app/Contents/Resources/CodeIcon.icns" | awk '{print $1}')" "$DRY_BEFORE_SUM"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"
assert_file_not_contains "$FAKE_LOG_DIR/native-icon.log" "set $DRY_HOME/Applications/Visual Studio Code.app"
assert_not_exists "$FAKE_LOG_DIR/killall.log"
assert_not_exists "$FAKE_LOG_DIR/rm.log"

EXPLICIT_APP="$ABS_TEST_DIR/explicit-app"
rm -rf "$EXPLICIT_APP"
mkdir -p "$EXPLICIT_APP"
create_fake_app "$EXPLICIT_APP/Explicit.app" "com.example.Explicit" loose "ExplicitIcon"
EXPLICIT_ICON="$ABS_TEST_DIR/explicit-replacement.icns"
cp "$TEST_IMAGE1" "$EXPLICIT_ICON"
rm -f "$FAKE_LOG_DIR/"*.log
HOME="$HOME_DIR" \
ICONFORGE_TEST_LOG_DIR="$FAKE_LOG_DIR" \
PATH="$FAKE_BIN:$PATH" \
ICONFORGE_TOUCH_BIN=touch \
ICONFORGE_CODESIGN_BIN=codesign \
ICONFORGE_NATIVE_ICON="$FAKE_BIN/iconforge-native-icon" \
ICONFORGE_KILLALL_BIN=killall \
ICONFORGE_RM_BIN=rm \
bash "$ROOT_ICONFORGE" apply "$EXPLICIT_APP/Explicit.app" --icon "$EXPLICIT_ICON" --strategy internal-icns >"$OUTPUT" 2>&1
assert_file_contains "$OUTPUT" "Strategy: internal-icns"
assert_file_exists "$EXPLICIT_APP/Explicit.app/Contents/Resources/ExplicitIcon_ugly.icns"

echo "🎉 $TEST_NAME passed"
