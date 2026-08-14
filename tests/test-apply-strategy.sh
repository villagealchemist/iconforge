#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="direct apply, restore, and strategy safety"
source tests/test-common.sh

BIN="$PWD/iconforge.sh"
REAL_HELPER="$PWD/iconforge-native-icon/iconforge-native-icon"
ABS_TEST_DIR="$PWD/$TEST_DIR"
FAKE_BIN="$ABS_TEST_DIR/fakebin"
LOGS="$ABS_TEST_DIR/logs"
HOME_DIR="$ABS_TEST_DIR/home"
OUTPUT="$ABS_TEST_DIR/output.log"
mkdir -p "$FAKE_BIN" "$LOGS" "$HOME_DIR/Library/Caches"

make_test_icns "$TEST_IMAGE1" "$ABS_TEST_DIR/original.icns"
make_test_icns "$TEST_IMAGE2" "$ABS_TEST_DIR/replacement.icns"

create_app() {
  local app="$1"
  local icon_name="$2"
  local mode="${3:-loose}"
  mkdir -p "$app/Contents/Resources"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "com.example.${icon_name}" "$app/Contents/Info.plist"
  plutil -insert CFBundleDisplayName -string "${app##*/}" "$app/Contents/Info.plist"
  plutil -insert CFBundleIconFile -string "$icon_name" "$app/Contents/Info.plist"
  cp "$ABS_TEST_DIR/original.icns" "$app/Contents/Resources/$icon_name.icns"
  [[ "$mode" != asset ]] || : >"$app/Contents/Resources/Assets.car"
}

cat >"$FAKE_BIN/native-helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$ICONFORGE_TEST_LOG_DIR/native.log"
case "$1" in
  normalize|validate|path-key|link-exclusive|user-home) exec "$ICONFORGE_REAL_HELPER" "$@" ;;
  rename-exact)
    "$ICONFORGE_REAL_HELPER" "$@"
    status=$?
    if [[ -f "$ICONFORGE_TEST_LOG_DIR/signal-on-rename" &&
          ! -f "$ICONFORGE_TEST_LOG_DIR/signal-fired" ]]; then
      signal_name="$(<"$ICONFORGE_TEST_LOG_DIR/signal-on-rename")"
      [[ -n "$signal_name" ]] || signal_name=TERM
      : >"$ICONFORGE_TEST_LOG_DIR/signal-fired"
      kill -"$signal_name" "$PPID"
    fi
    exit "$status"
    ;;
  set) : >"$ICONFORGE_TEST_LOG_DIR/native-${2##*/}" ;;
  test) [[ -f "$ICONFORGE_TEST_LOG_DIR/native-${2##*/}" ]] ;;
  present)
    [[ ! -f "$ICONFORGE_TEST_LOG_DIR/force-present-failure" ]] || exit 70
    [[ -f "$ICONFORGE_TEST_LOG_DIR/native-${2##*/}" ]]
    ;;
  remove) /bin/rm -f "$ICONFORGE_TEST_LOG_DIR/native-${2##*/}" ;;
  *) exit 64 ;;
esac
EOF
cat >"$FAKE_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$ICONFORGE_TEST_LOG_DIR/codesign.log"
if [[ -f "$ICONFORGE_TEST_LOG_DIR/force-verify-failure" ]]; then
  case "$*" in *--verify*VerifyFail.app*) exit 1 ;; esac
fi
EOF
cat >"$FAKE_BIN/touch" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ICONFORGE_TEST_LOG_DIR/touch.log"
EOF
cat >"$FAKE_BIN/cp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count_file="$ICONFORGE_TEST_LOG_DIR/cp-count"
count=0
[[ ! -f "$count_file" ]] || count="$(<"$count_file")"
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
destination=""
for destination in "$@"; do :; done
if [[ -f "$ICONFORGE_TEST_LOG_DIR/cp-fail-at" && "$(<"$ICONFORGE_TEST_LOG_DIR/cp-fail-at")" -eq "$count" ]]; then
  printf 'partial copy\n' >"$destination"
  exit 1
