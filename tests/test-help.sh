#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="complete command help"
source tests/test-common.sh

ROOT_DIR="$(pwd)"
ICONFORGE_BIN="$ROOT_DIR/iconforge.sh"
OUTPUT="$TEST_DIR/help.txt"

assert_help_contains() {
  local needle="$1"
  grep -F -- "$needle" "$OUTPUT" >/dev/null || {
    echo "❌ Expected help output to contain: $needle"
    exit 1
  }
}

mkdir -p "$TEST_DIR"

"$ICONFORGE_BIN" --help >"$OUTPUT"
for needle in \
  "forge" "inspect" "apply" "restore" "refresh" "nuke" \
  "-h, --help" "-V, --version" "iconforge <command>"; do
  assert_help_contains "$needle"
done

"$ICONFORGE_BIN" forge --help >"$OUTPUT"
for needle in \
  "-o, --output" "-k, --keep-png" "-r, --recursive" \
  "-q, --no-warnings" "-n, --dry-run" "-V, --version" "-h, --help" \
  "Supported input formats" "Output:" "Examples:"; do
  assert_help_contains "$needle"
done

"$ICONFORGE_BIN" inspect -h >"$OUTPUT"
assert_help_contains "-h, --help"
assert_help_contains "iconforge inspect <app>"

"$ICONFORGE_BIN" help apply >"$OUTPUT"
for needle in \
  "-i, --icon" "-s, --strategy" "-a, --all" "-r, --icon-root" \
  "-c, --refresh-caches" "--nuke" "-f, --force-asset" \
  "-S, --no-resign" "-n, --dry-run" "-v, --verbose" "-h, --help" \
  "Strategies:" "Managed library layout:" "Examples:"; do
  assert_help_contains "$needle"
done

"$ICONFORGE_BIN" restore --help >"$OUTPUT"
for needle in \
  "-c, --refresh-caches" "--nuke" "-S, --no-resign" \
  "-n, --dry-run" "-h, --help" "Examples:"; do
  assert_help_contains "$needle"
done

"$ICONFORGE_BIN" refresh -h >"$OUTPUT"
for needle in \
  "iconforge refresh" "iconforge nuke" "-n, --dry-run" \
  "-h, --help" "Behavior:" "Examples:"; do
  assert_help_contains "$needle"
done

assert_equals() {
  [[ "$1" == "$2" ]] || { echo "❌ Expected '$1' == '$2'"; exit 1; }
}

assert_equals "$("$ICONFORGE_BIN" -V)" "iconforge v2.0.1"
assert_equals "$("$ICONFORGE_BIN" forge --version)" "iconforge v2.0.1"

set +e
"$ICONFORGE_BIN" help unknown >"$OUTPUT" 2>&1
HELP_STATUS=$?
set -e
[[ "$HELP_STATUS" -ne 0 ]] || { echo "❌ Unknown help topics should fail"; exit 1; }
assert_help_contains "Unknown help topic: unknown"

set +e
"$ICONFORGE_BIN" forge --output >"$OUTPUT" 2>&1
FORGE_OPTION_STATUS=$?
set -e
[[ "$FORGE_OPTION_STATUS" -ne 0 ]] || { echo "❌ Missing forge option values should fail"; exit 1; }
assert_help_contains "--output requires an output directory"

set +e
"$ICONFORGE_BIN" apply --icon >"$OUTPUT" 2>&1
APPLY_OPTION_STATUS=$?
set -e
[[ "$APPLY_OPTION_STATUS" -ne 0 ]] || { echo "❌ Missing apply option values should fail"; exit 1; }
assert_help_contains "--icon requires a .icns file"

echo "🎉 $TEST_NAME passed"
