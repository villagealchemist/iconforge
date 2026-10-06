#!/usr/bin/env bash
set -euo pipefail
TEST_NAME="safe directory configuration"
# shellcheck source=tests/test-common.sh
source tests/test-common.sh
unset XDG_CONFIG_HOME || true
BIN="$PWD/iconforge.sh"
BASE="$PWD/$TEST_DIR"
FAKE_HOME="$BASE/home"
WORK="$BASE/work"
CONFIG_FILE="$FAKE_HOME/.config/iconforge/config.plist"
OUTPUT="$BASE/output.log"
MARKER="$BASE/sourced-marker"
mkdir -p "$FAKE_HOME/.config/iconforge" "$WORK" "$BASE/explicit" "$BASE/empty"
export HOME="$FAKE_HOME"

assert_status() {
  local expected="$1" actual=0; shift
  "$@" >"$OUTPUT" 2>&1 || actual=$?
  [[ "$actual" -eq "$expected" ]] || { test_fail "Expected $expected, got $actual: $*"; cat "$OUTPUT"; exit 1; }
}
contains() { grep -F -- "$1" "$OUTPUT" >/dev/null || { test_fail "Missing diagnostic: $1"; cat "$OUTPUT"; exit 1; }; }
new_plist() { /usr/bin/plutil -create xml1 "$CONFIG_FILE"; }

# Old executable preferences and obsolete keys are never loaded.
printf 'touch %q\n' "$MARKER" > "$FAKE_HOME/.iconforgerc"
new_plist
/usr/bin/plutil -insert icon_root -string /poison "$CONFIG_FILE"
mkdir -p "$BASE/runtime"
cp VERSION "$BASE/runtime/VERSION"
for name in .iconforge.env .iconforge.local.env; do printf 'touch %q\n' "$MARKER" > "$BASE/runtime/$name"; done
HOME="$FAKE_HOME" ICONFORGE_ROOT="$BASE/runtime" ICONFORGE_ICON_ROOT=/poison \
  bash -c 'source "$1"; printf "%s\n" "$ICONFORGE_DRY_RUN"' _ "$PWD/lib/iconforge/common.sh" > "$OUTPUT"
[[ "$(cat "$OUTPUT")" == false && ! -e "$MARKER" ]]
(
  cd "$WORK"
  ICONFORGE_ICON_ROOT=/poison CUSTOM_OUTPUT=/poison KEEP_PNG=true RECURSIVE=true SUPPRESS_WARNINGS=true \
    "$BIN" "$BASE/../i-just-wanna-be-an-icon.png" --dry-run > "$OUTPUT"
)
! grep -F /poison "$OUTPUT"
contains "$WORK/i-just-wanna-be-an-icon.icns"
assert_status 2 "$BIN" apply --all
contains 'the-hearth'