fi
exec /bin/cp "$@"
EOF
cat >"$FAKE_BIN/killall" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ICONFORGE_TEST_LOG_DIR/killall.log"
EOF
cat >"$FAKE_BIN/rm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ICONFORGE_TEST_LOG_DIR/rm.log"
EOF
chmod +x "$FAKE_BIN"/*

run_cli() {
  HOME="$HOME_DIR" \
  ICONFORGE_TEST_LOG_DIR="$LOGS" \
  ICONFORGE_REAL_HELPER="$REAL_HELPER" \
  ICONFORGE_NATIVE_ICON="$FAKE_BIN/native-helper" \
  ICONFORGE_CODESIGN_BIN="${ICONFORGE_TEST_CODESIGN_BIN:-$FAKE_BIN/codesign}" \
  ICONFORGE_TOUCH_BIN="${ICONFORGE_TEST_TOUCH_BIN:-$FAKE_BIN/touch}" \
  ICONFORGE_CP_BIN="$FAKE_BIN/cp" \
  ICONFORGE_KILLALL_BIN="$FAKE_BIN/killall" \
  ICONFORGE_RM_BIN="$FAKE_BIN/rm" \
  "$BIN" "$@" >"$OUTPUT" 2>&1
}

# These assignments are intentionally scoped to the sourced-code test subshell.
# shellcheck disable=SC2030
run_cli_with_nuke_rejected() (
  [[ "${1:-}" != apply ]] || shift
  export HOME="$HOME_DIR"
  export ICONFORGE_ROOT="$PWD"
  export ICONFORGE_TEST_LOG_DIR="$LOGS"
  export ICONFORGE_REAL_HELPER="$REAL_HELPER"
  export ICONFORGE_NATIVE_ICON="$FAKE_BIN/native-helper"
  export ICONFORGE_CODESIGN_BIN="$FAKE_BIN/codesign"
  export ICONFORGE_TOUCH_BIN="$FAKE_BIN/touch"
  export ICONFORGE_CP_BIN="$FAKE_BIN/cp"
  export ICONFORGE_KILLALL_BIN="$FAKE_BIN/killall"
  export ICONFORGE_RM_BIN="$FAKE_BIN/rm"
  source "$PWD/lib/iconforge/common.sh"
  source "$PWD/lib/iconforge/library.sh"
  source "$PWD/lib/iconforge/discovery.sh"
  source "$PWD/lib/iconforge/match.sh"
  source "$PWD/lib/iconforge/strategy-internal-icns.sh"
  source "$PWD/lib/iconforge/strategy-native-icon.sh"
  source "$PWD/lib/iconforge/strategy.sh"
  source "$PWD/lib/iconforge/apps.sh"
  nuke_validate_current_user() { fail "Simulated unsafe Nuke user"; return 1; }
  cmd_apply "$@"
) >"$OUTPUT" 2>&1

assert_output() { grep -F -- "$1" "$OUTPUT" >/dev/null || { test_fail "Missing output: $1"; exit 1; }; }
assert_log() { grep -F -- "$2" "$1" >/dev/null || { test_fail "Missing log entry '$2' in $1"; exit 1; }; }

NATIVE_APP="$ABS_TEST_DIR/Native.app"
INTERNAL_APP="$ABS_TEST_DIR/Internal.app"
ASSET_APP="$ABS_TEST_DIR/Asset.app"
VERIFY_FAIL_APP="$ABS_TEST_DIR/VerifyFail.app"
LEADING_APP="$ABS_TEST_DIR/-Leading.app"
SYMLINK_APP="$ABS_TEST_DIR/SymlinkTarget.app"
SYMLINK_BACKUP_APP="$ABS_TEST_DIR/SymlinkBackup.app"
MALFORMED_BACKUP_APP="$ABS_TEST_DIR/MalformedBackup.app"
AMBIGUOUS_BACKUP_APP="$ABS_TEST_DIR/AmbiguousBackup.app"
CP_BACKUP_FAIL_APP="$ABS_TEST_DIR/BackupCopyFail.app"
CP_REPLACEMENT_FAIL_APP="$ABS_TEST_DIR/ReplacementCopyFail.app"
RESTORE_COPY_FAIL_APP="$ABS_TEST_DIR/RestoreCopyFail.app"
UPPERCASE_ICON_APP="$ABS_TEST_DIR/UppercaseIcon.app"
DECOY_BACKUP_APP="$ABS_TEST_DIR/DecoyBackup.app"
CASE_ASSET_APP="$ABS_TEST_DIR/CaseAsset.app"
SYMLINK_ASSET_APP="$ABS_TEST_DIR/SymlinkAsset.app"
DIRECTORY_ASSET_APP="$ABS_TEST_DIR/DirectoryAsset.app"
INFO_SYMLINK_APP="$ABS_TEST_DIR/InfoSymlink.app"
SIGNAL_APPLY_APP="$ABS_TEST_DIR/SignalApply.app"
SIGNAL_RESTORE_APP="$ABS_TEST_DIR/SignalRestore.app"
PRESENT_FAIL_APP="$ABS_TEST_DIR/PresentFail.app"
MISSING_CODESIGN_APP="$ABS_TEST_DIR/MissingCodesign.app"
create_app "$NATIVE_APP" NativeIcon
create_app "$INTERNAL_APP" InternalIcon
create_app "$ASSET_APP" AssetIcon asset
create_app "$VERIFY_FAIL_APP" VerifyIcon
create_app "$LEADING_APP" LeadingIcon
create_app "$SYMLINK_APP" LinkIcon
create_app "$SYMLINK_BACKUP_APP" BackupLink
create_app "$MALFORMED_BACKUP_APP" Malformed
create_app "$AMBIGUOUS_BACKUP_APP" Ambiguous
create_app "$CP_BACKUP_FAIL_APP" BackupCopyFail
create_app "$CP_REPLACEMENT_FAIL_APP" ReplacementCopyFail
create_app "$RESTORE_COPY_FAIL_APP" RestoreCopyFail
create_app "$UPPERCASE_ICON_APP" Upper
create_app "$DECOY_BACKUP_APP" Main
create_app "$CASE_ASSET_APP" CaseAsset
create_app "$SYMLINK_ASSET_APP" SymlinkAsset
create_app "$DIRECTORY_ASSET_APP" DirectoryAsset
create_app "$INFO_SYMLINK_APP" InfoSymlink
create_app "$SIGNAL_APPLY_APP" SignalApply
create_app "$SIGNAL_RESTORE_APP" SignalRestore
create_app "$PRESENT_FAIL_APP" PresentFail
create_app "$MISSING_CODESIGN_APP" MissingCodesign

ORIGINAL_SUM="$(shasum -a 256 "$ABS_TEST_DIR/original.icns" | awk '{print $1}')"
REPLACEMENT_SUM="$(shasum -a 256 "$ABS_TEST_DIR/replacement.icns" | awk '{print $1}')"
cp "$ABS_TEST_DIR/original.icns" "$ABS_TEST_DIR/external.icns"
EXTERNAL_SUM="$(shasum -a 256 "$ABS_TEST_DIR/external.icns" | awk '{print $1}')"
rm "$SYMLINK_APP/Contents/Resources/LinkIcon.icns"
ln -s "$ABS_TEST_DIR/external.icns" "$SYMLINK_APP/Contents/Resources/LinkIcon.icns"
ln -s "$ABS_TEST_DIR/external.icns" "$SYMLINK_BACKUP_APP/Contents/Resources/BackupLink_ugly.icns"
printf 'not an icon' >"$MALFORMED_BACKUP_APP/Contents/Resources/Malformed_ugly.icns"
cp "$ABS_TEST_DIR/original.icns" "$AMBIGUOUS_BACKUP_APP/Contents/Resources/Ambiguous_ugly.icns"
cp "$ABS_TEST_DIR/original.icns" "$AMBIGUOUS_BACKUP_APP/Contents/Resources/Other_ugly.icns"
cp "$ABS_TEST_DIR/original.icns" "$RESTORE_COPY_FAIL_APP/Contents/Resources/RestoreCopyFail_ugly.icns"
cp "$ABS_TEST_DIR/replacement.icns" "$RESTORE_COPY_FAIL_APP/Contents/Resources/RestoreCopyFail.icns"
plutil -replace CFBundleIconFile -string 'Upper.ICNS' "$UPPERCASE_ICON_APP/Contents/Info.plist"
mv "$UPPERCASE_ICON_APP/Contents/Resources/Upper.icns" "$UPPERCASE_ICON_APP/Contents/Resources/Upper.ICNS"
cp "$ABS_TEST_DIR/original.icns" "$UPPERCASE_ICON_APP/Contents/Resources/Upper_ugly.icns"
cp "$ABS_TEST_DIR/replacement.icns" "$UPPERCASE_ICON_APP/Contents/Resources/Upper.ICNS"
cp "$ABS_TEST_DIR/original.icns" "$DECOY_BACKUP_APP/Contents/Resources/Other.icns"
cp "$ABS_TEST_DIR/original.icns" "$DECOY_BACKUP_APP/Contents/Resources/Other_ugly.icns"
: >"$CASE_ASSET_APP/Contents/Resources/Assets.CAR"
: >"$ABS_TEST_DIR/external.car"
ln -s "$ABS_TEST_DIR/external.car" "$SYMLINK_ASSET_APP/Contents/Resources/Assets.car"
mkdir "$DIRECTORY_ASSET_APP/Contents/Resources/Assets.car"
cp "$INFO_SYMLINK_APP/Contents/Info.plist" "$ABS_TEST_DIR/external-info.plist"
rm "$INFO_SYMLINK_APP/Contents/Info.plist"
ln -s "$ABS_TEST_DIR/external-info.plist" "$INFO_SYMLINK_APP/Contents/Info.plist"
/usr/bin/touch -t 200101010101 "$ABS_TEST_DIR/external-info.plist"
cp "$ABS_TEST_DIR/original.icns" "$SIGNAL_RESTORE_APP/Contents/Resources/SignalRestore_ugly.icns"
cp "$ABS_TEST_DIR/replacement.icns" "$SIGNAL_RESTORE_APP/Contents/Resources/SignalRestore.icns"
cp "$ABS_TEST_DIR/original.icns" "$PRESENT_FAIL_APP/Contents/Resources/PresentFail_ugly.icns"
cp "$ABS_TEST_DIR/replacement.icns" "$PRESENT_FAIL_APP/Contents/Resources/PresentFail.icns"

: >"$LOGS/native.log"
native_log_before="$(wc -l <"$LOGS/native.log")"
set +e
run_cli_with_nuke_rejected apply "$NATIVE_APP" -i "$ABS_TEST_DIR/replacement.icns" -n
STATUS=$?
set -e
native_log_after="$(wc -l <"$LOGS/native.log")"
[[ "$STATUS" -eq 1 ]] || { test_fail "Apply with Nuke should reject root before mutation"; exit 1; }
[[ "$native_log_before" == "$native_log_after" ]] || { test_fail "Root Nuke rejection happened after helper work"; exit 1; }

set +e
run_cli_with_nuke_rejected apply -a -n -i "$ABS_TEST_DIR/replacement.icns"
STATUS=$?
set -e
[[ "$STATUS" -eq 2 ]] || { test_fail "Bulk syntax conflicts should precede Nuke user validation"; exit 1; }

run_cli restore "$UPPERCASE_ICON_APP"
[[ "$(shasum -a 256 "$UPPERCASE_ICON_APP/Contents/Resources/Upper.ICNS" | awk '{print $1}')" == "$ORIGINAL_SUM" ]] || {
  test_fail "Uppercase ICNS metadata did not restore its resolved target"
  exit 1
}

decoy_before="$(shasum -a 256 "$DECOY_BACKUP_APP/Contents/Resources/Main.icns" | awk '{print $1}')"
set +e
run_cli restore "$DECOY_BACKUP_APP"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Restore should reject a backup for a different icon target"; exit 1; }
[[ "$(shasum -a 256 "$DECOY_BACKUP_APP/Contents/Resources/Main.icns" | awk '{print $1}')" == "$decoy_before" ]] || {
  test_fail "A decoy backup changed the metadata-resolved icon"
  exit 1
}

for conservative_asset_app in "$CASE_ASSET_APP" "$SYMLINK_ASSET_APP" "$DIRECTORY_ASSET_APP"; do
  conservative_target="$conservative_asset_app/Contents/Resources/${conservative_asset_app##*/}"
  conservative_target="${conservative_target%.app}.icns"
  conservative_before="$(shasum -a 256 "$conservative_target" | awk '{print $1}')"
  set +e
  run_cli apply "$conservative_asset_app" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
  STATUS=$?
  set -e
  [[ "$STATUS" -eq 1 ]] || { test_fail "Every case and file type of .car should block internal apply"; exit 1; }
  assert_output "does not support asset-catalog"
  [[ "$(shasum -a 256 "$conservative_target" | awk '{print $1}')" == "$conservative_before" ]] || {
    test_fail "Rejected asset-catalog app was modified: $conservative_asset_app"
    exit 1
  }
