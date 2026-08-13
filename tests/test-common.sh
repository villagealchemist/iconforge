#!/usr/bin/env bash
set -euo pipefail

ICONFORGE="./iconforge.sh"
TEST_IMAGE1="tests/i-just-wanna-be-an-icon.png"
TEST_IMAGE2="tests/pls-oh-pls-convert-me-to-icns.jpg"

TEST_COLOR_GREEN=$'\033[32m'
TEST_COLOR_RED=$'\033[31m'
TEST_COLOR_CYAN=$'\033[36m'
TEST_COLOR_YELLOW=$'\033[33m'
TEST_COLOR_BRIGHT_MAGENTA=$'\033[95m'
TEST_COLOR_RESET=$'\033[0m'

test_status() {
  local color="$1"
  local symbol="$2"
  local label="$3"
  shift 3
  printf '%s%s [%s]%s %s\n' "$color" "$symbol" "$label" "$TEST_COLOR_RESET" "$*"
}

test_pass() {
  test_status "$TEST_COLOR_GREEN" "✓" "PASS" "$@"
}

test_fail() {
  test_status "$TEST_COLOR_RED" "✗" "FAIL" "$@"
}

test_run() {
  test_status "$TEST_COLOR_CYAN" "▸" "RUN" "$@"
}

test_skip() {
  test_status "$TEST_COLOR_YELLOW" "○" "SKIP" "$@"
}

test_info() {
  test_status "$TEST_COLOR_BRIGHT_MAGENTA" "ⓘ" "INFO" "$@"
}

: "${TEST_NAME:?TEST_NAME must be set before sourcing test-common.sh}"

# Generate a consistent, lowercase, underscore-safe temp dir name
TEST_DIR="tests/tmp_$(echo "$TEST_NAME" | tr '[:upper:] ' '[:lower:]_')"

cleanup() {
  if [[ -d "$TEST_DIR" ]]; then
    chmod -R u+w "$TEST_DIR" 2>/dev/null || true
    rm -rf "$TEST_DIR"
  fi
}
trap 'cleanup || true' EXIT

assert_file_exists() {
  if [[ -f "$1" ]]; then
    test_pass "$1"
  else
    test_fail "Missing: $1"
    exit 1
  fi
}

assert_dir_exists() {
  if [[ -d "$1" ]]; then
    test_pass "$1"
  else
    test_fail "Missing directory: $1"
    exit 1
  fi
}
