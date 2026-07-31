#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="apply strategy selection and safety"
source tests/test_common.sh

ROOT_DIR="$(pwd)"
ROOT_ICONFORGE="$ROOT_DIR/iconforge.sh"
ABS_TEST_DIR="$ROOT_DIR/$TEST_DIR"
FAKE_BIN="$ABS_TEST_DIR/fakebin"
FAKE_LOG_DIR="$ABS_TEST_DIR/logs"

assert_equals() {
  [[ "$1" == "$2" ]] || { echo "❌ Expected '$1' == '$2'"; exit 1; }
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || { echo "❌ Expected output to contain '$2'"; exit 1; }
}

assert_not_exists() {
  [[ ! -e "$1" ]] || { echo "❌ Unexpected path exists: $1"; exit 1; }
}

assert_file_contains() {
  local file_path="$1"
  local needle="$2"
  grep -F "$needle" "$file_path" >/dev/null || { echo "❌ Expected $file_path to contain '$needle'"; exit 1; }
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
EOF

  cat > "$FAKE_BIN/fileicon" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ICONFORGE_TEST_LOG_DIR}/fileicon.log"
case "${1:-}" in
  set)
    : > "${ICONFORGE_TEST_LOG_DIR}/fileicon-active"
    ;;
  test)
    [[ -f "${ICONFORGE_TEST_LOG_DIR}/fileicon-active" ]]
    ;;
  rm)
    rm -f "${ICONFORGE_TEST_LOG_DIR}/fileicon-active"
    ;;
esac
EOF

  chmod +x "$FAKE_BIN/touch" "$FAKE_BIN/codesign" "$FAKE_BIN/fileicon"
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
    unresolved)
      cat > "$app_dir/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
</dict>
</plist>
EOF
      ;;
  esac
}

run_apply() {
  local output_file="$1"
  shift
  ICONFORGE_TEST_LOG_DIR="$FAKE_LOG_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  ICONFORGE_TOUCH_BIN=touch \
  ICONFORGE_CODESIGN_BIN=codesign \
  ICONFORGE_FILEICON_BIN=fileicon \
  bash "$ROOT_ICONFORGE" apply "$@" >"$output_file" 2>&1
}

run_apply_without_fileicon() {
  local output_file="$1"
  shift
  ICONFORGE_TEST_LOG_DIR="$FAKE_LOG_DIR" \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  ICONFORGE_TOUCH_BIN=touch \
  ICONFORGE_CODESIGN_BIN=codesign \
  ICONFORGE_FILEICON_BIN=fileicon \
  bash "$ROOT_ICONFORGE" apply "$@" >"$output_file" 2>&1
}

run_restore() {
  local output_file="$1"
  shift
  ICONFORGE_TEST_LOG_DIR="$FAKE_LOG_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  ICONFORGE_TOUCH_BIN=touch \
  ICONFORGE_CODESIGN_BIN=codesign \
  ICONFORGE_FILEICON_BIN=fileicon \
  bash "$ROOT_ICONFORGE" restore "$@" >"$output_file" 2>&1
}

mkdir -p "$TEST_DIR"
setup_fake_bin

REPLACEMENT_ICON="$ABS_TEST_DIR/replacement.icns"
cp "$TEST_IMAGE1" "$REPLACEMENT_ICON"

APP_INTERNAL="$ABS_TEST_DIR/Internal.app"
APP_FILEICON="$ABS_TEST_DIR/Fileicon.app"
APP_ASSET="$ABS_TEST_DIR/Asset.app"
APP_UNRESOLVED="$ABS_TEST_DIR/Unresolved.app"
create_fake_app "$APP_INTERNAL" "com.example.internal" loose "InternalIcon"
create_fake_app "$APP_FILEICON" "com.example.fileicon" loose "FileiconIcon"
create_fake_app "$APP_ASSET" "com.example.asset" asset "AssetIcon"
create_fake_app "$APP_UNRESOLVED" "com.example.unresolved" unresolved