done

info_target="$INFO_SYMLINK_APP/Contents/Resources/InfoSymlink.icns"
info_target_before="$(shasum -a 256 "$info_target" | awk '{print $1}')"
info_mtime_before="$(stat -f '%m' "$ABS_TEST_DIR/external-info.plist")"
set +e
ICONFORGE_TEST_TOUCH_BIN=/usr/bin/touch run_cli \
  apply "$INFO_SYMLINK_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "A symlinked Info.plist should block internal apply"; exit 1; }
assert_output "direct, non-symlink Contents/Info.plist"
[[ "$(shasum -a 256 "$info_target" | awk '{print $1}')" == "$info_target_before" ]] || {
  test_fail "A rejected Info.plist symlink changed the live icon"
  exit 1
}
[[ ! -e "$INFO_SYMLINK_APP/Contents/Resources/InfoSymlink_ugly.icns" ]] || {
  test_fail "A rejected Info.plist symlink created a backup"
  exit 1
}
[[ "$(stat -f '%m' "$ABS_TEST_DIR/external-info.plist")" == "$info_mtime_before" ]] || {
  test_fail "A rejected Info.plist symlink touched an external file"
  exit 1
}

cp "$ABS_TEST_DIR/original.icns" "$INFO_SYMLINK_APP/Contents/Resources/InfoSymlink_ugly.icns"
cp "$ABS_TEST_DIR/replacement.icns" "$info_target"
info_mtime_before="$(stat -f '%m' "$ABS_TEST_DIR/external-info.plist")"
set +e
ICONFORGE_TEST_TOUCH_BIN=/usr/bin/touch run_cli restore "$INFO_SYMLINK_APP"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "A symlinked Info.plist should block internal restore"; exit 1; }
assert_output "direct, non-symlink Contents/Info.plist"
[[ "$(shasum -a 256 "$info_target" | awk '{print $1}')" == "$REPLACEMENT_SUM" ]] || {
  test_fail "A rejected Info.plist symlink changed the live icon during restore"
  exit 1
}
[[ "$(stat -f '%m' "$ABS_TEST_DIR/external-info.plist")" == "$info_mtime_before" ]] || {
  test_fail "A rejected Info.plist symlink touched an external file during restore"
  exit 1
}

