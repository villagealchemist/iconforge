#!/usr/bin/env bash
# Portable tests for CLI policy using an inert backend. No AppKit, applications,
# caches, administrator privileges, or real user configuration are touched.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/iconforge/cli.sh
source "$ROOT/lib/iconforge/cli.sh"
# shellcheck source=lib/iconforge/config.sh
source "$ROOT/lib/iconforge/config.sh"

fail() { printf 'Error: %s\n' "$*" >&2; return 1; }
usage_fail() { printf 'Error: %s\n' "$*" >&2; return 2; }
note() { printf '%s\n' "$*" >&2; }
join_by() { local sep="$1"; shift; local first=true item; for item in "$@"; do [[ "$first" == true ]] || printf '%s' "$sep"; printf '%s' "$item"; first=false; done; }
forge_help() { printf 'forge help\n'; }
inspect_help() { printf 'inspect help\n'; }
restore_help() { printf 'restore help\n'; }
nuke_help() { printf 'nuke help\n'; }
backend_require() { :; }
CONFIG_READS=0
CONFIG_FAIL=false
HEARTH=/library
FORGE=/work
config_effective_directory() {
  CONFIG_READS=$((CONFIG_READS + 1))
  [[ "$CONFIG_FAIL" != true ]] || return 1
  if [[ "$1" == the-forge ]]; then CONFIG_DIRECTORY="$FORGE"; else CONFIG_DIRECTORY="$HEARTH"; fi
}
CALLS=0
CALL_KIND=""
CALL_ARGS=()
CAPTURED_ROOTS=()
record_call() {
  CALLS=$((CALLS + 1)); CALL_KIND="$1"; shift; CALL_ARGS=("$@")
  CAPTURED_ROOTS=("${ICONFORGE_EXTRA_APPLICATION_ROOTS[@]+"${ICONFORGE_EXTRA_APPLICATION_ROOTS[@]}"}")
}
backend_forge() { record_call forge "$@"; }
backend_apply_one() { record_call one "$@"; }
backend_apply_all() { record_call all "$@"; }
backend_inspect() { record_call inspect "$@"; }
backend_restore() { record_call restore "$@"; }
backend_refresh() { record_call refresh "$@"; }
RESOLUTION_FAIL=false
backend_resolve_target() {
  [[ "$RESOLUTION_FAIL" != true ]] || return 1
  BACKEND_TARGET="/apps/Firefox.app"; BACKEND_TARGET_KEYS=(firefox)
  [[ "$1" != Nuke ]] || { BACKEND_TARGET="/apps/Nuke.app"; BACKEND_TARGET_KEYS=(nuke); }
}
ICON_MODE=one
backend_scan_icons() {
  case "$ICON_MODE" in
    one) BACKEND_ICON_FILES=("$1/Firefox.icns"); BACKEND_ICON_KEYS=(firefox) ;;
    nuke) BACKEND_ICON_FILES=("$1/Nuke.icns"); BACKEND_ICON_KEYS=(nuke) ;;
    empty) BACKEND_ICON_FILES=(); BACKEND_ICON_KEYS=() ;;
    duplicate) BACKEND_ICON_FILES=("$1/Firefox.icns" "$1/firefox.ICNS"); BACKEND_ICON_KEYS=(firefox firefox) ;;
    unrelated) BACKEND_ICON_FILES=("$1/Firefox.icns" "$1/a/Discord.icns" "$1/b/Discord.icns"); BACKEND_ICON_KEYS=(firefox discord discord) ;;
    aliases) BACKEND_ICON_FILES=("$1/Firefox.icns" "$1/Firefox Browser.icns"); BACKEND_ICON_KEYS=(firefox 'firefox browser'); BACKEND_TARGET_KEYS=(firefox 'firefox browser') ;;
  esac
}

assert_eq() { [[ "$1" == "$2" ]] || { printf 'FAIL: expected <%s>, got <%s>\n' "$2" "$1" >&2; exit 1; }; }
assert_arg() { local arg; for arg in "${CALL_ARGS[@]+"${CALL_ARGS[@]}"}"; do [[ "$arg" != "$1" ]] || return 0; done; printf 'FAIL missing argument <%s>\n' "$1" >&2; exit 1; }
expect_error() {
  local expected="$1" status=0 before="$CALLS"; shift
  "$@" >/dev/null 2>&1 || status=$?
  assert_eq "$status" "$expected"
  assert_eq "$CALLS" "$before"
}
TESTS=0
case_run() { ( "$@" ); TESTS=$((TESTS + 1)); printf 'PASS %s\n' "$1"; }