# Relative values bind to configuration-time cwd. Future unknown keys survive.
(
  cd "$WORK"
  "$BIN" config set default-directory 'saved icons/Ünicode' >/dev/null
)
EXPECTED="$WORK/saved icons/Ünicode"
[[ "$("$BIN" config get default-directory)" == "$EXPECTED" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :default_directory' "$CONFIG_FILE")" == "$EXPECTED" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :icon_root' "$CONFIG_FILE")" == /poison ]]
[[ "$(/usr/bin/stat -f '%Lp' "$CONFIG_FILE")" == 600 ]]
mkdir -p "$BASE/physical/real" "$BASE/physical/icons" "$BASE/logical"
ln -s "$BASE/physical/real" "$BASE/logical/link"
"$BIN" config set default-directory "$BASE/logical/link/../icons" >/dev/null
[[ "$("$BIN" config get default-directory)" == "$BASE/physical/icons" ]]
"$BIN" config set default-directory "$EXPECTED" >/dev/null
assert_status 0 "$BIN" forge "$TEST_IMAGE1" --dry-run
contains "$EXPECTED/i-just-wanna-be-an-icon.icns"
"$BIN" config unset default-directory > "$OUTPUT"
contains 'Default icon directory unset'
assert_status 1 "$BIN" config get default-directory
"$BIN" config unset default-directory > "$OUTPUT"
contains 'Default icon directory is not set'

# A corrupt preference does not affect explicit paths or --version. Unlike the
# old single-key setter, set may not erase an unreadable multi-key document.
printf 'not a property list\n' > "$CONFIG_FILE"
assert_status 1 "$BIN" forge "$TEST_IMAGE1" --dry-run
contains 'configuration is not a valid property list'
assert_status 0 "$BIN" forge "$TEST_IMAGE1" --dry-run --output "$BASE/explicit"
contains "$BASE/explicit/i-just-wanna-be-an-icon.icns"
assert_status 1 "$BIN" apply --all "$BASE/empty" --dry-run
contains 'No eligible .icns files found'
[[ "$("$BIN" --version)" == "iconforge v$(tr -d '[:space:]' < VERSION)" ]]
assert_status 1 "$BIN" config set default-directory "$EXPECTED"
[[ "$(cat "$CONFIG_FILE")" == 'not a property list' ]]
rm "$CONFIG_FILE"
"$BIN" config set default-directory "$EXPECTED" >/dev/null

# Known keys must contain one absolute, single-line string, not path-shaped data.
for type in array data; do
  new_plist
  if [[ "$type" == array ]]; then
    /usr/bin/plutil -insert default_directory -array "$CONFIG_FILE"
  else
    /usr/bin/plutil -insert default_directory -data L3RtcC9pY29ucw== "$CONFIG_FILE"
  fi
  assert_status 1 "$BIN" config get default-directory
  contains 'must be a string'
done
new_plist
/usr/bin/plutil -insert default_directory -string "$EXPECTED"$'\n' "$CONFIG_FILE"
assert_status 1 "$BIN" config get default-directory
contains 'must be a single-line string'
printf '<plist version="1.0"><array/></plist>\n' > "$CONFIG_FILE"
assert_status 1 "$BIN" forge "$TEST_IMAGE1" --dry-run
contains 'configuration root must be a dictionary'
assert_status 1 "$BIN" config set default-directory /
: > "$BASE/not-a-directory"
assert_status 1 "$BIN" config set default-directory "$BASE/not-a-directory/child"
contains 'ancestor is not a directory'
ln -s "$BASE/missing" "$BASE/dangling"
assert_status 1 "$BIN" config set default-directory "$BASE/dangling"
contains 'contains a dangling symlink'
ln -s / "$BASE/root-link"
new_plist
/usr/bin/plutil -insert default_directory -string "$BASE/root-link" "$CONFIG_FILE"
assert_status 1 "$BIN" apply --all --dry-run
contains 'resolves to the filesystem root'

# None of get/set/unset may follow a symlinked preference file.
mv "$CONFIG_FILE" "$BASE/target.plist"
CHECKSUM="$(shasum -a 256 "$BASE/target.plist")"
ln -s "$BASE/target.plist" "$CONFIG_FILE"
assert_status 1 "$BIN" config get default-directory
contains 'configuration must not be a symlink'
assert_status 1 "$BIN" config set default-directory "$EXPECTED"
contains 'configuration must not be a symlink'
assert_status 1 "$BIN" config unset default-directory
contains 'configuration must not be a symlink'
[[ "$(shasum -a 256 "$BASE/target.plist")" == "$CHECKSUM" ]]

export XDG_CONFIG_HOME="$BASE/xdg"
"$BIN" config set the-hearth "$EXPECTED" >/dev/null
[[ -f "$XDG_CONFIG_HOME/iconforge/config.plist" ]]
[[ "$("$BIN" config get the-hearth)" == "$EXPECTED" ]]
XDG_CONFIG_HOME=relative assert_status 1 "$BIN" config get the-hearth
contains 'XDG_CONFIG_HOME must be an absolute path'
export XDG_CONFIG_HOME="$BASE/nonregular"
mkdir -p "$XDG_CONFIG_HOME/iconforge/config.plist"
assert_status 1 "$BIN" config get default-directory
contains 'configuration is not a regular file'
assert_status 1 "$BIN" config set default-directory "$EXPECTED"
contains 'configuration is not a regular file'
assert_status 1 "$BIN" config unset default-directory
contains 'configuration is not a regular file'

test_pass "$TEST_NAME passed"