: >"$LOGS/force-present-failure"
present_fail_before="$(shasum -a 256 "$PRESENT_FAIL_APP/Contents/Resources/PresentFail.icns" | awk '{print $1}')"
set +e
run_cli restore "$PRESENT_FAIL_APP"
STATUS=$?
set -e
rm -f "$LOGS/force-present-failure"
[[ "$STATUS" -eq 1 ]] || { test_fail "A native presence probe failure should fail restore"; exit 1; }
assert_output "could not determine whether $PRESENT_FAIL_APP has a Finder custom icon (status 70)"
[[ "$(shasum -a 256 "$PRESENT_FAIL_APP/Contents/Resources/PresentFail.icns" | awk '{print $1}')" == "$present_fail_before" ]] || {
  test_fail "A failed native presence probe allowed internal mutation"
  exit 1
}

missing_codesign_target="$MISSING_CODESIGN_APP/Contents/Resources/MissingCodesign.icns"
missing_codesign_before="$(shasum -a 256 "$missing_codesign_target" | awk '{print $1}')"
set +e
ICONFORGE_TEST_CODESIGN_BIN="$ABS_TEST_DIR/missing-codesign" \
  run_cli apply "$MISSING_CODESIGN_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Missing codesign should fail internal apply preflight"; exit 1; }
