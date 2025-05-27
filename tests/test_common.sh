#!/usr/bin/env bash
set -euo pipefail

ICONFORGE="./bin/iconforge.sh"
TEST_IMAGE1="tests/i_just_wanna_be_an_icon.png"
TEST_IMAGE2="tests/pls_oh_pls_convert_me_to_icns.jpg"

: "${TEST_NAME:?TEST_NAME must be set before sourcing test_common.sh}"

# Generate a consistent, lowercase, underscore-safe temp dir name
TEST_DIR="tests/tmp_$(echo "$TEST_NAME" | tr '[:upper:] ' '[:lower:]_')"

cleanup() {
  [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR" || true
}
trap 'cleanup || true' EXIT

assert_file_exists() {
  [[ -f "$1" ]] && echo "✅ $1" || { echo "❌ Missing: $1"; exit 1; }
}
