#!/usr/bin/env bash

INTERNAL_APPLY_CHANGED=false
INTERNAL_TRANSACTION_ACTIVE=false
INTERNAL_TRANSACTION_DIRTY=false
INTERNAL_TRANSACTION_INTERRUPT_STATUS=0
INTERNAL_TRANSACTION_KIND=""
INTERNAL_TRANSACTION_APP_PATH=""
INTERNAL_TRANSACTION_RESOURCES_DIR=""
INTERNAL_TRANSACTION_TARGET=""
INTERNAL_TRANSACTION_BACKUP=""
INTERNAL_TRANSACTION_ROLLBACK_SOURCE=""
INTERNAL_TRANSACTION_REMOVE_NEW_BACKUP=false
INTERNAL_TRANSACTION_SAVED_EXIT_TRAP=""
INTERNAL_TRANSACTION_SAVED_HUP_TRAP=""
INTERNAL_TRANSACTION_SAVED_INT_TRAP=""
INTERNAL_TRANSACTION_SAVED_TERM_TRAP=""

strategy_internal_icns_is_writable() {
  [[ -n "$APP_ICON_TARGET" && -f "$APP_ICON_TARGET" ]] || return 1
  mutable_app_info_plist_is_safe "$APP_PATH" || return 1
  loose_icon_path_is_safe "$APP_RESOURCES_DIR" "$APP_ICON_TARGET" || return 1
  loose_icon_path_is_safe "$APP_RESOURCES_DIR" "$APP_ICON_BACKUP" true || return 1
  [[ -w "$APP_PATH" && -w "$APP_RESOURCES_DIR" && -w "$APP_ICON_TARGET" ]] || return 1
  [[ ! -e "$APP_INFO_PLIST" || -w "$APP_INFO_PLIST" ]] || return 1
}

strategy_internal_icns_require_writable() {
  strategy_internal_icns_is_writable && return 0
  fail "Internal icon replacement requires write access to the app bundle: $APP_PATH" || true
  warn "Use --strategy native for a protected or vendor-managed application."
  return 1
}

strategy_internal_icns_atomic_copy() {
  local source="$1"
  local target="$2"
  local replace="${3:-true}"
  local target_dir
  local temporary

  target_dir="$(dirname "$target")"
  temporary="$(mktemp "$target_dir/.iconforge-internal.XXXXXX")" || return 1
  if ! "$CP_BIN" -p "$source" "$temporary"; then
    /bin/rm -f "$temporary"
    return 1
  fi
  if [[ "$replace" == true ]]; then
    "$ICONFORGE_NATIVE_ICON" rename-exact "$temporary" "$target" >/dev/null 2>&1 || {
      /bin/rm -f "$temporary"
      return 1
    }
  elif ! "$ICONFORGE_NATIVE_ICON" link-exclusive "$temporary" "$target" >/dev/null 2>&1; then
    /bin/rm -f "$temporary"
    return 1
  fi
  /bin/rm -f "$temporary"
}

internal_transaction_restore_saved_trap() {
  local saved_trap="$1"
  local signal_name="$2"

  if [[ -n "$saved_trap" ]]; then
    eval "$saved_trap"
  else
    trap - "$signal_name"
  fi
}

internal_transaction_restore_traps() {
  internal_transaction_restore_saved_trap "$INTERNAL_TRANSACTION_SAVED_HUP_TRAP" HUP
  internal_transaction_restore_saved_trap "$INTERNAL_TRANSACTION_SAVED_INT_TRAP" INT
  internal_transaction_restore_saved_trap "$INTERNAL_TRANSACTION_SAVED_TERM_TRAP" TERM
  internal_transaction_restore_saved_trap "$INTERNAL_TRANSACTION_SAVED_EXIT_TRAP" EXIT
}

internal_transaction_run_saved_exit_trap() {
  local exit_status="$1"
  local saved_trap="$INTERNAL_TRANSACTION_SAVED_EXIT_TRAP"

  [[ -n "$saved_trap" ]] || return 0
  (
    trap - EXIT HUP INT TERM
    eval "$saved_trap"
    exit "$exit_status"
  ) || true
}