assert_output "Missing required tool: codesign"
[[ "$(shasum -a 256 "$missing_codesign_target" | awk '{print $1}')" == "$missing_codesign_before" ]] || {
  test_fail "Missing codesign was detected after the internal icon changed"
  exit 1
}
[[ ! -e "$MISSING_CODESIGN_APP/Contents/Resources/MissingCodesign_ugly.icns" ]] || {
  test_fail "Missing codesign was detected after an internal backup was created"
  exit 1
}

set +e
run_cli apply "$SYMLINK_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Internal apply through a symlink should fail"; exit 1; }
[[ "$(shasum -a 256 "$ABS_TEST_DIR/external.icns" | awk '{print $1}')" == "$EXTERNAL_SUM" ]] || {
  test_fail "Rejected symlink target modified an external file"
  exit 1
}

set +e
run_cli restore "$SYMLINK_BACKUP_APP"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Restore through a symlink backup should fail"; exit 1; }
[[ "$(shasum -a 256 "$ABS_TEST_DIR/external.icns" | awk '{print $1}')" == "$EXTERNAL_SUM" ]] || {
  test_fail "Rejected symlink backup modified an external file"
  exit 1
}

malformed_target_before="$(shasum -a 256 "$MALFORMED_BACKUP_APP/Contents/Resources/Malformed.icns" | awk '{print $1}')"
set +e
run_cli restore "$MALFORMED_BACKUP_APP"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Restore should reject a malformed internal backup"; exit 1; }
[[ "$(shasum -a 256 "$MALFORMED_BACKUP_APP/Contents/Resources/Malformed.icns" | awk '{print $1}')" == "$malformed_target_before" ]] || {
  test_fail "Malformed backup changed the live icon"
  exit 1
}

ambiguous_target_before="$(shasum -a 256 "$AMBIGUOUS_BACKUP_APP/Contents/Resources/Ambiguous.icns" | awk '{print $1}')"
set +e
run_cli apply "$AMBIGUOUS_BACKUP_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Internal apply should reject multiple backups"; exit 1; }
[[ "$(shasum -a 256 "$AMBIGUOUS_BACKUP_APP/Contents/Resources/Ambiguous.icns" | awk '{print $1}')" == "$ambiguous_target_before" ]] || {
  test_fail "Ambiguous backup state changed the live icon"
  exit 1
}

rm -f "$LOGS/cp-count"
printf '2\n' >"$LOGS/cp-fail-at"
set +e
run_cli apply "$CP_BACKUP_FAIL_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
STATUS=$?
set -e
rm -f "$LOGS/cp-fail-at"
[[ "$STATUS" -eq 1 ]] || { test_fail "A partial persistent-backup copy should fail"; exit 1; }
[[ ! -e "$CP_BACKUP_FAIL_APP/Contents/Resources/BackupCopyFail_ugly.icns" ]] || {
  test_fail "A partial persistent-backup copy left a backup"
  exit 1
}
[[ "$(shasum -a 256 "$CP_BACKUP_FAIL_APP/Contents/Resources/BackupCopyFail.icns" | awk '{print $1}')" == "$ORIGINAL_SUM" ]] || {
  test_fail "A failed backup copy changed the live icon"
  exit 1
}

rm -f "$LOGS/cp-count"
printf '3\n' >"$LOGS/cp-fail-at"
replacement_fail_mode_before="$(stat -f '%Lp' "$CP_REPLACEMENT_FAIL_APP/Contents/Resources/ReplacementCopyFail.icns")"
set +e
run_cli apply "$CP_REPLACEMENT_FAIL_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
STATUS=$?
set -e
rm -f "$LOGS/cp-fail-at"
[[ "$STATUS" -eq 1 ]] || { test_fail "A partial replacement copy should fail"; exit 1; }
[[ ! -e "$CP_REPLACEMENT_FAIL_APP/Contents/Resources/ReplacementCopyFail_ugly.icns" ]] || {
  test_fail "A failed first replacement left a new persistent backup"
  exit 1
}
[[ "$(shasum -a 256 "$CP_REPLACEMENT_FAIL_APP/Contents/Resources/ReplacementCopyFail.icns" | awk '{print $1}')" == "$ORIGINAL_SUM" ]] || {
  test_fail "A partial replacement copy changed the live icon"
  exit 1
}
[[ "$(stat -f '%Lp' "$CP_REPLACEMENT_FAIL_APP/Contents/Resources/ReplacementCopyFail.icns")" == "$replacement_fail_mode_before" ]] || {
  test_fail "A failed replacement changed the live icon mode"
  exit 1
}

