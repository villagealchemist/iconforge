#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="safe default-directory configuration"
source tests/test-common.sh
unset XDG_CONFIG_HOME || true

BIN="$PWD/iconforge.sh"
EXPECTED_VERSION="$(tr -d '[:space:]' < VERSION)"
RUNTIME_ROOT="$PWD/$TEST_DIR/runtime"
FAKE_HOME="$PWD/$TEST_DIR/home"
WORK_ROOT="$PWD/$TEST_DIR/work"
MARKER="$PWD/$TEST_DIR/sourced-marker"
OUTPUT="$PWD/$TEST_DIR/output.log"
CONFIG_FILE="$FAKE_HOME/.config/iconforge/config.plist"
EXPLICIT_OUTPUT="$PWD/$TEST_DIR/explicit-output"
EMPTY_EXPLICIT_BULK="$PWD/$TEST_DIR/empty-explicit-bulk"
mkdir -p "$RUNTIME_ROOT" "$FAKE_HOME/.config/iconforge" "$WORK_ROOT" "$EXPLICIT_OUTPUT" "$EMPTY_EXPLICIT_BULK"
cp VERSION "$RUNTIME_ROOT/VERSION"

for legacy_file in "$RUNTIME_ROOT/.iconforge.env" "$RUNTIME_ROOT/.iconforge.local.env" "$FAKE_HOME/.iconforgerc"; do
  printf 'touch %q\n' "$MARKER" >"$legacy_file"
done
/usr/bin/plutil -create xml1 "$CONFIG_FILE"
/usr/bin/plutil -insert icon_root -string /poison "$CONFIG_FILE"

HOME="$FAKE_HOME" ICONFORGE_ROOT="$RUNTIME_ROOT" ICONFORGE_ICON_ROOT="/poison" \
bash -c 'source "$1"; printf "%s\n" "$ICONFORGE_DRY_RUN"' \
  _ "$PWD/lib/iconforge/common.sh" >"$OUTPUT"

[[ ! -e "$MARKER" ]] || { test_fail "A legacy shell config was sourced"; exit 1; }
[[ "$(cat "$OUTPUT")" == "false" ]] || { test_fail "Runtime dry-run state was not reset"; exit 1; }

(
  cd "$WORK_ROOT"
  HOME="$FAKE_HOME" CUSTOM_OUTPUT="/poison" KEEP_PNG=true RECURSIVE=true SUPPRESS_WARNINGS=true \
    "$BIN" "$PWD/../../i-just-wanna-be-an-icon.png" -d >"$OUTPUT"
)
! grep -F "/poison" "$OUTPUT" >/dev/null || { test_fail "Forge inherited a legacy output default"; exit 1; }
grep -F "$WORK_ROOT/i-just-wanna-be-an-icon.icns" "$OUTPUT" >/dev/null || {
  test_fail "An obsolete plist key displaced the current-directory fallback"
  exit 1
}

HOME="$FAKE_HOME" ICONFORGE_ICON_ROOT="$PWD/$TEST_DIR/icons" "$BIN" -v >"$OUTPUT"
[[ "$(cat "$OUTPUT")" == "iconforge v$EXPECTED_VERSION" ]] || { test_fail "Legacy state affected root version"; exit 1; }

set +e
HOME="$FAKE_HOME" ICONFORGE_ICON_ROOT="$PWD/$TEST_DIR/icons" "$BIN" apply -a >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 2 ]] || { test_fail "Bare --all should still fail without the new default"; exit 1; }
grep -F -- "--all requires an icon directory or a configured default-directory" "$OUTPUT" >/dev/null || {
  test_fail "Missing default-directory guidance"
  exit 1
}