internal_transaction_rollback() {
  local rollback_ok=true

  if [[ -z "$INTERNAL_TRANSACTION_ROLLBACK_SOURCE" ||
        ! -f "$INTERNAL_TRANSACTION_ROLLBACK_SOURCE" ||
        -L "$INTERNAL_TRANSACTION_ROLLBACK_SOURCE" ]]; then
    warn "Automatic rollback is unavailable because the pre-operation icon could not be preserved."
    return 1
  fi

  if [[ "$INTERNAL_TRANSACTION_KIND" == restore ]]; then
    warn "Internal restore failed; putting the pre-restore icon back."
  else
    warn "Internal apply failed; restoring the icon from immediately before this operation."
  fi

  strategy_internal_icns_atomic_copy \
    "$INTERNAL_TRANSACTION_ROLLBACK_SOURCE" \
    "$INTERNAL_TRANSACTION_TARGET" || rollback_ok=false

  if [[ "$INTERNAL_TRANSACTION_REMOVE_NEW_BACKUP" == true &&
        -n "$INTERNAL_TRANSACTION_BACKUP" ]]; then
    if loose_icon_path_is_safe \
      "$INTERNAL_TRANSACTION_RESOURCES_DIR" \
      "$INTERNAL_TRANSACTION_BACKUP" \
      true; then
      /bin/rm -f -- "$INTERNAL_TRANSACTION_BACKUP" || rollback_ok=false
    else
      rollback_ok=false
    fi
  fi

  touch_app_bundle "$INTERNAL_TRANSACTION_APP_PATH" || rollback_ok=false
  resign_app_bundle "$INTERNAL_TRANSACTION_APP_PATH" || rollback_ok=false

  if [[ "$rollback_ok" != true ]]; then
    warn "Rollback could not be fully verified; the app may still be modified or invalidly signed. Reinstall it from its trusted source before launching it."
    return 1
  fi
  warn "The pre-operation icon state was restored and the bundle was strictly verified."
}

internal_transaction_cleanup_rollback_source() {
  local rollback_source="$INTERNAL_TRANSACTION_ROLLBACK_SOURCE"

  [[ -n "$rollback_source" && -f "$rollback_source" && ! -L "$rollback_source" ]] || return 0
  /bin/rm -f -- "$rollback_source"
}

internal_transaction_exit_handler() {
  local exit_status="${1:-1}"
  local saved_exit_trap="$INTERNAL_TRANSACTION_SAVED_EXIT_TRAP"

  trap - EXIT
  trap '' HUP INT TERM
  if [[ "$INTERNAL_TRANSACTION_ACTIVE" == true && "$INTERNAL_TRANSACTION_DIRTY" == true ]]; then
    internal_transaction_rollback || true
  fi
  internal_transaction_cleanup_rollback_source || true
  INTERNAL_TRANSACTION_ACTIVE=false
  INTERNAL_TRANSACTION_SAVED_EXIT_TRAP="$saved_exit_trap"
  internal_transaction_run_saved_exit_trap "$exit_status"
  return "$exit_status"
}

internal_transaction_begin() {
  local kind="$1"
  local rollback_source="$2"

  INTERNAL_TRANSACTION_KIND="$kind"
  INTERNAL_TRANSACTION_APP_PATH="$APP_PATH"
  INTERNAL_TRANSACTION_RESOURCES_DIR="$APP_RESOURCES_DIR"
  INTERNAL_TRANSACTION_TARGET="$APP_ICON_TARGET"
  INTERNAL_TRANSACTION_BACKUP="$APP_ICON_BACKUP"
  INTERNAL_TRANSACTION_ROLLBACK_SOURCE="$rollback_source"
  INTERNAL_TRANSACTION_REMOVE_NEW_BACKUP=false
  INTERNAL_TRANSACTION_DIRTY=false
  INTERNAL_TRANSACTION_INTERRUPT_STATUS=0

  INTERNAL_TRANSACTION_SAVED_EXIT_TRAP="$(trap -p EXIT)"
  INTERNAL_TRANSACTION_SAVED_HUP_TRAP="$(trap -p HUP)"
  INTERNAL_TRANSACTION_SAVED_INT_TRAP="$(trap -p INT)"
  INTERNAL_TRANSACTION_SAVED_TERM_TRAP="$(trap -p TERM)"
  INTERNAL_TRANSACTION_ACTIVE=true

  trap 'internal_transaction_exit_handler "$?"' EXIT
  trap 'INTERNAL_TRANSACTION_INTERRUPT_STATUS=129' HUP
  trap 'INTERNAL_TRANSACTION_INTERRUPT_STATUS=130' INT
  trap 'INTERNAL_TRANSACTION_INTERRUPT_STATUS=143' TERM
}

internal_transaction_abort() {
  local requested_status="${1:-1}"
  local final_status="$requested_status"

  [[ "$INTERNAL_TRANSACTION_INTERRUPT_STATUS" -eq 0 ]] || final_status="$INTERNAL_TRANSACTION_INTERRUPT_STATUS"
  if [[ "$INTERNAL_TRANSACTION_ACTIVE" == true && "$INTERNAL_TRANSACTION_DIRTY" == true ]]; then
    internal_transaction_rollback || true
  fi
  [[ "$INTERNAL_TRANSACTION_INTERRUPT_STATUS" -eq 0 ]] || final_status="$INTERNAL_TRANSACTION_INTERRUPT_STATUS"
  internal_transaction_cleanup_rollback_source || true
  INTERNAL_TRANSACTION_ACTIVE=false
  internal_transaction_restore_traps
  return "$final_status"
}

internal_transaction_finish() {
  local final_status="$INTERNAL_TRANSACTION_INTERRUPT_STATUS"

  if [[ "$final_status" -ne 0 ]]; then
    local abort_status=0
    internal_transaction_abort "$final_status" || abort_status=$?
    return "$abort_status"
  fi
  internal_transaction_cleanup_rollback_source || true
  INTERNAL_TRANSACTION_ACTIVE=false
  internal_transaction_restore_traps
  return 0
}