rm -f "$LOGS/cp-count"
printf '2\n' >"$LOGS/cp-fail-at"
restore_copy_before="$(shasum -a 256 "$RESTORE_COPY_FAIL_APP/Contents/Resources/RestoreCopyFail.icns" | awk '{print $1}')"
restore_mode_before="$(stat -f '%Lp' "$RESTORE_COPY_FAIL_APP/Contents/Resources/RestoreCopyFail.icns")"
set +e
run_cli restore "$RESTORE_COPY_FAIL_APP"
STATUS=$?
set -e
rm -f "$LOGS/cp-fail-at"
[[ "$STATUS" -eq 1 ]] || { test_fail "A partial restore copy should fail"; exit 1; }
[[ "$(shasum -a 256 "$RESTORE_COPY_FAIL_APP/Contents/Resources/RestoreCopyFail.icns" | awk '{print $1}')" == "$restore_copy_before" ]] || {
  test_fail "A partial restore copy did not retain the pre-restore icon"
  exit 1
}
[[ "$(stat -f '%Lp' "$RESTORE_COPY_FAIL_APP/Contents/Resources/RestoreCopyFail.icns")" == "$restore_mode_before" ]] || {
  test_fail "A failed restore changed the live icon mode"
  exit 1
}

mkdir -p "$ABS_TEST_DIR/signal-temp"
for signal_case in 'HUP 129' 'INT 130' 'TERM 143'; do
  read -r signal_name expected_status <<<"$signal_case"
  rm -f "$LOGS/cp-count" "$LOGS/signal-fired"
  printf '%s\n' "$signal_name" >"$LOGS/signal-on-rename"
  : >"$LOGS/codesign.log"
  set +e
  TMPDIR="$ABS_TEST_DIR/signal-temp" run_cli \
    apply "$SIGNAL_APPLY_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
  STATUS=$?
  set -e
  rm -f "$LOGS/signal-on-rename" "$LOGS/signal-fired"
  [[ "$STATUS" -eq "$expected_status" ]] || {
    test_fail "$signal_name during internal apply should return $expected_status (got $STATUS)"
    exit 1
  }
  [[ "$(shasum -a 256 "$SIGNAL_APPLY_APP/Contents/Resources/SignalApply.icns" | awk '{print $1}')" == "$ORIGINAL_SUM" ]] || {
    test_fail "$signal_name during internal apply did not restore the live icon"
    exit 1
  }
  [[ ! -e "$SIGNAL_APPLY_APP/Contents/Resources/SignalApply_ugly.icns" ]] || {
    test_fail "$signal_name during first internal apply left a persistent backup"
    exit 1
  }
  assert_log "$LOGS/codesign.log" "--verify --deep --strict --all-architectures $SIGNAL_APPLY_APP"
  if find "$ABS_TEST_DIR/signal-temp" -mindepth 1 -print -quit | grep -q .; then
    test_fail "$signal_name during internal apply left a rollback file"
    exit 1
  fi
done

rm -f "$LOGS/cp-count" "$LOGS/signal-fired"
printf 'TERM\n' >"$LOGS/signal-on-rename"
: >"$LOGS/codesign.log"
set +e
TMPDIR="$ABS_TEST_DIR/signal-temp" run_cli restore "$SIGNAL_RESTORE_APP"
STATUS=$?
set -e
rm -f "$LOGS/signal-on-rename" "$LOGS/signal-fired"
[[ "$STATUS" -eq 143 ]] || { test_fail "TERM during internal restore should return 143 (got $STATUS)"; exit 1; }
[[ "$(shasum -a 256 "$SIGNAL_RESTORE_APP/Contents/Resources/SignalRestore.icns" | awk '{print $1}')" == "$REPLACEMENT_SUM" ]] || {
  test_fail "TERM during internal restore did not put the pre-restore icon back"
  exit 1
}
[[ "$(shasum -a 256 "$SIGNAL_RESTORE_APP/Contents/Resources/SignalRestore_ugly.icns" | awk '{print $1}')" == "$ORIGINAL_SUM" ]] || {
  test_fail "TERM during internal restore changed the preserved backup"
  exit 1
}
assert_log "$LOGS/codesign.log" "--verify --deep --strict --all-architectures $SIGNAL_RESTORE_APP"
if find "$ABS_TEST_DIR/signal-temp" -mindepth 1 -print -quit | grep -q .; then
  test_fail "TERM during internal restore left a rollback file"
  exit 1
