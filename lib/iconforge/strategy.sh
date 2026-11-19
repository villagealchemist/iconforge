#!/usr/bin/env bash

strategy_validate_name() {
  local strategy_name="$1"
  case "$strategy_name" in
    native|internal-icns) return 0 ;;
    *) usage_fail "Unknown strategy: $strategy_name (expected native or internal-icns)" || return 2 ;;
  esac
}

select_apply_strategy() {
  local requested_strategy="${1:-native}"
  strategy_validate_name "$requested_strategy" || return $?

  # Each strategy collects its own prerequisite failures before any mutation.
  printf '%s\n' "$requested_strategy"
}

apply_icon_with_strategy() {
  local strategy_name="$1"
  local icon_file="$2"
  strategy_validate_name "$strategy_name" || return $?
  case "$strategy_name" in
    native) strategy_native_icon_apply "$icon_file" ;;
    internal-icns) strategy_internal_icns_apply "$icon_file" ;;
  esac
}