strategy_internal_icns_apply() {
  local icon_file="$1"
  local replacement_checksum
  local rollback_file=""
  local temp_root=""
  local target_checksum
  local transaction_status=0

  INTERNAL_APPLY_CHANGED=false

  require_app_bundle_path "$APP_PATH" || return 1
  validate_icns_file "$icon_file" || return 1
  [[ "$APP_USES_ASSET_CATALOG" != true ]] || {
    fail "internal-icns does not support asset-catalog applications" || return 1
  }
  require_nonempty_path "Loose icon target path" "$APP_ICON_TARGET" || return 1
  require_existing_file_path "Loose icon target" "$APP_ICON_TARGET" || return 1
  require_nonempty_path "Backup icon path" "$APP_ICON_BACKUP" || return 1
  require_safe_loose_icon_path "Loose icon target" "$APP_RESOURCES_DIR" "$APP_ICON_TARGET" || return 1
  require_safe_loose_icon_path "Backup icon path" "$APP_RESOURCES_DIR" "$APP_ICON_BACKUP" true || return 1
  require_safe_mutable_app_info_plist "$APP_PATH" || return 1
  collect_internal_backups || return 1
  [[ "${#INTERNAL_BACKUPS[@]}" -le 1 ]] || {
    fail "Multiple internal icon backups found; refusing to create an ambiguous restore state" || return 1
  }
  if [[ "${#INTERNAL_BACKUPS[@]}" -eq 1 ]]; then
    internal_backup_matches_target "${INTERNAL_BACKUPS[0]}" "$APP_ICON_TARGET" || {
      fail "The existing internal backup does not match the resolved icon target: ${INTERNAL_BACKUPS[0]}" || return 1
    }
    APP_ICON_BACKUP="${INTERNAL_BACKUPS[0]}"
    validate_icns_file "$APP_ICON_BACKUP" || return 1
  fi
  strategy_internal_icns_require_writable || return 1
  require_tool "$CODESIGN_BIN" "Missing required tool: codesign" || return 1

  replacement_checksum="$(shasum -a 256 "$icon_file" | awk '{print $1}')"
  target_checksum="$(shasum -a 256 "$APP_ICON_TARGET" | awk '{print $1}')"
  if [[ "$replacement_checksum" == "$target_checksum" ]]; then
    note "The app's internal icon already matches $icon_file"
    return 0
  fi

  INTERNAL_APPLY_CHANGED=true

  warn "internal-icns modifies the app bundle and replaces its existing signature with an ad hoc signature."
  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    if [[ ! -f "$APP_ICON_BACKUP" ]]; then
      run_cmd "$CP_BIN" "$APP_ICON_TARGET" "$APP_ICON_BACKUP" || return 1
    fi
    run_cmd "$CP_BIN" "$icon_file" "$APP_ICON_TARGET" || return 1
    touch_app_bundle "$APP_PATH" || return 1
    resign_app_bundle "$APP_PATH" || return 1
    return 0
  fi

  temp_root="$(iconforge_temp_root)"
  rollback_file="$(mktemp "${temp_root%/}/iconforge-internal-rollback.XXXXXX")" || {
    fail "Could not preserve the pre-operation icon under $temp_root"
    return 1
  }
  internal_transaction_begin apply "$rollback_file"
  if ! "$CP_BIN" -p "$APP_ICON_TARGET" "$rollback_file"; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi
  if [[ "$INTERNAL_TRANSACTION_INTERRUPT_STATUS" -ne 0 ]]; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi
  if [[ ! -f "$APP_ICON_BACKUP" ]]; then
    INTERNAL_TRANSACTION_DIRTY=true
    if ! strategy_internal_icns_atomic_copy "$APP_ICON_TARGET" "$APP_ICON_BACKUP" false; then
      internal_transaction_abort 1 || transaction_status=$?
      return "$transaction_status"
    fi
    INTERNAL_TRANSACTION_REMOVE_NEW_BACKUP=true
    if [[ "$INTERNAL_TRANSACTION_INTERRUPT_STATUS" -ne 0 ]]; then
      internal_transaction_abort 1 || transaction_status=$?
      return "$transaction_status"
    fi
  fi
  INTERNAL_TRANSACTION_DIRTY=true
  if ! strategy_internal_icns_atomic_copy "$icon_file" "$APP_ICON_TARGET"; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi
  if [[ "$INTERNAL_TRANSACTION_INTERRUPT_STATUS" -ne 0 ]]; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi

  if ! touch_app_bundle "$APP_PATH"; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi
  if [[ "$INTERNAL_TRANSACTION_INTERRUPT_STATUS" -ne 0 ]]; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi
  if ! resign_app_bundle "$APP_PATH"; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi
  if [[ "$INTERNAL_TRANSACTION_INTERRUPT_STATUS" -ne 0 ]]; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi

  internal_transaction_finish || transaction_status=$?
  return "$transaction_status"
}
