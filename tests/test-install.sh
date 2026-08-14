#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="installer"
source tests/test-common.sh

EXPECTED_VERSION="$(tr -d '[:space:]' < VERSION)"

mkdir -p "$TEST_DIR"
TEST_DIR_ABS="$(cd "$TEST_DIR" && pwd)"
TEST_IMAGE_ABS="$(cd "$(dirname "$TEST_IMAGE1")" && pwd)/$(basename "$TEST_IMAGE1")"
INSTALL_PREFIX="$TEST_DIR_ABS/prefix"
OUTPUT="$TEST_DIR_ABS/output.log"

PREFIX="$INSTALL_PREFIX" ./install.sh >"$OUTPUT" 2>&1
INSTALLED_ICONFORGE="$(cd "$INSTALL_PREFIX" && pwd)/bin/iconforge"

assert_file_exists "$INSTALL_PREFIX/bin/iconforge"
assert_file_exists "$INSTALL_PREFIX/lib/iconforge/iconforge"
assert_file_exists "$INSTALL_PREFIX/lib/iconforge/iconforge-processor/iconforge-processor"
assert_file_exists "$INSTALL_PREFIX/lib/iconforge/iconforge-native-icon/iconforge-native-icon"
assert_file_exists "$INSTALL_PREFIX/lib/iconforge/LICENSE"
assert_file_exists "$INSTALL_PREFIX/lib/iconforge/THIRD_PARTY_NOTICES.md"

[[ "$("$INSTALLED_ICONFORGE" --version)" == "iconforge v$EXPECTED_VERSION" ]] || {
  test_fail "Installed launcher reported the wrong version"
  exit 1
}

INSTALL_FORGE_OUTPUT="$TEST_DIR_ABS/forged"
"$INSTALLED_ICONFORGE" forge "$TEST_IMAGE_ABS" --output "$INSTALL_FORGE_OUTPUT"
assert_file_exists "$INSTALL_FORGE_OUTPUT/i-just-wanna-be-an-icon.icns"

LEGACY_HOME="$TEST_DIR_ABS/legacy-home"
LEGACY_CWD="$TEST_DIR_ABS/stateless-output"
LEGACY_WRONG_OUTPUT="$TEST_DIR_ABS/legacy-output"
LEGACY_MARKER="$TEST_DIR_ABS/legacy-config-was-sourced"
mkdir -p "$LEGACY_HOME" "$LEGACY_CWD"
printf 'touch "%s"\nexit 97\n' "$LEGACY_MARKER" >"$LEGACY_HOME/.iconforgerc"
printf 'touch "%s"\nexit 98\n' "$LEGACY_MARKER" >"$INSTALL_PREFIX/lib/iconforge/.iconforge.env"
printf 'touch "%s"\nexit 99\n' "$LEGACY_MARKER" >"$INSTALL_PREFIX/lib/iconforge/.iconforge.local.env"

(
  cd "$LEGACY_CWD"
  HOME="$LEGACY_HOME" \
    ICONFORGE_ICON_ROOT="$LEGACY_WRONG_OUTPUT" \
    CUSTOM_OUTPUT="$LEGACY_WRONG_OUTPUT" \
    KEEP_PNG=true \
    RECURSIVE=true \
    SUPPRESS_WARNINGS=true \
    "$INSTALLED_ICONFORGE" "$TEST_IMAGE_ABS"
)
assert_file_exists "$LEGACY_CWD/i-just-wanna-be-an-icon.icns"
[[ ! -e "$LEGACY_CWD/i-just-wanna-be-an-icon.png" ]] || {
  test_fail "Installed runtime inherited a legacy keep-PNG default"
  exit 1
}
[[ ! -e "$LEGACY_WRONG_OUTPUT" ]] || {
  test_fail "Installed runtime inherited a legacy output or library directory"
  exit 1
}
[[ ! -e "$LEGACY_MARKER" ]] || {
  test_fail "Installed runtime sourced a legacy shell configuration file"
  exit 1
}

PREFIX="$INSTALL_PREFIX" ./uninstall.sh >>"$OUTPUT" 2>&1
[[ ! -e "$INSTALL_PREFIX/bin/iconforge" ]] || { test_fail "Launcher survived uninstall"; exit 1; }
[[ ! -e "$INSTALL_PREFIX/lib/iconforge" ]] || { test_fail "Runtime survived uninstall"; exit 1; }

INVALID_PREFIX="$TEST_DIR_ABS/not-a-directory"
: >"$INVALID_PREFIX"
if PREFIX="$INVALID_PREFIX" ./install.sh >"$OUTPUT" 2>&1; then
  test_fail "Installer accepted a file as PREFIX"
  exit 1
fi
grep -q "install prefix exists but is not a directory" "$OUTPUT" || {
  test_fail "Installer did not explain the invalid prefix"
  exit 1
}

test_pass "$TEST_NAME passed"
