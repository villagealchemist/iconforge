#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="stateless runtime ignores legacy configuration"
source tests/test-common.sh

RUNTIME_ROOT="$TEST_DIR/runtime"
FAKE_HOME="$TEST_DIR/home"
MARKER="$TEST_DIR/sourced-marker"
OUTPUT="$TEST_DIR/output.log"
mkdir -p "$RUNTIME_ROOT" "$FAKE_HOME/.config/iconforge"
cp VERSION "$RUNTIME_ROOT/VERSION"

for legacy_file in "$RUNTIME_ROOT/.iconforge.env" "$RUNTIME_ROOT/.iconforge.local.env" "$FAKE_HOME/.iconforgerc"; do
  printf 'touch %q\n' "$MARKER" >"$legacy_file"
done
printf '<plist><dict><key>icon_root</key><string>/poison</string></dict></plist>\n' >"$FAKE_HOME/.config/iconforge/config.plist"

HOME="$FAKE_HOME" ICONFORGE_ROOT="$RUNTIME_ROOT" ICONFORGE_ICON_ROOT="/poison" \
bash -c 'source "$1"; printf "%s\n" "$ICONFORGE_DRY_RUN"' \
  _ "$PWD/lib/iconforge/common.sh" >"$OUTPUT"

[[ ! -e "$MARKER" ]] || { test_fail "A legacy shell config was sourced"; exit 1; }
[[ "$(cat "$OUTPUT")" == "false" ]] || { test_fail "Runtime dry-run state was not reset"; exit 1; }

(
  cd "$TEST_DIR"
  HOME="$FAKE_HOME" CUSTOM_OUTPUT="/poison" KEEP_PNG=true RECURSIVE=true SUPPRESS_WARNINGS=true \
    "$PWD/../../iconforge.sh" "$PWD/../i-just-wanna-be-an-icon.png" -d >"$PWD/forge-plan.log"
)
! grep -F "/poison" "$TEST_DIR/forge-plan.log" >/dev/null || { test_fail "Forge inherited a legacy output default"; exit 1; }

HOME="$FAKE_HOME" ICONFORGE_ICON_ROOT="$TEST_DIR/icons" "$PWD/iconforge.sh" -v >"$OUTPUT"
[[ "$(cat "$OUTPUT")" == "iconforge v2.0.0" ]] || { test_fail "Legacy state affected root version"; exit 1; }

set +e
HOME="$FAKE_HOME" ICONFORGE_ICON_ROOT="$TEST_DIR/icons" "$PWD/iconforge.sh" apply -a >"$OUTPUT" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 2 ]] || { test_fail "Bare --all should require an explicit directory"; exit 1; }
grep -F -- "--all requires exactly one icon directory" "$OUTPUT" >/dev/null || { test_fail "Missing explicit-directory error"; exit 1; }

test_pass "$TEST_NAME passed"