fi

run_cli apply "$NATIVE_APP" -i "$ABS_TEST_DIR/replacement.icns"
assert_output "Strategy: native"
assert_log "$LOGS/native.log" "set $NATIVE_APP $ABS_TEST_DIR/replacement.icns"
[[ ! -e "$NATIVE_APP/Contents/Resources/NativeIcon_ugly.icns" ]] || { test_fail "Native apply created an internal backup"; exit 1; }

rm -f "$LOGS/killall.log"
run_cli apply "$NATIVE_APP" -i "$ABS_TEST_DIR/replacement.icns" -n
assert_output "Nuke: complete"
[[ "$(wc -l <"$LOGS/killall.log" | tr -d ' ')" -eq 3 ]] || { test_fail "Direct -n did not run Nuke exactly once"; exit 1; }

ACCOUNT_HOME="$("$REAL_HELPER" user-home)"
printf -v EXPECTED_NUKE_TARGET '%q' "$ACCOUNT_HOME/Library/Caches/com.apple.iconservices.store"
HOME=/private/tmp/.. \
  ICONFORGE_TEST_LOG_DIR="$LOGS" \
  ICONFORGE_REAL_HELPER="$REAL_HELPER" \
  ICONFORGE_NATIVE_ICON="$FAKE_BIN/native-helper" \
  ICONFORGE_KILLALL_BIN="$FAKE_BIN/killall" \
  ICONFORGE_RM_BIN="$FAKE_BIN/rm" \
  "$BIN" nuke -d >"$OUTPUT" 2>&1
assert_output "$EXPECTED_NUKE_TARGET"
if grep -F '/private/tmp/../Library/Caches' "$OUTPUT" >/dev/null; then
  test_fail "A poisoned HOME redirected Nuke cache targets"
  exit 1
fi

run_cli restore "$NATIVE_APP"
assert_output "Removed Finder custom icon"
assert_log "$LOGS/native.log" "remove $NATIVE_APP"

(
  cd "$ABS_TEST_DIR"
  run_cli apply -i "$ABS_TEST_DIR/replacement.icns" -- -Leading.app
)
assert_log "$LOGS/native.log" "set $LEADING_APP $ABS_TEST_DIR/replacement.icns"

run_cli apply "$INTERNAL_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
assert_output "Strategy: internal-icns"
assert_output "Ad hoc re-signed"
[[ "$(shasum -a 256 "$INTERNAL_APP/Contents/Resources/InternalIcon.icns" | awk '{print $1}')" == "$REPLACEMENT_SUM" ]] || { test_fail "Internal replacement did not land"; exit 1; }
[[ "$(shasum -a 256 "$INTERNAL_APP/Contents/Resources/InternalIcon_ugly.icns" | awk '{print $1}')" == "$ORIGINAL_SUM" ]] || { test_fail "First original backup was not preserved"; exit 1; }
assert_log "$LOGS/codesign.log" "--verify --deep --strict --all-architectures $INTERNAL_APP"

run_cli restore "$INTERNAL_APP"
assert_output "Restored internal icon"
[[ "$(shasum -a 256 "$INTERNAL_APP/Contents/Resources/InternalIcon.icns" | awk '{print $1}')" == "$ORIGINAL_SUM" ]] || { test_fail "Internal restore did not recover the original"; exit 1; }

chmod 444 "$INTERNAL_APP/Contents/Resources/InternalIcon_ugly.icns"
run_cli apply "$INTERNAL_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
run_cli restore "$INTERNAL_APP"
[[ "$(shasum -a 256 "$INTERNAL_APP/Contents/Resources/InternalIcon.icns" | awk '{print $1}')" == "$ORIGINAL_SUM" ]] || {
  test_fail "A read-only preserved backup could not be used safely"
  exit 1
}

set +e
run_cli apply "$ASSET_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Asset-catalog internal apply should be operational failure"; exit 1; }
assert_output "does not support asset-catalog"
[[ ! -e "$ASSET_APP/Contents/Resources/AssetIcon_ugly.icns" ]] || { test_fail "Rejected asset app was modified"; exit 1; }

run_cli apply "$VERIFY_FAIL_APP" -i "$ABS_TEST_DIR/replacement.icns" -s internal-icns
VERIFY_BEFORE="$(shasum -a 256 "$VERIFY_FAIL_APP/Contents/Resources/VerifyIcon.icns" | awk '{print $1}')"
: >"$LOGS/force-verify-failure"
set +e
run_cli apply "$VERIFY_FAIL_APP" -i "$ABS_TEST_DIR/original.icns" -s internal-icns
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Signature verification failure should fail"; exit 1; }
[[ "$(shasum -a 256 "$VERIFY_FAIL_APP/Contents/Resources/VerifyIcon.icns" | awk '{print $1}')" == "$VERIFY_BEFORE" ]] || { test_fail "Failed second internal apply did not restore the immediately previous icon"; exit 1; }
assert_output "Rollback could not be fully verified"