DEFAULT_RELATIVE="saved icons/Ünicode"
(
  cd "$WORK_ROOT"
  HOME="$FAKE_HOME" "$BIN" config set default-directory "$DEFAULT_RELATIVE" >"$OUTPUT"
)
EXPECTED_DEFAULT="$WORK_ROOT/$DEFAULT_RELATIVE"
[[ "$(HOME="$FAKE_HOME" "$BIN" config get default-directory)" == "$EXPECTED_DEFAULT" ]] || {
  test_fail "Config get did not return the canonical absolute default"
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :default_directory' "$CONFIG_FILE")" == "$EXPECTED_DEFAULT" ]] || {
  test_fail "The plist did not contain the configured directory"
  exit 1
}
[[ "$(/usr/bin/stat -f '%Lp' "$CONFIG_FILE")" == 600 ]] || {
  test_fail "The configuration file was not private"
  exit 1
}

SYMLINK_CASE="$PWD/$TEST_DIR/symlink-case"
mkdir -p "$SYMLINK_CASE/physical/real" "$SYMLINK_CASE/physical/icons" "$SYMLINK_CASE/logical"
ln -s "$SYMLINK_CASE/physical/real" "$SYMLINK_CASE/logical/link"
HOME="$FAKE_HOME" "$BIN" config set default-directory "$SYMLINK_CASE/logical/link/../icons" >/dev/null
[[ "$(HOME="$FAKE_HOME" "$BIN" config get default-directory)" == "$SYMLINK_CASE/physical/icons" ]] || {
  test_fail "Config collapsed parent traversal before resolving a symlink"
  exit 1
}
HOME="$FAKE_HOME" "$BIN" config set default-directory "$EXPECTED_DEFAULT" >/dev/null

(
  cd "$PWD/$TEST_DIR"
  HOME="$FAKE_HOME" "$BIN" forge "$PWD/../i-just-wanna-be-an-icon.png" -d >"$OUTPUT"
)
grep -F "$EXPECTED_DEFAULT/i-just-wanna-be-an-icon.icns" "$OUTPUT" >/dev/null || {
  test_fail "Forge did not use the configured default across working directories"
  exit 1
}

HOME="$FAKE_HOME" "$BIN" config unset default-directory >"$OUTPUT"
grep -Fx "Default icon directory unset" "$OUTPUT" >/dev/null || { test_fail "Unset did not report success"; exit 1; }
set +e
HOME="$FAKE_HOME" "$BIN" config get default-directory >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Get should return status 1 when unset"; exit 1; }
! grep -q '^/' "$OUTPUT" || { test_fail "Unset get unexpectedly printed a path"; exit 1; }
HOME="$FAKE_HOME" "$BIN" config unset default-directory >"$OUTPUT"
grep -Fx "Default icon directory is not set" "$OUTPUT" >/dev/null || { test_fail "Unset was not idempotent"; exit 1; }

printf 'not a property list\n' >"$CONFIG_FILE"
set +e
HOME="$FAKE_HOME" "$BIN" forge "$TEST_IMAGE1" -d >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Forge accepted malformed configuration"; exit 1; }
grep -F "configuration is not a valid property list" "$OUTPUT" >/dev/null || {
  test_fail "Malformed configuration error was unclear"
  exit 1
}
HOME="$FAKE_HOME" "$BIN" forge "$TEST_IMAGE1" -d -o "$EXPLICIT_OUTPUT" >"$OUTPUT"
grep -F "$EXPLICIT_OUTPUT/i-just-wanna-be-an-icon.icns" "$OUTPUT" >/dev/null || {
  test_fail "Explicit output did not bypass an irrelevant malformed default"
  exit 1
}
set +e
HOME="$FAKE_HOME" "$BIN" apply --all "$EMPTY_EXPLICIT_BULK" --dry-run >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Explicit bulk directory did not complete its own empty-library preflight"; exit 1; }
grep -F "No eligible .icns files found under: $EMPTY_EXPLICIT_BULK" "$OUTPUT" >/dev/null || {
  test_fail "Explicit bulk directory did not bypass an irrelevant malformed default"
  exit 1
}
! grep -F "configuration is not a valid property list" "$OUTPUT" >/dev/null || {
  test_fail "Explicit bulk directory loaded an irrelevant malformed default"
  exit 1
}
[[ "$(HOME="$FAKE_HOME" "$BIN" --version)" == "iconforge v$EXPECTED_VERSION" ]] || {
  test_fail "Version read configuration eagerly"
  exit 1
}

