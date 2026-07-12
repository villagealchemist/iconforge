#!/usr/bin/env bash

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