lookup() { cli_apply Firefox; assert_eq "$CALL_KIND" one; assert_arg /library/Firefox.icns; assert_arg /apps/Firefox.app; assert_eq "$CONFIG_READS" 1; }
shorthand() { cli_apply Firefox nuke; assert_eq "$CALLS" 1; assert_arg --nuke; }
flag_refresh() { cli_apply Firefox --refresh; assert_arg --nuke; }
explicit_bypass() { CONFIG_FAIL=true; cli_apply Firefox --icon ./custom.icns; assert_eq "$CONFIG_READS" 0; assert_arg ./custom.icns; }
from_bypass() { CONFIG_FAIL=true; cli_apply Firefox --from='/alternate icons'; assert_eq "$CONFIG_READS" 0; assert_arg '/alternate icons/Firefox.icns'; }
malformed_implicit() { CONFIG_FAIL=true; expect_error 1 cli_apply Firefox; }
missing_config() { HEARTH=""; expect_error 2 cli_apply Firefox; }
missing_icon() { ICON_MODE=empty; expect_error 1 cli_apply Firefox; }
duplicate_icon() { ICON_MODE=duplicate; expect_error 1 cli_apply Firefox; }
alias_collision() { ICON_MODE=aliases; expect_error 1 cli_apply Firefox; }
unrelated_duplicates() { ICON_MODE=unrelated; cli_apply Firefox; assert_arg /library/Firefox.icns; }
unresolved_app() { RESOLUTION_FAIL=true; expect_error 1 cli_apply Firefox; }
bulk() { cli_apply --all --nuke; assert_eq "$CALL_KIND" all; assert_eq "$CALLS" 1; assert_arg /library; assert_arg --nuke; }
bulk_explicit() { CONFIG_FAIL=true; cli_apply --all '/alternate icons'; assert_eq "$CONFIG_READS" 0; assert_arg '/alternate icons'; }
bulk_from() { cli_apply --all --from /other; assert_arg /other; }
bulk_nuke_directory() { CONFIG_FAIL=true; cli_apply --all nuke; assert_arg nuke; local arg; for arg in "${CALL_ARGS[@]}"; do [[ "$arg" != --nuke ]] || exit 1; done; }
no_implicit_bulk() { expect_error 2 cli_apply; }
conflicting_sources() { expect_error 2 cli_apply Firefox --icon one.icns --from /other; }
conflicting_bulk() { expect_error 2 cli_apply --all /other --from /another; }
unsafe_bulk_strategy() { expect_error 2 cli_apply --all --strategy internal-icns; }
invalid_strategy() { expect_error 2 cli_apply Firefox --strategy surprise; }
option_duplicates() { expect_error 2 cli_apply Firefox -i one --icon two; expect_error 2 cli_apply Firefox --from a --from b; }
end_of_options() { expect_error 2 cli_apply -- Firefox nuke; }
app_named_nuke() { ICON_MODE=nuke; cli_apply Nuke; assert_arg /apps/Nuke.app; assert_arg /library/Nuke.icns; }
no_invented_chains() { expect_error 2 cli_apply Firefox nuke restore; expect_error 2 cli_apply Firefox nuke --all; }
preview() { cli_apply Firefox nuke --dry-run >/dev/null; assert_arg --dry-run; assert_arg --nuke; }
forge_default() { cli_forge ./art.png Firefox; assert_eq "$CALL_KIND" forge; assert_arg /work; assert_arg --output; }
forge_override() { CONFIG_FAIL=true; cli_forge ./art.png --output=/different; assert_eq "$CONFIG_READS" 0; assert_arg /different; }
forge_end_marker() { cli_forge -- ./-art.png; assert_eq "${CALL_ARGS[0]}" --output; assert_eq "${CALL_ARGS[2]}" --; assert_eq "${CALL_ARGS[3]}" ./-art.png; }
normalization_literal() { cli_normalize_options forge -- '--output=literal'; assert_eq "${CLI_ARGS[1]}" '--output=literal'; }
empty_option() { expect_error 2 cli_apply Firefox --from=; }
boolean_equals() { expect_error 2 cli_apply Firefox --dry-run=true; }
quoted_path() { cli_apply Firefox --from "/a folder/\$(not-a-command)"; assert_arg "/a folder/\$(not-a-command)/Firefox.icns"; }
additional_roots() { cli_apply Firefox --app-root /tmp; assert_eq "${CAPTURED_ROOTS[0]}" "$(cd -P /tmp && pwd)"; [[ "${ICONFORGE_EXTRA_APPLICATION_ROOTS+x}" != x ]]; }
invalid_root() { expect_error 2 cli_apply Firefox --app-root /; }
read_only_routing() { cli_target_command inspect Firefox --app-root=/tmp; assert_eq "$CALL_KIND" inspect; assert_arg Firefox; assert_eq "${CAPTURED_ROOTS[0]}" "$(cd -P /tmp && pwd)"; }
help_no_config() { CONFIG_FAIL=true; cli_apply --help >/dev/null; cli_forge --help >/dev/null; assert_eq "$CONFIG_READS" 0; assert_eq "$CALLS" 0; }

for name in lookup shorthand flag_refresh explicit_bypass from_bypass malformed_implicit missing_config missing_icon duplicate_icon alias_collision unrelated_duplicates unresolved_app bulk bulk_explicit bulk_from bulk_nuke_directory no_implicit_bulk conflicting_sources conflicting_bulk unsafe_bulk_strategy invalid_strategy option_duplicates end_of_options app_named_nuke no_invented_chains preview forge_default forge_override forge_end_marker normalization_literal empty_option boolean_equals quoted_path additional_roots invalid_root read_only_routing help_no_config; do case_run "$name"; done
printf '%s portable CLI policy tests passed\n' "$TESTS"