HOME="$FAKE_HOME" "$BIN" config set default-directory "$EXPECTED_DEFAULT" >/dev/null
/usr/bin/plutil -remove default_directory "$CONFIG_FILE"
/usr/bin/plutil -insert default_directory -array "$CONFIG_FILE"
set +e
HOME="$FAKE_HOME" "$BIN" config get default-directory >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Config accepted a non-string default_directory"; exit 1; }
grep -F "must be a string" "$OUTPUT" >/dev/null || { test_fail "Wrong-type configuration error was unclear"; exit 1; }

/usr/bin/plutil -create xml1 "$CONFIG_FILE"
/usr/bin/plutil -insert default_directory -data L3RtcC9pY29ucw== "$CONFIG_FILE"
set +e
HOME="$FAKE_HOME" "$BIN" config get default-directory >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Config accepted path-shaped data as a string"; exit 1; }
grep -F "must be a string" "$OUTPUT" >/dev/null || { test_fail "Data-type configuration error was unclear"; exit 1; }

/usr/bin/plutil -create xml1 "$CONFIG_FILE"
/usr/bin/plutil -insert default_directory -string "$EXPECTED_DEFAULT"$'\n' "$CONFIG_FILE"
set +e
HOME="$FAKE_HOME" "$BIN" config get default-directory >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Config discarded and accepted a trailing newline"; exit 1; }
grep -F "must be a single-line string" "$OUTPUT" >/dev/null || {
  test_fail "Multiline configuration error was unclear"
  exit 1
}

printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0"><array/></plist>' >"$CONFIG_FILE"
set +e
HOME="$FAKE_HOME" "$BIN" forge "$TEST_IMAGE1" -d >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Forge treated a non-dictionary config root as unset"; exit 1; }
grep -F "configuration root must be a dictionary" "$OUTPUT" >/dev/null || {
  test_fail "Non-dictionary configuration error was unclear"
  exit 1
}

set +e
HOME="$FAKE_HOME" "$BIN" config set default-directory / >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Config accepted the filesystem root as a default"; exit 1; }

NOT_A_DIRECTORY="$PWD/$TEST_DIR/not-a-directory"
: >"$NOT_A_DIRECTORY"
set +e
HOME="$FAKE_HOME" "$BIN" config set default-directory "$NOT_A_DIRECTORY/child" >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Config accepted a path below a non-directory ancestor"; exit 1; }
grep -F "ancestor is not a directory" "$OUTPUT" >/dev/null || {
  test_fail "Non-directory ancestor error was unclear"
  exit 1
}

DANGLING_LINK="$PWD/$TEST_DIR/dangling-link"
ln -s "$PWD/$TEST_DIR/missing-link-target" "$DANGLING_LINK"
set +e
HOME="$FAKE_HOME" "$BIN" config set default-directory "$DANGLING_LINK" >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Config accepted a dangling default-directory symlink"; exit 1; }
grep -F "contains a dangling symlink" "$OUTPUT" >/dev/null || {
  test_fail "Dangling-symlink error was unclear"
  exit 1
}

ROOT_LINK="$PWD/$TEST_DIR/root-link"
ln -s / "$ROOT_LINK"
/usr/bin/plutil -create xml1 "$CONFIG_FILE"
/usr/bin/plutil -insert default_directory -string "$ROOT_LINK" "$CONFIG_FILE"
set +e
HOME="$FAKE_HOME" "$BIN" apply --all --dry-run >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Bulk apply accepted a configured symlink to the filesystem root"; exit 1; }
grep -F "resolves to the filesystem root" "$OUTPUT" >/dev/null || {
  test_fail "Effective-root configuration error was unclear"
  exit 1
}