set +e
run_cli restore "$VERIFY_FAIL_APP"
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Restore verification failure should fail"; exit 1; }
[[ "$(shasum -a 256 "$VERIFY_FAIL_APP/Contents/Resources/VerifyIcon.icns" | awk '{print $1}')" == "$VERIFY_BEFORE" ]] || {
  test_fail "Failed internal restore did not put the pre-restore icon back"
  exit 1
}
[[ "$(shasum -a 256 "$VERIFY_FAIL_APP/Contents/Resources/VerifyIcon_ugly.icns" | awk '{print $1}')" == "$ORIGINAL_SUM" ]] || {
  test_fail "Failed internal restore changed the preserved original backup"
  exit 1
}
assert_output "Rollback could not be fully verified"
rm -f "$LOGS/force-verify-failure"

rm -f "$LOGS/native-Native.app"
run_cli apply "$NATIVE_APP" -i "$ABS_TEST_DIR/replacement.icns" -d
assert_output "Planned Finder custom icon target"
[[ ! -e "$LOGS/native-Native.app" ]] || { test_fail "Dry-run set a native icon"; exit 1; }

for removed in auto legacy-native-alias; do
  set +e
  run_cli apply "$NATIVE_APP" -i "$ABS_TEST_DIR/replacement.icns" -s "$removed"
  STATUS=$?
  set -e
  [[ "$STATUS" -eq 2 ]] || { test_fail "Removed strategy '$removed' should be usage error"; exit 1; }
done
for removed_flag in -f -S -c --force-asset --no-resign --refresh-caches; do
  set +e
  run_cli apply "$NATIVE_APP" -i "$ABS_TEST_DIR/replacement.icns" "$removed_flag"
  STATUS=$?
  set -e
  [[ "$STATUS" -eq 2 ]] || { test_fail "Removed flag '$removed_flag' should be usage error"; exit 1; }
done

set +e
HOME="$HOME_DIR" ICONFORGE_NATIVE_ICON="$ABS_TEST_DIR/missing-helper" "$BIN" apply "$NATIVE_APP" -i "$ABS_TEST_DIR/replacement.icns" >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Missing native helper must fail closed"; exit 1; }
assert_output "Bundled native icon helper not found"

printf 'icnsjunk' >"$ABS_TEST_DIR/magic-only.icns"
internal_before="$(shasum -a 256 "$INTERNAL_APP/Contents/Resources/InternalIcon.icns" | awk '{print $1}')"
set +e
HOME="$HOME_DIR" ICONFORGE_NATIVE_ICON="$ABS_TEST_DIR/missing-helper" \
  "$BIN" apply "$INTERNAL_APP" -i "$ABS_TEST_DIR/magic-only.icns" -s internal-icns >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Internal apply without the validator must fail closed"; exit 1; }
assert_output "Bundled native icon helper not found"
[[ "$(shasum -a 256 "$INTERNAL_APP/Contents/Resources/InternalIcon.icns" | awk '{print $1}')" == "$internal_before" ]] || {
  test_fail "Missing-validator internal apply modified its target"
  exit 1
}

trap_exit_marker="$ABS_TEST_DIR/restored-exit-trap"
(
  # This is a separate sourced-code probe; it does not consume the earlier subshell's assignment.
  # shellcheck disable=SC2031
  export ICONFORGE_ROOT="$PWD"
  source "$PWD/lib/iconforge/common.sh"
  source "$PWD/lib/iconforge/strategy-internal-icns.sh"
  APP_PATH="$SIGNAL_APPLY_APP"
  APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
  APP_RESOURCES_DIR="$APP_PATH/Contents/Resources"
  APP_ICON_TARGET="$APP_RESOURCES_DIR/SignalApply.icns"
  APP_ICON_BACKUP="$APP_RESOURCES_DIR/SignalApply_ugly.icns"
  rollback_probe="$ABS_TEST_DIR/trap-rollback.icns"
  cp "$APP_ICON_TARGET" "$rollback_probe"

  trap ': >"$trap_exit_marker"' EXIT
  trap ':' HUP
  trap ':' INT
  trap ':' TERM
  saved_exit="$(trap -p EXIT)"
  saved_hup="$(trap -p HUP)"
  saved_int="$(trap -p INT)"
  saved_term="$(trap -p TERM)"

  internal_transaction_begin apply "$rollback_probe"
  internal_transaction_finish
  [[ "$(trap -p EXIT)" == "$saved_exit" ]]
  [[ "$(trap -p HUP)" == "$saved_hup" ]]
  [[ "$(trap -p INT)" == "$saved_int" ]]
  [[ "$(trap -p TERM)" == "$saved_term" ]]
)
[[ -f "$trap_exit_marker" ]] || { test_fail "Internal transaction did not restore the prior EXIT trap"; exit 1; }

test_pass "$TEST_NAME passed"
