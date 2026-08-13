#!/usr/bin/env bash

strategy_native_icon_available() {
  [[ -x "$ICONFORGE_NATIVE_ICON" ]]
}

strategy_native_icon_is_set() {
  strategy_native_icon_available || return 1
  "$ICONFORGE_NATIVE_ICON" test "$APP_PATH" >/dev/null 2>&1
}

strategy_native_icon_requires_authorization() {
  [[ ! -w "$APP_PATH" ]]
}

strategy_native_icon_authorization_error() {
  local icon_file="${1:-}"

  fail "Administrator authorization is required to change the Finder custom icon on $APP_PATH" || true
  if [[ -n "$icon_file" ]]; then
    printf 'Run this one operation with scoped elevation:\n  sudo ' >&2
    printf '%q ' "$ICONFORGE_NATIVE_ICON" set "$APP_PATH" "$icon_file" >&2
    printf '\n' >&2
    printf 'Then refresh user caches without sudo: iconforge refresh\n' >&2
  fi
  return 1
}

require_native_icon_helper() {
  strategy_native_icon_available || fail "Bundled native icon helper not found or not executable: $ICONFORGE_NATIVE_ICON" || return 1
}

strategy_native_icon_apply() {
  local icon_file="$1"

  require_native_icon_helper || return 1
  require_app_bundle_path "$APP_PATH" || return 1
  require_existing_file_path "Icon file" "$icon_file" || return 1
  [[ "$icon_file" == *.icns ]] || fail "Icon file must be a .icns file: $icon_file" || return 1

  if [[ "$ICONFORGE_DRY_RUN" != true ]] && strategy_native_icon_requires_authorization; then
    strategy_native_icon_authorization_error "$icon_file"
    return 1
  fi

  run_cmd "$ICONFORGE_NATIVE_ICON" set "$APP_PATH" "$icon_file" || return 1

  if [[ "$ICONFORGE_DRY_RUN" != true ]]; then
    run_quiet_cmd "$ICONFORGE_NATIVE_ICON" test "$APP_PATH" || fail "Native helper did not persist a usable Finder custom icon for $APP_PATH" || return 1
  fi
}

strategy_native_icon_restore() {
  require_native_icon_helper || return 1
  require_app_bundle_path "$APP_PATH" || return 1

  if [[ "$ICONFORGE_DRY_RUN" != true ]] && strategy_native_icon_requires_authorization; then
    strategy_native_icon_authorization_error
    return 1
  fi

  run_cmd "$ICONFORGE_NATIVE_ICON" remove "$APP_PATH"
}
