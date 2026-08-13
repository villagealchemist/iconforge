#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="installer"
source tests/test-common.sh

INSTALL_PREFIX="$TEST_DIR/prefix"
OUTPUT="$TEST_DIR/output.log"
EXPECTED_VERSION="$(tr -d '[:space:]' < VERSION)"

mkdir -p "$TEST_DIR"

PREFIX="$INSTALL_PREFIX" ./install.sh >"$OUTPUT" 2>&1

assert_file_exists "$INSTALL_PREFIX/bin/iconforge"
assert_file_exists "$INSTALL_PREFIX/lib/iconforge/iconforge"
assert_file_exists "$INSTALL_PREFIX/lib/iconforge/iconforge-processor/iconforge-processor"
assert_file_exists "$INSTALL_PREFIX/lib/iconforge/iconforge-native-icon/iconforge-native-icon"

[[ "$("$INSTALL_PREFIX/bin/iconforge" --version)" == "iconforge v$EXPECTED_VERSION" ]] || {
  test_fail "Installed launcher reported the wrong version"
  exit 1
}

INSTALL_FORGE_OUTPUT="$TEST_DIR/forged"
"$INSTALL_PREFIX/bin/iconforge" forge "$TEST_IMAGE1" --output "$INSTALL_FORGE_OUTPUT"
assert_file_exists "$INSTALL_FORGE_OUTPUT/i-just-wanna-be-an-icon.icns"

PREFIX="$INSTALL_PREFIX" ./uninstall.sh >>"$OUTPUT" 2>&1
[[ ! -e "$INSTALL_PREFIX/bin/iconforge" ]] || { test_fail "Launcher survived uninstall"; exit 1; }
[[ ! -e "$INSTALL_PREFIX/lib/iconforge" ]] || { test_fail "Runtime survived uninstall"; exit 1; }

INVALID_PREFIX="$TEST_DIR/not-a-directory"
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
