#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="complete CLI parser table"
source tests/test-common.sh

BIN="$PWD/iconforge.sh"
ABS_TEST_DIR="$PWD/$TEST_DIR"
OUTPUT="$ABS_TEST_DIR/output.log"
INPUT="$ABS_TEST_DIR/parser-input.png"
RECURSIVE_INPUT="$ABS_TEST_DIR/recursive-input"
FORGE_OUTPUT="$ABS_TEST_DIR/forge-output"
APP_ROOT="$ABS_TEST_DIR/apps"
EMPTY_ROOT="$ABS_TEST_DIR/empty"
APP="$APP_ROOT/Parser Fixture.app"
ICON="$ABS_TEST_DIR/parser.icns"
ICON_LIBRARY="$ABS_TEST_DIR/parser-icons"

mkdir -p "$RECURSIVE_INPUT" "$FORGE_OUTPUT" "$APP/Contents/Resources" \
  "$EMPTY_ROOT" "$ICON_LIBRARY" "$ABS_TEST_DIR/home"
cp "$TEST_IMAGE1" "$INPUT"
cp "$TEST_IMAGE1" "$RECURSIVE_INPUT/nested.png"
make_test_icns "$TEST_IMAGE1" "$ICON"
cp "$ICON" "$APP/Contents/Resources/ParserIcon.icns"
cp "$ICON" "$ICON_LIBRARY/Parser Fixture.icns"
plutil -create xml1 "$APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.example.iconforge.parser "$APP/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "Parser Fixture" "$APP/Contents/Info.plist"
plutil -insert CFBundleName -string "Parser Fixture" "$APP/Contents/Info.plist"
plutil -insert CFBundleIconFile -string ParserIcon "$APP/Contents/Info.plist"

export HOME="$ABS_TEST_DIR/home"
export ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR="$APP_ROOT"
export ICONFORGE_TEST_USER_APPLICATIONS_DIR="$EMPTY_ROOT"
export ICONFORGE_TEST_APPLICATIONS_DIR="$EMPTY_ROOT"
export ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR="$EMPTY_ROOT"

assert_status() {
  local expected="$1"
  shift
  set +e
  "$BIN" "$@" >"$OUTPUT" 2>&1
  local actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    cat "$OUTPUT"
    test_fail "Expected status $expected from: iconforge $*; got $actual"
    exit 1
  fi
}

assert_recognized() {
  set +e
  "$BIN" "$@" >"$OUTPUT" 2>&1
  local actual=$?
  set -e
  if [[ "$actual" -eq 2 ]]; then
    cat "$OUTPUT"
    test_fail "Parser rejected a documented spelling: iconforge $*"
    exit 1
  fi
}

# Root options and the contextual meaning of -v.
for flag in -h --help; do
  assert_status 0 "$flag"
  assert_status 0 help "$flag"
done
for flag in -v --version; do
  assert_status 0 "$flag"
  grep -Fx "iconforge v2.0.0" "$OUTPUT" >/dev/null || {
    test_fail "Root $flag did not print only the version"
    exit 1
  }
done
assert_status 0 apply -v "$APP" -i "$ICON" -d
grep -F "Strategy: native" "$OUTPUT" >/dev/null || {
  test_fail "apply -v did not remain in apply/verbose context"
  exit 1
}
if grep -Fx "iconforge v2.0.0" "$OUTPUT" >/dev/null; then
  test_fail "apply -v was interpreted as the root version flag"
  exit 1
fi

# Forge: every short and long spelling.
for flag in -o --output; do
  assert_status 0 forge "$INPUT" "$flag" "$FORGE_OUTPUT" -d
done
for flag in -k --keep-png; do
  assert_status 0 forge "$INPUT" "$flag" -d -o "$FORGE_OUTPUT"
done
for flag in -r --recursive; do
  assert_status 0 forge "$RECURSIVE_INPUT" "$flag" -d -o "$FORGE_OUTPUT"
done
for flag in -f --force; do
  assert_status 0 forge "$INPUT" "$flag" -d -o "$FORGE_OUTPUT"
done
for flag in -d --dry-run; do
  assert_status 0 forge "$INPUT" "$flag" -o "$FORGE_OUTPUT"
done
for flag in -h --help; do
  assert_status 0 forge "$flag"
done

# Inspect: both help spellings and a valid operand.
assert_status 0 inspect "$APP"
for flag in -h --help; do
  assert_status 0 inspect "$flag"
done

