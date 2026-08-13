#!/usr/bin/env bash
set -euo pipefail

ICONFORGE="./iconforge.sh"
TEST_IMAGE1="tests/i_just_wanna_be_an_icon.png"
TEST_IMAGE2="tests/pls_oh_pls_convert_me_to_icns.jpg"

: "${TEST_NAME:?TEST_NAME must be set before sourcing test_common.sh}"

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
    echo "✅ $1"
  else
    echo "❌ Missing: $1"
    exit 1
  fi
}

assert_dir_exists() {
  if [[ -d "$1" ]]; then
    echo "✅ $1"
  else
    echo "❌ Missing directory: $1"
    exit 1
  fi
}