APP_FILEICON_REALPATH="$(cd "$(dirname "$APP_FILEICON")" && pwd)/$(basename "$APP_FILEICON")"
APP_ASSET_REALPATH="$(cd "$(dirname "$APP_ASSET")" && pwd)/$(basename "$APP_ASSET")"
ORIGINAL_INTERNAL_SUM="$(shasum -a 256 "$APP_INTERNAL/Contents/Resources/InternalIcon.icns" | awk '{print $1}')"
OUTPUT="$ABS_TEST_DIR/output.log"

run_apply "$OUTPUT" "$APP_INTERNAL" --icon "$REPLACEMENT_ICON" --strategy internal-icns
assert_file_contains "$OUTPUT" "Strategy: internal-icns"
assert_dir_exists "$APP_INTERNAL"
assert_file_exists "$APP_INTERNAL/Contents/Resources/InternalIcon_ugly.icns"
assert_file_contains "$FAKE_LOG_DIR/touch.log" "$APP_INTERNAL"
assert_file_contains "$FAKE_LOG_DIR/codesign.log" "$APP_INTERNAL"
assert_equals "$(shasum -a 256 "$APP_INTERNAL/Contents/Resources/InternalIcon_ugly.icns" | awk '{print $1}')" "$ORIGINAL_INTERNAL_SUM"
assert_equals "$(shasum -a 256 "$APP_INTERNAL/Contents/Resources/InternalIcon.icns" | awk '{print $1}')" "$(shasum -a 256 "$REPLACEMENT_ICON" | awk '{print $1}')"

rm -f "$FAKE_LOG_DIR/"*.log
ORIGINAL_FILEICON_SUM="$(shasum -a 256 "$APP_FILEICON/Contents/Resources/FileiconIcon.icns" | awk '{print $1}')"
run_apply "$OUTPUT" "$APP_FILEICON" --icon "$REPLACEMENT_ICON" --strategy fileicon
assert_file_contains "$OUTPUT" "Strategy: fileicon"
assert_file_contains "$FAKE_LOG_DIR/fileicon.log" "set $APP_FILEICON_REALPATH $REPLACEMENT_ICON"
assert_not_exists "$APP_FILEICON/Contents/Resources/FileiconIcon_ugly.icns"
assert_equals "$(shasum -a 256 "$APP_FILEICON/Contents/Resources/FileiconIcon.icns" | awk '{print $1}')" "$ORIGINAL_FILEICON_SUM"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"

rm -f "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_ASSET" --icon "$REPLACEMENT_ICON"
assert_file_contains "$OUTPUT" "Strategy: fileicon"
assert_file_contains "$FAKE_LOG_DIR/fileicon.log" "set $APP_ASSET_REALPATH $REPLACEMENT_ICON"
assert_not_exists "$FAKE_LOG_DIR/touch.log"

run_restore "$OUTPUT" "$APP_ASSET"
assert_file_contains "$OUTPUT" "Removed fileicon custom icon: $APP_ASSET_REALPATH"
assert_file_contains "$FAKE_LOG_DIR/fileicon.log" "rm $APP_ASSET_REALPATH"
assert_not_exists "$FAKE_LOG_DIR/fileicon-active"

rm -f "$FAKE_LOG_DIR/"*.log
mv "$FAKE_BIN/fileicon" "$FAKE_BIN/fileicon.disabled"
set +e
run_apply_without_fileicon "$OUTPUT" "$APP_ASSET" --icon "$REPLACEMENT_ICON" --strategy fileicon
STATUS=$?
set -e
mv "$FAKE_BIN/fileicon.disabled" "$FAKE_BIN/fileicon"
[[ "$STATUS" -ne 0 ]] || { echo "❌ Missing fileicon should fail"; exit 1; }
assert_file_contains "$OUTPUT" "Missing required tool: fileicon"
assert_not_exists "$FAKE_LOG_DIR/fileicon.log"

set +e
run_apply "$OUTPUT" "" --icon "$REPLACEMENT_ICON"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Empty app path should fail"; exit 1; }
assert_file_contains "$OUTPUT" "apply requires an app argument"

set +e
run_apply "$OUTPUT" "$APP_INTERNAL" --icon ""
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Empty icon path should fail"; exit 1; }
assert_file_contains "$OUTPUT" "apply requires --icon <file.icns>"

