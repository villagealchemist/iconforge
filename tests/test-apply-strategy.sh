#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="apply strategy selection and safety"
source tests/test-common.sh

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
  grep -F -- "$needle" "$file_path" >/dev/null || { echo "❌ Expected $file_path to contain '$needle'"; exit 1; }
}

assert_file_not_contains() {
  local file_path="$1"
  local needle="$2"
  [[ ! -f "$file_path" ]] || ! grep -F -- "$needle" "$file_path" >/dev/null || { echo "❌ Expected $file_path not to contain '$needle'"; exit 1; }
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
  *-dv*VendorSigned.app*)
    printf 'TeamIdentifier=EXAMPLE123\n' >&2
    ;;
  *--verify*VerifyFail.app*)
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

  cat > "$FAKE_BIN/iconforge-native-icon" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ICONFORGE_TEST_LOG_DIR}/native-icon.log"
case "${1:-}" in
  set)
    : > "${ICONFORGE_TEST_LOG_DIR}/native-icon-active"
    ;;
  test)
    [[ -f "${ICONFORGE_TEST_LOG_DIR}/native-icon-active" ]]
    ;;
  remove)
    /bin/rm -f "${ICONFORGE_TEST_LOG_DIR}/native-icon-active"
    ;;
esac
EOF

  chmod +x "$FAKE_BIN/touch" "$FAKE_BIN/codesign" "$FAKE_BIN/killall" "$FAKE_BIN/qlmanage" "$FAKE_BIN/rm" "$FAKE_BIN/iconforge-native-icon"
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
  ICONFORGE_KILLALL_BIN=killall \
  ICONFORGE_RM_BIN=rm \
  ICONFORGE_NATIVE_ICON="$FAKE_BIN/iconforge-native-icon" \
  bash "$ROOT_ICONFORGE" apply "$@" >"$output_file" 2>&1
}

run_apply_without_native_helper() {
  local output_file="$1"
  shift
  ICONFORGE_TEST_LOG_DIR="$FAKE_LOG_DIR" \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  ICONFORGE_TOUCH_BIN=touch \
  ICONFORGE_CODESIGN_BIN=codesign \
  ICONFORGE_KILLALL_BIN=killall \
  ICONFORGE_RM_BIN=rm \
  ICONFORGE_NATIVE_ICON="$FAKE_BIN/iconforge-native-icon" \
  bash "$ROOT_ICONFORGE" apply "$@" >"$output_file" 2>&1
}

