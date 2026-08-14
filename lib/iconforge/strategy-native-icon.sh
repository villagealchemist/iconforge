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
  "$ICONFORGE_NATIVE_ICON" present "$APP_PATH" >/dev/null 2>&1
}

strategy_native_icon_requires_authorization() {
  [[ ! -w "$APP_PATH" ]]
}

strategy_native_icon_authorization_error() {
  fail "The native icon write needs authorization for this app: $APP_PATH" || true
  note "IconForge did not modify the application. Retry with a writable copy or explicitly authorize the helper operation."
  return 1
}

strategy_native_icon_apply() {
  local icon_file="$1"

  require_native_icon_helper || return 1
  require_app_bundle_path "$APP_PATH" || return 1
  validate_icns_file "$icon_file" || return 1

  if strategy_native_icon_requires_authorization; then
    if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
      warn "The real native icon write would need authorization for $APP_PATH"
    else
      strategy_native_icon_authorization_error
      return 1
    fi
  fi

  run_cmd "$ICONFORGE_NATIVE_ICON" set "$APP_PATH" "$icon_file" || return 1
  if [[ "$ICONFORGE_DRY_RUN" != true ]]; then
    "$ICONFORGE_NATIVE_ICON" test "$APP_PATH" >/dev/null 2>&1 || {
      fail "Native helper did not persist a usable Finder custom icon for $APP_PATH" || return 1
    }
  fi
}

strategy_native_icon_restore() {
  require_native_icon_helper || return 1
  require_app_bundle_path "$APP_PATH" || return 1

  if strategy_native_icon_requires_authorization; then
    if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
      warn "The real native icon removal would need authorization for $APP_PATH"
    else
      strategy_native_icon_authorization_error
      return 1
    fi
  fi
  run_cmd "$ICONFORGE_NATIVE_ICON" remove "$APP_PATH"
}