# Apply: every public spelling, including direct and bulk selectors.
for flag in -i --icon; do
  assert_status 0 apply "$APP" "$flag" "$ICON" -d
done
for flag in -s --strategy; do
  assert_status 0 apply "$APP" -i "$ICON" "$flag" native -d
done
for flag in -a --all; do
  assert_status 0 apply "$flag" "$ICON_LIBRARY" -d
done
for flag in -n --nuke; do
  assert_recognized apply "$APP" -i "$ICON" "$flag" -d
done
for flag in -d --dry-run; do
  assert_status 0 apply "$APP" -i "$ICON" "$flag"
done
for flag in -v --verbose; do
  assert_status 0 apply "$flag" "$APP" -i "$ICON" -d
done
for flag in -h --help; do
  assert_status 0 apply "$flag"
done

# Restore and Nuke: parser recognition is independent of whether this fresh
# synthetic bundle currently has anything to restore or whether tests run as root.
for flag in -n --nuke -d --dry-run; do
  assert_recognized restore "$APP" -d "$flag"
done
for flag in -h --help; do
  assert_status 0 restore "$flag"
done
for flag in -d --dry-run; do
  assert_recognized nuke "$flag"
done
for flag in -h --help; do
  assert_status 0 nuke "$flag"
done

# Every command accepts -- as its end-of-options marker.
mkdir -p "$ABS_TEST_DIR/root-marker" "$ABS_TEST_DIR/forge-marker"
set +e
(
  cd "$ABS_TEST_DIR/root-marker"
  "$BIN" -- "$INPUT"
) >"$OUTPUT" 2>&1
root_marker_status=$?
set -e
[[ "$root_marker_status" -eq 0 ]] || { cat "$OUTPUT"; test_fail "Root -- marker failed"; exit 1; }

set +e
(
  cd "$ABS_TEST_DIR/forge-marker"
  "$BIN" forge -- "$INPUT"
) >"$OUTPUT" 2>&1
forge_marker_status=$?
set -e
[[ "$forge_marker_status" -eq 0 ]] || { cat "$OUTPUT"; test_fail "Forge -- marker failed"; exit 1; }

assert_status 0 help -- apply
assert_status 0 inspect -- "$APP"
assert_status 0 apply -d -i "$ICON" -- "$APP"
assert_recognized restore -d -- "$APP"
assert_recognized nuke -d -- "$APP"

# Short-option clusters are rejected consistently.
assert_status 2 -hv
assert_status 2 help -hh
assert_status 2 forge "$INPUT" -kd
assert_status 2 inspect -hh
assert_status 2 apply "$APP" -i "$ICON" -dn
assert_status 2 restore "$APP" -dn
assert_status 2 nuke -dh

# Long options never accept an equals-sign value form.
assert_status 2 --help=yes
assert_status 2 help --help=yes
assert_status 2 forge "$INPUT" "--output=$FORGE_OUTPUT"
assert_status 2 inspect --help=yes
assert_status 2 apply "$APP" "--icon=$ICON"
assert_status 2 apply "$APP" -i "$ICON" --strategy=native
assert_status 2 apply "--all=$ICON_LIBRARY"
assert_status 2 restore "$APP" --dry-run=yes
assert_status 2 nuke --dry-run=yes

# Documented value options require a separate, nonempty operand.
for flag in -o --output; do
  assert_status 2 forge "$INPUT" "$flag"
done
for flag in -i --icon; do
  assert_status 2 apply "$APP" "$flag"
done
for flag in -s --strategy; do
  assert_status 2 apply "$APP" -i "$ICON" "$flag"
done
for flag in -a --all; do
  assert_status 2 apply "$flag"
done
assert_status 2 --

# Removed flags, command-level versions, and the obsolete strategy alias fail
# as parser errors rather than being silently accepted.
assert_status 2 -V
for flag in -q --no-warnings; do
  assert_status 2 forge "$INPUT" "$flag"
done
for flag in -c --refresh-caches -r --icon-root -f --force-asset -S --no-resign; do
  assert_status 2 apply "$APP" -i "$ICON" "$flag"
done
for command in forge inspect restore nuke help; do
  assert_status 2 "$command" -v
  assert_status 2 "$command" -V
  assert_status 2 "$command" --version
done
assert_status 2 apply -V
assert_status 2 apply --version
assert_status 2 refresh
assert_status 2 apply "$APP" -i "$ICON" -s legacy-native-alias

test_pass "$TEST_NAME passed"