run_restore() {
  local output_file="$1"
  shift
  ICONFORGE_TEST_LOG_DIR="$FAKE_LOG_DIR" \
  PATH="$FAKE_BIN:$PATH" \
  ICONFORGE_TOUCH_BIN=touch \
  ICONFORGE_CODESIGN_BIN=codesign \
  ICONFORGE_KILLALL_BIN=killall \
  ICONFORGE_RM_BIN=rm \
  ICONFORGE_NATIVE_ICON="$FAKE_BIN/iconforge-native-icon" \
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

run_apply "$OUTPUT" "$APP_INTERNAL" -i "$REPLACEMENT_ICON" -s internal-icns
assert_file_contains "$OUTPUT" "Strategy: internal-icns"
assert_dir_exists "$APP_INTERNAL"
assert_file_exists "$APP_INTERNAL/Contents/Resources/InternalIcon_ugly.icns"
assert_file_contains "$FAKE_LOG_DIR/touch.log" "$APP_INTERNAL"
assert_file_contains "$FAKE_LOG_DIR/codesign.log" "$APP_INTERNAL"
assert_equals "$(shasum -a 256 "$APP_INTERNAL/Contents/Resources/InternalIcon_ugly.icns" | awk '{print $1}')" "$ORIGINAL_INTERNAL_SUM"
assert_equals "$(shasum -a 256 "$APP_INTERNAL/Contents/Resources/InternalIcon.icns" | awk '{print $1}')" "$(shasum -a 256 "$REPLACEMENT_ICON" | awk '{print $1}')"

rm -f "$FAKE_LOG_DIR/"*.log
run_restore "$OUTPUT" "$APP_INTERNAL"
assert_file_contains "$OUTPUT" "Restored icon: $APP_INTERNAL/Contents/Resources/InternalIcon.icns"
assert_equals "$(shasum -a 256 "$APP_INTERNAL/Contents/Resources/InternalIcon.icns" | awk '{print $1}')" "$ORIGINAL_INTERNAL_SUM"
assert_file_not_contains "$FAKE_LOG_DIR/native-icon.log" "remove $APP_INTERNAL"

rm -f "$FAKE_LOG_DIR/"*.log
ORIGINAL_FILEICON_SUM="$(shasum -a 256 "$APP_FILEICON/Contents/Resources/FileiconIcon.icns" | awk '{print $1}')"
run_apply "$OUTPUT" "$APP_FILEICON" --icon "$REPLACEMENT_ICON" --strategy fileicon
assert_file_contains "$OUTPUT" "Strategy: native"
assert_file_contains "$OUTPUT" "Applied Finder custom icon: $APP_FILEICON_REALPATH"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "set $APP_FILEICON_REALPATH $REPLACEMENT_ICON"
assert_not_exists "$APP_FILEICON/Contents/Resources/FileiconIcon_ugly.icns"
assert_equals "$(shasum -a 256 "$APP_FILEICON/Contents/Resources/FileiconIcon.icns" | awk '{print $1}')" "$ORIGINAL_FILEICON_SUM"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"

rm -f "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_ASSET" --icon "$REPLACEMENT_ICON"
assert_file_contains "$OUTPUT" "Strategy: native"
assert_file_contains "$OUTPUT" "Applied Finder custom icon: $APP_ASSET_REALPATH"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "set $APP_ASSET_REALPATH $REPLACEMENT_ICON"
assert_not_exists "$FAKE_LOG_DIR/touch.log"

run_restore "$OUTPUT" "$APP_ASSET"
assert_file_contains "$OUTPUT" "Removed Finder custom icon: $APP_ASSET_REALPATH"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "remove $APP_ASSET_REALPATH"
assert_not_exists "$FAKE_LOG_DIR/native-icon-active"

rm -f "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_ASSET" -i "$REPLACEMENT_ICON" -n
assert_file_contains "$OUTPUT" "Strategy: native"
assert_file_contains "$OUTPUT" "Planned Finder custom icon target: $APP_ASSET_REALPATH"
assert_file_not_contains "$FAKE_LOG_DIR/native-icon.log" "set $APP_ASSET_REALPATH"

run_restore "$OUTPUT" "$APP_ASSET" -n
assert_file_contains "$OUTPUT" "Planned removal of Finder custom icon: $APP_ASSET_REALPATH"
assert_file_not_contains "$FAKE_LOG_DIR/native-icon.log" "remove $APP_ASSET_REALPATH"

rm -f "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_ASSET" -i "$REPLACEMENT_ICON" -c
assert_file_contains "$OUTPUT" "Cache refresh: requested"
assert_file_contains "$FAKE_LOG_DIR/killall.log" "Finder"

run_restore "$OUTPUT" "$APP_ASSET" -c
assert_file_contains "$OUTPUT" "Removed Finder custom icon: $APP_ASSET_REALPATH"
assert_file_contains "$FAKE_LOG_DIR/killall.log" "iconservicesagent"

rm -f "$FAKE_LOG_DIR/"*.log
mv "$FAKE_BIN/iconforge-native-icon" "$FAKE_BIN/iconforge-native-icon.disabled"
set +e
run_apply_without_native_helper "$OUTPUT" "$APP_ASSET" --icon "$REPLACEMENT_ICON" --strategy fileicon
STATUS=$?
set -e
mv "$FAKE_BIN/iconforge-native-icon.disabled" "$FAKE_BIN/iconforge-native-icon"
[[ "$STATUS" -ne 0 ]] || { echo "❌ Missing native helper should fail"; exit 1; }
assert_file_contains "$OUTPUT" "Bundled native icon helper not found or not executable"
assert_not_exists "$FAKE_LOG_DIR/native-icon.log"

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
assert_file_contains "$OUTPUT" "Strategy: native"
assert_file_contains "$OUTPUT" "Planned Finder custom icon target"
assert_not_exists "$APP_DRY_RUN/Contents/Resources/DryRunIcon_ugly.icns"
assert_equals "$(shasum -a 256 "$APP_DRY_RUN/Contents/Resources/DryRunIcon.icns" | awk '{print $1}')" "$DRYRUN_BEFORE"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"
assert_file_not_contains "$FAKE_LOG_DIR/native-icon.log" "set $APP_DRY_RUN"

set +e
run_apply "$OUTPUT" "$APP_ASSET" --icon "$REPLACEMENT_ICON" --strategy internal-icns
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Internal strategy should refuse asset-backed apps by default"; exit 1; }
assert_file_contains "$OUTPUT" "Refusing icon replacement without --force-asset"

APP_FORCED="$ABS_TEST_DIR/ForcedAsset.app"
create_fake_app "$APP_FORCED" "com.example.forced" asset "ForcedIcon"
rm -f "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_FORCED" -i "$REPLACEMENT_ICON" -s internal-icns -f -S
assert_file_contains "$OUTPUT" "Strategy: internal-icns"
assert_file_exists "$APP_FORCED/Contents/Resources/ForcedIcon_ugly.icns"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"

APP_COMPAT="$ABS_TEST_DIR/Compat.app"
create_fake_app "$APP_COMPAT" "com.example.compat" loose "CompatIcon"
rm -f "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_COMPAT" --icon "$REPLACEMENT_ICON"
assert_file_contains "$OUTPUT" "Strategy: native"
assert_not_exists "$APP_COMPAT/Contents/Resources/CompatIcon_ugly.icns"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "set $APP_COMPAT $REPLACEMENT_ICON"

APP_FALLBACK="$ABS_TEST_DIR/Fallback.app"
create_fake_app "$APP_FALLBACK" "com.example.fallback" loose "FallbackIcon"
rm -f "$FAKE_LOG_DIR/"*.log
mv "$FAKE_BIN/iconforge-native-icon" "$FAKE_BIN/iconforge-native-icon.disabled"
run_apply_without_native_helper "$OUTPUT" "$APP_FALLBACK" --icon "$REPLACEMENT_ICON"
mv "$FAKE_BIN/iconforge-native-icon.disabled" "$FAKE_BIN/iconforge-native-icon"
assert_file_contains "$OUTPUT" "Strategy: internal-icns"
assert_file_exists "$APP_FALLBACK/Contents/Resources/FallbackIcon_ugly.icns"

rm -f "$FAKE_LOG_DIR/"*.log
mv "$FAKE_BIN/iconforge-native-icon" "$FAKE_BIN/iconforge-native-icon.disabled"
set +e
run_apply_without_native_helper "$OUTPUT" "$APP_ASSET" --icon "$REPLACEMENT_ICON"
STATUS=$?
set -e
mv "$FAKE_BIN/iconforge-native-icon.disabled" "$FAKE_BIN/iconforge-native-icon"
[[ "$STATUS" -ne 0 ]] || { echo "❌ Asset-backed app should not fall back without the native helper"; exit 1; }
assert_file_contains "$OUTPUT" "asset-catalog backed"

APP_VENDOR_SIGNED="$ABS_TEST_DIR/VendorSigned.app"
create_fake_app "$APP_VENDOR_SIGNED" "com.example.vendor-signed" loose "VendorIcon"
APP_VENDOR_SIGNED_REALPATH="$(cd "$(dirname "$APP_VENDOR_SIGNED")" && pwd)/$(basename "$APP_VENDOR_SIGNED")"
rm -f "$FAKE_LOG_DIR/native-icon-active" "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_VENDOR_SIGNED" --icon "$REPLACEMENT_ICON"
assert_file_contains "$OUTPUT" "Strategy: native"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "set $APP_VENDOR_SIGNED_REALPATH $REPLACEMENT_ICON"
assert_not_exists "$APP_VENDOR_SIGNED/Contents/Resources/VendorIcon_ugly.icns"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"

rm -f "$FAKE_LOG_DIR/"*.log
mv "$FAKE_BIN/iconforge-native-icon" "$FAKE_BIN/iconforge-native-icon.disabled"
set +e
run_apply_without_native_helper "$OUTPUT" "$APP_VENDOR_SIGNED" --icon "$REPLACEMENT_ICON"
STATUS=$?
set -e
mv "$FAKE_BIN/iconforge-native-icon.disabled" "$FAKE_BIN/iconforge-native-icon"
[[ "$STATUS" -ne 0 ]] || { echo "❌ Vendor-signed app should not fall back without the native helper"; exit 1; }
assert_file_contains "$OUTPUT" "vendor signed"

APP_VERIFY_FAIL="$ABS_TEST_DIR/VerifyFail.app"
create_fake_app "$APP_VERIFY_FAIL" "com.example.verify-fail" loose "VerifyFailIcon"
cp "$TEST_IMAGE2" "$APP_VERIFY_FAIL/Contents/Resources/VerifyFailIcon.icns"
VERIFY_FAIL_ORIGINAL_SUM="$(shasum -a 256 "$APP_VERIFY_FAIL/Contents/Resources/VerifyFailIcon.icns" | awk '{print $1}')"
rm -f "$FAKE_LOG_DIR/"*.log
set +e
run_apply "$OUTPUT" "$APP_VERIFY_FAIL" --icon "$REPLACEMENT_ICON" --strategy internal-icns
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Failed signature verification should fail apply"; exit 1; }
assert_file_contains "$OUTPUT" "Ad hoc signature verification failed"
assert_file_contains "$OUTPUT" "restoring the preserved icon backup"
assert_file_exists "$APP_VERIFY_FAIL/Contents/Resources/VerifyFailIcon_ugly.icns"
assert_equals "$(shasum -a 256 "$APP_VERIFY_FAIL/Contents/Resources/VerifyFailIcon.icns" | awk '{print $1}')" "$VERIFY_FAIL_ORIGINAL_SUM"

APP_EXISTING_NATIVE="$ABS_TEST_DIR/ExistingNative.app"
create_fake_app "$APP_EXISTING_NATIVE" "com.example.existing-native" loose "ExistingNativeIcon"
APP_EXISTING_NATIVE_REALPATH="$(cd "$(dirname "$APP_EXISTING_NATIVE")" && pwd)/$(basename "$APP_EXISTING_NATIVE")"
: > "$FAKE_LOG_DIR/native-icon-active"
rm -f "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_EXISTING_NATIVE" --icon "$REPLACEMENT_ICON"
assert_file_contains "$OUTPUT" "Strategy: native"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "test $APP_EXISTING_NATIVE_REALPATH"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "set $APP_EXISTING_NATIVE_REALPATH $REPLACEMENT_ICON"
assert_not_exists "$APP_EXISTING_NATIVE/Contents/Resources/ExistingNativeIcon_ugly.icns"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"

APP_LEGACY="$ABS_TEST_DIR/Legacy.app"
create_fake_app "$APP_LEGACY" "com.example.legacy" loose "LegacyIcon"
run_apply "$OUTPUT" "$APP_LEGACY" --icon "$REPLACEMENT_ICON" --strategy internal-icns
rm -f "$FAKE_LOG_DIR/native-icon-active" "$FAKE_LOG_DIR/"*.log
run_apply "$OUTPUT" "$APP_LEGACY" --icon "$REPLACEMENT_ICON"
assert_file_contains "$OUTPUT" "Strategy: native"
assert_file_contains "$OUTPUT" "A legacy internal icon backup remains"
assert_file_contains "$OUTPUT" "reinstall that app from its trusted source"

rm -f "$FAKE_LOG_DIR/"*.log
run_restore "$OUTPUT" "$APP_LEGACY"
assert_file_contains "$OUTPUT" "Restored icon: $APP_LEGACY/Contents/Resources/LegacyIcon.icns"
assert_file_contains "$OUTPUT" "Removed Finder custom icon: $APP_LEGACY"
assert_file_contains "$FAKE_LOG_DIR/native-icon.log" "remove $APP_LEGACY"

run_apply "$OUTPUT" "$APP_LEGACY" --icon "$REPLACEMENT_ICON" --strategy native
rm -f "$FAKE_LOG_DIR/"*.log
run_restore "$OUTPUT" "$APP_LEGACY" --dry-run
assert_file_contains "$OUTPUT" "Planned restore target: $APP_LEGACY/Contents/Resources/LegacyIcon.icns"
assert_file_contains "$OUTPUT" "Planned removal of Finder custom icon: $APP_LEGACY"
assert_file_not_contains "$FAKE_LOG_DIR/native-icon.log" "remove $APP_LEGACY"

APP_PROTECTED="$ABS_TEST_DIR/Protected.app"
create_fake_app "$APP_PROTECTED" "com.example.protected" loose "ProtectedIcon"
APP_PROTECTED_REALPATH="$(cd "$(dirname "$APP_PROTECTED")" && pwd)/$(basename "$APP_PROTECTED")"
rm -f "$FAKE_LOG_DIR/native-icon-active" "$FAKE_LOG_DIR/"*.log
chmod 0555 "$APP_PROTECTED" "$APP_PROTECTED/Contents" "$APP_PROTECTED/Contents/Resources"
chmod 0444 "$APP_PROTECTED/Contents/Info.plist" "$APP_PROTECTED/Contents/Resources/ProtectedIcon.icns"
set +e
run_apply "$OUTPUT" "$APP_PROTECTED" --icon "$REPLACEMENT_ICON"
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Protected app should require authorization"; exit 1; }
assert_file_contains "$OUTPUT" "Administrator authorization is required"
assert_file_contains "$OUTPUT" "scoped elevation"
assert_file_not_contains "$FAKE_LOG_DIR/native-icon.log" "set $APP_PROTECTED_REALPATH"
assert_not_exists "$APP_PROTECTED/Contents/Resources/ProtectedIcon_ugly.icns"

rm -f "$FAKE_LOG_DIR/"*.log
set +e
run_apply "$OUTPUT" "$APP_PROTECTED" --icon "$REPLACEMENT_ICON" --strategy internal-icns
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Explicit internal strategy should reject a protected app"; exit 1; }
assert_file_contains "$OUTPUT" "Internal icon replacement requires write access"
assert_file_contains "$OUTPUT" "Use --strategy native"
assert_not_exists "$APP_PROTECTED/Contents/Resources/ProtectedIcon_ugly.icns"

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
  ICONFORGE_NATIVE_ICON="$FAKE_BIN/iconforge-native-icon" \
  bash "$ROOT_ICONFORGE" apply Twin --icon "$REPLACEMENT_ICON" >"$OUTPUT" 2>&1
)
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Ambiguous app match should fail"; exit 1; }
assert_file_contains "$OUTPUT" "App name is ambiguous"
assert_not_exists "$FAKE_LOG_DIR/touch.log"
assert_not_exists "$FAKE_LOG_DIR/codesign.log"
assert_not_exists "$FAKE_LOG_DIR/native-icon.log"
assert_not_exists "$AMBIGUOUS_WORK/Twin.app/Contents/Resources/TwinIcon_ugly.icns"

set +e
run_apply "$OUTPUT" "$APP_UNRESOLVED" --icon "$REPLACEMENT_ICON" --strategy internal-icns
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]] || { echo "❌ Unresolved loose icon target should fail"; exit 1; }
assert_file_contains "$OUTPUT" "Loose icon target path must not be empty"

echo "🎉 $TEST_NAME passed"
