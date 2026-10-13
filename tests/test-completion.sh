#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="generated Zsh configuration completion"
# shellcheck source=tests/test-common.sh
source tests/test-common.sh

command -v zsh >/dev/null 2>&1 || { test_fail 'Zsh is required for completion verification'; exit 1; }
mkdir -p "$TEST_DIR"
./iconforge.sh completion zsh > "$TEST_DIR/iconforge.zsh"

zsh -f -s -- "$TEST_DIR/iconforge.zsh" <<'ZSH_TEST'
set -eu

# Capture completion candidates without requiring an interactive terminal.
compdef() { :; }
compadd() { captured=("$@"); }
_files() { captured=('file fallback'); }
source "$1"

assert_candidates() {
  local expected="$*" actual="${(j: :)captured}"
  [[ "$actual" == "$expected" ]] || {
    print -ru2 -- "Expected completion candidates <$expected>, got <$actual>"
    exit 1
  }
}

words=(iconforge config '')
CURRENT=3
_iconforge
assert_candidates set get unset show path

for action in set get unset; do
  words=(iconforge config "$action" '')
  CURRENT=4
  _iconforge
  assert_candidates the-forge the-hearth default-directory
done

words=(iconforge config set the-forge '')
CURRENT=5
_iconforge
assert_candidates 'file fallback'
ZSH_TEST

test_pass "$TEST_NAME passed"