CONFIG_TARGET="$PWD/$TEST_DIR/config-target.plist"
mv "$CONFIG_FILE" "$CONFIG_TARGET"
CONFIG_TARGET_CHECKSUM="$(shasum -a 256 "$CONFIG_TARGET" | awk '{print $1}')"
ln -s "$CONFIG_TARGET" "$CONFIG_FILE"

assert_symlinked_config_rejected() {
  local action_label="$1"
  shift
  set +e
  HOME="$FAKE_HOME" "$BIN" config "$@" >"$OUTPUT" 2>&1
  STATUS=$?
  set -e
  [[ "$STATUS" -eq 1 ]] || { test_fail "Config action accepted a symlinked configuration file: $action_label"; exit 1; }
  grep -F "configuration must not be a symlink" "$OUTPUT" >/dev/null || {
    test_fail "Symlinked configuration error was unclear for: $action_label"
    exit 1
  }
}

assert_symlinked_config_rejected "get" get default-directory
assert_symlinked_config_rejected "set" set default-directory "$EXPECTED_DEFAULT"
assert_symlinked_config_rejected "unset" unset default-directory
[[ "$(shasum -a 256 "$CONFIG_TARGET" | awk '{print $1}')" == "$CONFIG_TARGET_CHECKSUM" ]] || {
  test_fail "A rejected config action modified the symlink target"
  exit 1
}

ABS_XDG_HOME="$PWD/$TEST_DIR/xdg-config-home"
XDG_CONFIG_HOME="$ABS_XDG_HOME" HOME="$FAKE_HOME" \
  "$BIN" config set default-directory "$EXPECTED_DEFAULT" >/dev/null
[[ "$(XDG_CONFIG_HOME="$ABS_XDG_HOME" HOME="$FAKE_HOME" "$BIN" config get default-directory)" == "$EXPECTED_DEFAULT" ]] || {
  test_fail "An absolute XDG_CONFIG_HOME did not select its own configuration"
  exit 1
}
[[ -f "$ABS_XDG_HOME/iconforge/config.plist" ]] || {
  test_fail "The XDG configuration was not written below XDG_CONFIG_HOME"
  exit 1
}

set +e
XDG_CONFIG_HOME="relative-config-home" HOME="$FAKE_HOME" \
  "$BIN" config get default-directory >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 1 ]] || { test_fail "Config accepted a relative XDG_CONFIG_HOME"; exit 1; }
grep -F "XDG_CONFIG_HOME must be an absolute path" "$OUTPUT" >/dev/null || {
  test_fail "Relative XDG_CONFIG_HOME error was unclear"
  exit 1
}

NONREGULAR_XDG_HOME="$PWD/$TEST_DIR/nonregular-xdg-home"
mkdir -p "$NONREGULAR_XDG_HOME/iconforge/config.plist"
assert_nonregular_config_rejected() {
  local action_label="$1"
  shift
  set +e
  XDG_CONFIG_HOME="$NONREGULAR_XDG_HOME" HOME="$FAKE_HOME" \
    "$BIN" config "$@" >"$OUTPUT" 2>&1
  STATUS=$?
  set -e
  [[ "$STATUS" -eq 1 ]] || { test_fail "Config action accepted a nonregular configuration file: $action_label"; exit 1; }
  grep -F "configuration is not a regular file" "$OUTPUT" >/dev/null || {
    test_fail "Nonregular configuration error was unclear for: $action_label"
    exit 1
  }
}

assert_nonregular_config_rejected "get" get default-directory
assert_nonregular_config_rejected "set" set default-directory "$EXPECTED_DEFAULT"
assert_nonregular_config_rejected "unset" unset default-directory

test_pass "$TEST_NAME passed"
