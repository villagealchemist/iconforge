#!/usr/bin/env bash

strategy_internal_icns_is_writable() {
  [[ -n "$APP_ICON_TARGET" && -f "$APP_ICON_TARGET" ]] || return 1
  [[ -w "$APP_PATH" ]] || return 1
  [[ -w "$APP_RESOURCES_DIR" ]] || return 1
  [[ -w "$APP_ICON_TARGET" ]] || return 1
  [[ ! -e "$APP_INFO_PLIST" || -w "$APP_INFO_PLIST" ]] || return 1

  if [[ -n "$APP_ICON_BACKUP" && -e "$APP_ICON_BACKUP" ]]; then
    [[ -w "$APP_ICON_BACKUP" ]] || return 1
  fi
}

strategy_internal_icns_require_writable() {
  strategy_internal_icns_is_writable && return 0

  fail "Internal icon replacement requires write access to the app bundle: $APP_PATH" || true
  warn "Use --strategy native for a root-owned or vendor-managed application."
  return 1
}

strategy_internal_icns_rollback() {
  local no_resign="${1:-false}"
  local rollback_ok=true

  if [[ -z "$APP_ICON_BACKUP" || ! -f "$APP_ICON_BACKUP" ]]; then
    warn "Automatic rollback is unavailable because no internal icon backup exists."
    return 1
  fi

  warn "Internal apply failed; restoring the preserved icon backup."
  run_cmd "$CP_BIN" "$APP_ICON_BACKUP" "$APP_ICON_TARGET" || rollback_ok=false
  touch_app_bundle "$APP_PATH" || rollback_ok=false
  if [[ "$no_resign" != true ]]; then
    resign_app_bundle "$APP_PATH" || rollback_ok=false
  fi

  if [[ "$rollback_ok" != true ]]; then
    warn "Icon Forge restored as much as it could, but could not verify the complete rollback. Reinstall the app from its official source before launching it."
    return 1
  fi

  warn "The preserved icon was restored after the failed apply."
  return 0
}

strategy_internal_icns_apply() {
  local icon_file="$1"
  local force_asset="${2:-false}"
  local replacement_checksum=""
  local target_checksum=""

  require_app_bundle_path "$APP_PATH" || return 1
  require_existing_file_path "Icon file" "$icon_file" || return 1
  [[ "$icon_file" == *.icns ]] || fail "Icon file must be a .icns file: $icon_file" || return 1

  if [[ "$APP_USES_ASSET_CATALOG" == true && "$force_asset" != true ]]; then
    warn "This app appears asset-catalog backed."
    warn "Replacing $APP_ICON_TARGET may have no visible effect."
    fail "Refusing icon replacement without --force-asset" || return 1
  fi

  require_nonempty_path "Loose icon target path" "$APP_ICON_TARGET" || return 1
  require_existing_file_path "Loose icon target" "$APP_ICON_TARGET" || return 1
  require_nonempty_path "Backup icon path" "$APP_ICON_BACKUP" || return 1
  strategy_internal_icns_require_writable || return 1

  replacement_checksum="$(shasum -a 256 "$icon_file" | awk '{print $1}')"
  target_checksum="$(shasum -a 256 "$APP_ICON_TARGET" | awk '{print $1}')"

  if [[ "$replacement_checksum" == "$target_checksum" ]]; then
    note "Target icon already matches $icon_file"
  fi

  if [[ ! -f "$APP_ICON_BACKUP" ]]; then
    run_cmd "$CP_BIN" "$APP_ICON_TARGET" "$APP_ICON_BACKUP" || return 1
  fi

  run_cmd "$CP_BIN" "$icon_file" "$APP_ICON_TARGET" || return 1
}
