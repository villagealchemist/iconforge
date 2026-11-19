#!/usr/bin/env bash

strategy_native_icon_available() {
  [[ -x "$ICONFORGE_NATIVE_ICON" ]]
}

require_native_icon_helper() {
  strategy_native_icon_available || {
    fail "Bundled native icon helper not found or not executable: $ICONFORGE_NATIVE_ICON"
    return 1
  }
}

strategy_native_icon_is_set() {
  require_native_icon_helper || return 1
  "$ICONFORGE_NATIVE_ICON" test "$APP_PATH" >/dev/null 2>&1
}

strategy_native_icon_is_present() {
  require_native_icon_helper || return 1
  "$ICONFORGE_NATIVE_ICON" present "$APP_PATH" >/dev/null
}

strategy_native_icon_requires_authorization() {
  [[ ! -w "$APP_PATH" ]]
}

strategy_native_icon_authorization_guidance() {
  local operation="$1"
  shift

  "$ICONFORGE_NATIVE_ICON" diagnose "$APP_PATH" || true
  remedy "Resolve any locked-path or read-only-volume errors above first. Administrator privileges do not override those conditions."
  note "Retry with a writable copy, or, if ownership is the only blocker, authorize only this app's icon change:"
  note "  $(format_cmd sudo -- "$ICONFORGE_NATIVE_ICON" "$operation" "$APP_PATH" "$@")"
  note "Enter your Mac administrator password if prompted; Terminal does not display password characters."
  note "After it succeeds, refresh icons if needed with: iconforge nuke"
  note "Do not run the whole IconForge command or iconforge nuke with sudo."
}

strategy_native_icon_authorization_error() {
  fail "Your account cannot write to this app: $APP_PATH" || true
  note "IconForge did not modify the application."
  strategy_native_icon_authorization_guidance "$@"
  return 1
}

strategy_native_icon_apply() {
  local icon_file="$1"
  local preflight_failed=false
  local helper_status=0

  require_native_icon_helper || preflight_failed=true
  require_app_bundle_path "$APP_PATH" || preflight_failed=true
  validate_icns_file "$icon_file" || preflight_failed=true
  [[ "$preflight_failed" != true ]] || return 1

  if strategy_native_icon_requires_authorization; then
    if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
      warn "The real native icon write would need authorization for $APP_PATH"
    else
      strategy_native_icon_authorization_error set "$icon_file"
      return 1
    fi
  fi

  run_cmd "$ICONFORGE_NATIVE_ICON" set "$APP_PATH" "$icon_file" || helper_status=$?
  if [[ "$helper_status" -ne 0 ]]; then
    fail "Finder icon application failed (helper status $helper_status): $APP_PATH; source: $icon_file" || true
    remedy "Review the helper diagnostics above before retrying this app. The operation did not finish successfully."
    return 1
  fi
  if [[ "$ICONFORGE_DRY_RUN" != true ]]; then
    "$ICONFORGE_NATIVE_ICON" test "$APP_PATH" >/dev/null || {
      fail "Native helper did not persist a usable Finder custom icon for $APP_PATH" || true
      note "The write was attempted but could not be verified. A cache refresh cannot repair missing icon data."
      return 1
    }
  fi
}

strategy_native_icon_restore() {
  local helper_status=0
  require_native_icon_helper || return 1
  require_app_bundle_path "$APP_PATH" || return 1

  if strategy_native_icon_requires_authorization; then
    if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
      warn "The real native icon removal would need authorization for $APP_PATH"
    else
      strategy_native_icon_authorization_error remove
      return 1
    fi
  fi
  run_cmd "$ICONFORGE_NATIVE_ICON" remove "$APP_PATH" || helper_status=$?
  if [[ "$helper_status" -ne 0 ]]; then
    fail "Finder icon removal failed (helper status $helper_status): $APP_PATH" || true
    note "Review the helper diagnostics before retrying removal; any completed internal restore has been retained."
    return 1
  fi
  return 0
}