set +e
run_apply "$OUTPUT" "$ABS_TEST_DIR/Missing.app" --icon "$REPLACEMENT_ICON"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Nonexistent app should fail"; exit 1; }
assert_file_contains "$OUTPUT" "Could not resolve app bundle"

set +e
run_apply "$OUTPUT" "$APP_INTERNAL" --icon "$ABS_TEST_DIR/missing.icns"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Nonexistent icon should fail"; exit 1; }
assert_file_contains "$OUTPUT" "Icon file not found"

APP_DRY_RUN="$ABS_TEST_DIR/DryRun.app"
create_fake_app "$APP_DRY_RUN" "com.example.dryrun" loose "DryRunIcon"
DRYRUN_BEFORE="$(shasum -a 256 "$APP_DRY_RUN/Contents/Resources/DryRunIcon.icns" | awk '{print $1}')"
rm -f "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_DRY_RUN" --icon "$REPLACEMENT_ICON" --dry-run
assert_file_contains "$OUTPUT" "Strategy: internal-icns"
assert_not_exists "$APP_DRY_RUN/Contents/Resources/DryRunIcon_ugly.icns"
assert_equals "$(shasum -a 256 "$APP_DRY_RUN/Contents/Resources/DryRunIcon.icns" | awk '{print $1}')" "$DRYRUN_BEFORE"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"
assert_not_exists "$FAKE_LOG_DIR/fileicon.log"

set +e
run_apply "$OUTPUT" "$APP_ASSET" --icon "$REPLACEMENT_ICON" --strategy internal-icns
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Internal strategy should refuse asset-backed apps by default"; exit 1; }
assert_file_contains "$OUTPUT" "Refusing icon replacement without --force-asset"

APP_COMPAT="$ABS_TEST_DIR/Compat.app"
create_fake_app "$APP_COMPAT" "com.example.compat" loose "CompatIcon"
rm -f "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_COMPAT" --icon "$REPLACEMENT_ICON"
assert_file_contains "$OUTPUT" "Strategy: internal-icns"
assert_file_exists "$APP_COMPAT/Contents/Resources/CompatIcon_ugly.icns"
assert_file_contains "$FAKE_LOG_DIR/touch.log" "$APP_COMPAT"
assert_file_contains "$FAKE_LOG_DIR/codesign.log" "$APP_COMPAT"

AMBIGUOUS_HOME="$ABS_TEST_DIR/home"
AMBIGUOUS_WORK="$ABS_TEST_DIR/ambiguous-work"
mkdir -p "$AMBIGUOUS_HOME/Applications" "$AMBIGUOUS_WORK"
create_fake_app "$AMBIGUOUS_HOME/Applications/Twin.app" "com.example.twin.home" loose "TwinIcon"
create_fake_app "$AMBIGUOUS_WORK/Twin.app" "com.example.twin.work" loose "TwinIcon"
rm -f "$FAKE_LOG_DIR/"*.log
set +e
(
  cd "$AMBIGUOUS_WORK"
  HOME="$AMBIGUOUS_HOME" \
  ICONFORGE_TEST_LOG_DIR="$FAKE_LOG_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  ICONFORGE_TOUCH_BIN=touch \
  ICONFORGE_CODESIGN_BIN=codesign \
  ICONFORGE_FILEICON_BIN=fileicon \
  bash "$ROOT_ICONFORGE" apply Twin --icon "$REPLACEMENT_ICON" >"$OUTPUT" 2>&1
)
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Ambiguous app match should fail"; exit 1; }
assert_file_contains "$OUTPUT" "App name is ambiguous"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"
assert_not_exists "$FAKE_LOG_DIR/fileicon.log"
assert_not_exists "$AMBIGUOUS_WORK/Twin.app/Contents/Resources/TwinIcon_ugly.icns"

set +e
run_apply "$OUTPUT" "$APP_UNRESOLVED" --icon "$REPLACEMENT_ICON" --strategy internal-icns
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Unresolved loose icon target should fail"; exit 1; }
assert_file_contains "$OUTPUT" "Loose icon target path must not be empty"

echo "🎉 $TEST_NAME passed"
