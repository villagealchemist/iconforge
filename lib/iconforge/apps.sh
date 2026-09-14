#!/usr/bin/env bash

inspect_help() {
  cat <<EOF
Inspect an application bundle's icon metadata without changing it.

Usage:
  iconforge inspect <app>

Options:
  -h, --help  Show this help

Names are resolved from the current directory, ~/Applications, /Applications,
and /System/Applications. Use -- before an app name beginning with a dash.
EOF
}

apply_help() {
  cat <<EOF
Apply one icon directly or apply a directory of icons in bulk.

Usage:
  iconforge apply <app> -i <file.icns> [options]
  iconforge apply -a [directory] [options]

Options:
  -i, --icon <file>       ICNS file for a direct apply
  -a, --all               Apply all eligible ICNS files under [directory]
  -s, --strategy <name>  Direct strategy: native or internal-icns
  -n, --nuke              Run Nuke once after a successful apply
  -d, --dry-run           Validate and show work without changing anything
  -v, --verbose           Print a status line for every bulk entry
  -h, --help              Show this help

The native AppKit strategy is the default and the only bulk strategy.
internal-icns is an explicit expert operation that modifies and ad-hoc signs a
writable loose-icon app bundle. Without [directory], bulk mode uses the saved
default. Use -- before positional values beginning '-'.
EOF
}

restore_help() {
  cat <<EOF
Restore an internal icon backup and/or remove a Finder custom icon.

Usage:
  iconforge restore <app> [options]

Options:
  -n, --nuke     Run Nuke once after a successful restore
  -d, --dry-run  Validate and show work without changing anything
  -h, --help     Show this help
EOF
}

nuke_help() {
  cat <<EOF
Refresh current-user macOS icon caches.

Usage:
  iconforge nuke [app] [options]

Options:
  -d, --dry-run  Show cache and process work without changing anything
  -h, --help     Show this help

An optional app is touched before the current user's icon caches are removed.
Nuke refuses to run as root.
EOF
}

print_inspect_summary() {
  local icon_source
  icon_source="$(print_icon_source_summary)"

  printf 'App: %s\n' "$APP_PATH"
  printf 'Info.plist: %s\n' "$APP_INFO_PLIST"
  printf 'Resources: %s\n' "$APP_RESOURCES_DIR"
  printf 'Icon source: %s\n' "$icon_source"
  printf 'CFBundleIconFile: %s\n' "${APP_CF_BUNDLE_ICON_FILE:-"(none)"}"
  printf 'CFBundleIconName: %s\n' "${APP_CF_BUNDLE_ICON_NAME:-"(none)"}"
  printf 'CFBundlePrimaryIcon name: %s\n' "${APP_PRIMARY_ICON_NAME:-"(none)"}"

  if [[ "${APP_PRIMARY_ICON_FILES[0]+set}" == set ]]; then
    printf 'CFBundlePrimaryIcon files: %s\n' "$(join_by ', ' "${APP_PRIMARY_ICON_FILES[@]}")"
  else
    printf 'CFBundlePrimaryIcon files: (none)\n'
  fi
  if [[ "${APP_CAR_FILES[0]+set}" == set ]]; then
    printf 'Assets.car files: %s\n' "$(join_by ', ' "${APP_CAR_FILES[@]}")"
  else
    printf 'Assets.car files: (none)\n'
  fi
  printf 'Resolved loose icon: %s\n' "${APP_ICON_TARGET:-"(not found)"}"
  printf 'Appears asset catalog backed: %s\n' "$([[ "$APP_USES_ASSET_CATALOG" == true ]] && printf yes || printf no)"
}

cmd_inspect() {
  local app_arg=""
  local app_seen=false
  local options_done=false

  while [[ $# -gt 0 ]]; do
    if [[ "$options_done" != true ]]; then
      case "$1" in
        --) options_done=true; shift; continue ;;
        -h|--help) inspect_help; return 0 ;;
        -*) usage_fail "Unknown inspect flag: $1" || return 2 ;;
      esac
    fi
    [[ "$app_seen" != true ]] || { usage_fail "Unexpected inspect argument: $1"; return 2; }
    [[ -n "$1" ]] || { usage_fail "Inspect app must not be empty"; return 2; }
    app_arg="$1"
    app_seen=true
    shift
  done

  [[ "$app_seen" == true ]] || { inspect_help; return 2; }
  inspect_app_metadata "$app_arg" || return 1
  print_inspect_summary
}

print_direct_apply_result() {
  local strategy_name="$1"
  local do_nuke="$2"
  printf 'Strategy: %s\n' "$strategy_name"
  if [[ "$strategy_name" == internal-icns && "$INTERNAL_APPLY_CHANGED" != true ]]; then
    printf 'Internal icon already matches: %s\n' "$APP_ICON_TARGET"
    [[ "$do_nuke" != true ]] || printf 'Nuke: %s\n' "$([[ "$ICONFORGE_DRY_RUN" == true ]] && printf planned || printf complete)"
    return 0
  fi
  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    if [[ "$strategy_name" == native ]]; then
      printf 'Planned Finder custom icon target: %s\n' "$APP_PATH"
    else
      printf 'Planned internal icon target: %s\n' "$APP_ICON_TARGET"
      printf 'Planned preserved backup: %s\n' "$APP_ICON_BACKUP"
      printf 'Planned ad hoc re-sign: %s\n' "$APP_PATH"
    fi
    [[ "$do_nuke" != true ]] || printf 'Planned Nuke: yes\n'
  else
    if [[ "$strategy_name" == native ]]; then
      printf 'Applied Finder custom icon: %s\n' "$APP_PATH"
    else
      printf 'Applied internal icon: %s\n' "$APP_ICON_TARGET"
      printf 'Preserved backup: %s\n' "$APP_ICON_BACKUP"
      printf 'Ad hoc re-signed: %s\n' "$APP_PATH"
    fi
    [[ "$do_nuke" != true ]] || printf 'Nuke: complete\n'
  fi
}

run_requested_nuke() {
  local do_nuke="$1"
  local app_path="$2"
  [[ "$do_nuke" == true ]] || return 0
  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    cmd_nuke "$app_path" -d
  else
    cmd_nuke "$app_path"
  fi
}

NUKE_USER_HOME=""

nuke_validate_current_user() {
  NUKE_USER_HOME=""
  [[ "$EUID" -ne 0 ]] || {
    fail "Nuke refuses to run as root because it operates on the current user's caches" || return 1
  }
  require_native_icon_helper || return 1
  NUKE_USER_HOME="$("$ICONFORGE_NATIVE_ICON" user-home 2>/dev/null)" || {
    fail "Nuke could not resolve the current account's home directory" || return 1
  }
  [[ -n "$NUKE_USER_HOME" && "$NUKE_USER_HOME" == /* && "$NUKE_USER_HOME" != / &&
     "$NUKE_USER_HOME" != *$'\n'* && -d "$NUKE_USER_HOME" ]] || {
    NUKE_USER_HOME=""
    fail "Nuke received an unsafe current-account home directory" || return 1
  }
}

BULK_STATUSES=()
BULK_APP_PATHS=()
BULK_MESSAGES=()
BULK_CANDIDATE_STARTS=()
BULK_CANDIDATE_COUNTS=()
BULK_CANDIDATE_PATHS=()

bulk_fail_duplicate_keys() {
  local i
  local j
  for ((i = 0; i < ${#ICON_LIBRARY_NORMALIZED_KEYS[@]}; i++)); do
    [[ -n "${ICON_LIBRARY_NORMALIZED_KEYS[$i]}" ]] || {
      fail "Icon filename is empty after normalization: ${ICON_LIBRARY_FILES[$i]}"
      return 1
    }
    for ((j = i + 1; j < ${#ICON_LIBRARY_NORMALIZED_KEYS[@]}; j++)); do
      if [[ "${ICON_LIBRARY_NORMALIZED_KEYS[$i]}" == "${ICON_LIBRARY_NORMALIZED_KEYS[$j]}" ]]; then
        fail "Duplicate normalized icon key '${ICON_LIBRARY_NORMALIZED_KEYS[$i]}': ${ICON_LIBRARY_FILES[$i]} and ${ICON_LIBRARY_FILES[$j]}"
        return 1
      fi
    done
  done
}

bulk_validate_icons() {
  local icon_file
  for icon_file in "${ICON_LIBRARY_FILES[@]+"${ICON_LIBRARY_FILES[@]}"}"; do
    validate_icns_file "$icon_file" || return 1
  done
}

bulk_match_icons() {
  local i
  local key
  local status
  local path
  local j
  local candidate_record
  local candidate_start
  local candidate_count

  BULK_STATUSES=()
  BULK_APP_PATHS=()
  BULK_MESSAGES=()
  BULK_CANDIDATE_STARTS=()
  BULK_CANDIDATE_COUNTS=()
  BULK_CANDIDATE_PATHS=()
  discover_applications

  for ((i = 0; i < ${#ICON_LIBRARY_FILES[@]}; i++)); do
    key="${ICON_LIBRARY_KEYS[$i]}"
    candidate_start="${#BULK_CANDIDATE_PATHS[@]}"
    candidate_count=0
    if match_application_name "$key"; then
      path="$(discovered_app_path "$MATCH_RECORD")"
      if [[ "$MATCH_STATUS" == matched-partial ]]; then
        status="suggested"
        BULK_MESSAGES+=("unique partial suggestion")
      else
        status="ready"
        BULK_MESSAGES+=("exact match")
      fi
      BULK_STATUSES+=("$status")
      BULK_APP_PATHS+=("$path")
    else
      case "$MATCH_STATUS" in
        ambiguous-exact|ambiguous-partial)
          BULK_STATUSES+=("ambiguous")
          for candidate_record in "${MATCH_CANDIDATES[@]+"${MATCH_CANDIDATES[@]}"}"; do
            BULK_CANDIDATE_PATHS+=("$(discovered_app_path "$candidate_record")")
            candidate_count=$((candidate_count + 1))
          done
          ;;
        *)
          BULK_STATUSES+=("unmatched")
          ;;
      esac
      BULK_APP_PATHS+=("")
      BULK_MESSAGES+=("${MATCH_MESSAGE:-no installed application matched}")
    fi
    BULK_CANDIDATE_STARTS+=("$candidate_start")
    BULK_CANDIDATE_COUNTS+=("$candidate_count")
  done

  # Two keys targeting one app is structural ambiguity, including suggested
  # partial matches, and must fail before any write.
  for ((i = 0; i < ${#BULK_APP_PATHS[@]}; i++)); do
    [[ -n "${BULK_APP_PATHS[$i]}" ]] || continue
    for ((j = i + 1; j < ${#BULK_APP_PATHS[@]}; j++)); do
      [[ -n "${BULK_APP_PATHS[$j]}" ]] || continue
      if [[ "${BULK_APP_PATHS[$i]}" == "${BULK_APP_PATHS[$j]}" ]]; then
        fail "Two icon keys resolve to the same app: ${ICON_LIBRARY_KEYS[$i]} and ${ICON_LIBRARY_KEYS[$j]} -> ${BULK_APP_PATHS[$i]}"
        return 1
      fi
    done
  done
}

bulk_report_ambiguity() {
  local index="$1"
  local start="${BULK_CANDIDATE_STARTS[$index]:-0}"
  local count="${BULK_CANDIDATE_COUNTS[$index]:-0}"
  local candidate_index
  local candidate_path

  note "Skipped ambiguous icon '${ICON_LIBRARY_KEYS[$index]}'."
  for ((candidate_index = start; candidate_index < start + count; candidate_index++)); do
    candidate_path="${BULK_CANDIDATE_PATHS[$candidate_index]}"
    note "Retry directly: $(format_cmd iconforge apply "$candidate_path" -i "${ICON_LIBRARY_FILES[$index]}")"
  done
}

bulk_confirm_suggestions() {
  local suggested=0
  local answer=""
  local accept=false
  local i

  for ((i = 0; i < ${#BULK_STATUSES[@]}; i++)); do
    [[ "${BULK_STATUSES[$i]}" == suggested ]] || continue
    suggested=$((suggested + 1))
  done
  [[ "$suggested" -gt 0 ]] || return 0

  if iconforge_input_is_tty; then
    stderr "Unique partial application suggestions:"
    for ((i = 0; i < ${#BULK_STATUSES[@]}; i++)); do
      [[ "${BULK_STATUSES[$i]}" == suggested ]] || continue
      printf '  %s -> %s\n' "${ICON_LIBRARY_KEYS[$i]}" "${BULK_APP_PATHS[$i]}" >&2
    done
    printf 'Include all of these suggestions for this run? [y/N] ' >&2
    IFS= read -r answer || answer=""
    case "$answer" in
      y|Y|yes|YES|Yes) accept=true ;;
    esac
  fi

  for ((i = 0; i < ${#BULK_STATUSES[@]}; i++)); do
    [[ "${BULK_STATUSES[$i]}" == suggested ]] || continue
    if [[ "$accept" == true ]]; then
      BULK_STATUSES[i]="ready"
      BULK_MESSAGES[i]="confirmed partial match"
    else
      BULK_STATUSES[i]="declined"
      if iconforge_input_is_tty; then
        BULK_MESSAGES[i]="partial suggestion declined"
      else
        BULK_MESSAGES[i]="partial suggestions require a terminal; retry with the exact app name or path"
      fi
      note "Skipped partial suggestion '${ICON_LIBRARY_KEYS[$i]}' -> '${BULK_APP_PATHS[$i]}'."
      note "Retry directly: $(format_cmd iconforge apply "${BULK_APP_PATHS[$i]}" -i "${ICON_LIBRARY_FILES[$i]}")"
    fi
  done
}

bulk_print_entry() {
  local verbose="$1"
  local index="$2"
  local status="$3"
  local message="${4:-}"
  [[ "$verbose" == true ]] || return 0
  if [[ -n "$message" ]]; then
    printf '%s: %s (%s)\n' "${ICON_LIBRARY_KEYS[$index]}" "$status" "$message"
  else
    printf '%s: %s\n' "${ICON_LIBRARY_KEYS[$index]}" "$status"
  fi
}

cmd_apply_bulk() {
  local icon_root="$1"
  local do_nuke="$2"
  local verbose="$3"
  local i
  local status
  local applied=0
  local unmatched=0
  local ambiguous=0
  local declined=0
  local needs_authorization=0
  local failed=0

  require_native_icon_helper || return 1
  scan_icon_library "$icon_root" || return 1
  [[ "${#ICON_LIBRARY_FILES[@]}" -gt 0 ]] || { fail "No eligible .icns files found under: $icon_root"; return 1; }
  bulk_fail_duplicate_keys || return 1
  bulk_validate_icons || return 1
  bulk_match_icons || return 1
  bulk_confirm_suggestions

  for ((i = 0; i < ${#ICON_LIBRARY_FILES[@]}; i++)); do
    status="${BULK_STATUSES[$i]}"
    case "$status" in
      ready)
        APP_PATH="${BULK_APP_PATHS[$i]}"
        if strategy_native_icon_requires_authorization; then
          needs_authorization=$((needs_authorization + 1))
          bulk_print_entry "$verbose" "$i" "needs-authorization" "$APP_PATH"
          continue
        fi
        if strategy_native_icon_apply "${ICON_LIBRARY_FILES[$i]}"; then
          applied=$((applied + 1))
          if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
            bulk_print_entry "$verbose" "$i" "would-apply" "$APP_PATH"
          else
            bulk_print_entry "$verbose" "$i" "applied" "$APP_PATH"
          fi
        else
          failed=$((failed + 1))
          bulk_print_entry "$verbose" "$i" "failed" "$APP_PATH"
        fi
        ;;
      unmatched)
        unmatched=$((unmatched + 1))
        bulk_print_entry "$verbose" "$i" "unmatched" "${BULK_MESSAGES[$i]}"
        ;;
      ambiguous)
        ambiguous=$((ambiguous + 1))
        bulk_report_ambiguity "$i"
        bulk_print_entry "$verbose" "$i" "ambiguous" "${BULK_MESSAGES[$i]}"
        ;;
      declined)
        declined=$((declined + 1))
        bulk_print_entry "$verbose" "$i" "declined" "${BULK_MESSAGES[$i]}"
        ;;
    esac
  done

  if [[ "$applied" -gt 0 && "$do_nuke" == true ]]; then
    if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
      printf 'Planned Nuke: yes\n'
    elif ! cmd_nuke; then
      failed=$((failed + 1))
    fi
  fi

  printf 'IconForge bulk apply\n\n'
  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    printf 'Would apply: %s\n' "$applied"
  else
    printf 'Applied: %s\n' "$applied"
  fi
  printf 'Unmatched: %s\n' "$unmatched"
  printf 'Ambiguous: %s\n' "$ambiguous"
  printf 'Declined: %s\n' "$declined"
  printf 'Needs authorization: %s\n' "$needs_authorization"
  printf 'Failed: %s\n' "$failed"

  [[ "$applied" -gt 0 && "$needs_authorization" -eq 0 && "$failed" -eq 0 ]]
}

cmd_apply() {
  local app_arg=""
  local app_seen=false
  local icon_file=""
  local icon_seen=false
  local apply_all=false
  local strategy_name="native"
  local strategy_seen=false
  local do_nuke=false
  local verbose=false
  local options_done=false
  local selected_strategy

  while [[ $# -gt 0 ]]; do
    if [[ "$options_done" != true ]]; then
      case "$1" in
        --) options_done=true; shift; continue ;;
        -i|--icon)
          [[ "$icon_seen" != true ]] || { usage_fail "-i/--icon may be supplied only once"; return 2; }
          [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { usage_fail "$1 requires a .icns file"; return 2; }
          icon_seen=true; icon_file="$2"; shift 2; continue
          ;;
        -a|--all) apply_all=true; shift; continue ;;
        -s|--strategy)
          [[ "$strategy_seen" != true ]] || { usage_fail "-s/--strategy may be supplied only once"; return 2; }
          [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { usage_fail "$1 requires native or internal-icns"; return 2; }
          strategy_seen=true; strategy_name="$2"; shift 2; continue
          ;;
        -n|--nuke) do_nuke=true; shift; continue ;;
        -d|--dry-run) ICONFORGE_DRY_RUN=true; shift; continue ;;
        -v|--verbose) verbose=true; shift; continue ;;
        -h|--help) apply_help; return 0 ;;
        -*) usage_fail "Unknown apply flag: $1" || return 2 ;;
      esac
    fi

    [[ "$app_seen" != true ]] || { usage_fail "Unexpected apply argument: $1"; return 2; }
    [[ -n "$1" ]] || { usage_fail "Apply operand must not be empty"; return 2; }
    app_arg="$1"
    app_seen=true
    shift
  done

  if [[ "$apply_all" == true ]]; then
    [[ "$icon_seen" != true ]] || { usage_fail "--all cannot be combined with --icon"; return 2; }
    [[ "$strategy_seen" != true ]] || { usage_fail "--strategy is available only for direct apply"; return 2; }
    if [[ "$app_seen" != true ]]; then
      load_iconforge_config || return 1
      [[ "$ICONFORGE_HAS_DEFAULT_DIRECTORY" == true ]] || {
        usage_fail "--all requires an icon directory or a configured default-directory" || return 2
      }
      app_arg="$ICONFORGE_DEFAULT_DIRECTORY"
      app_seen=true
    fi
    [[ -d "$app_arg" ]] || { fail "Icon directory not found: $app_arg"; return 1; }
    [[ "$do_nuke" != true ]] || nuke_validate_current_user || return 1
    cmd_apply_bulk "$app_arg" "$do_nuke" "$verbose"
    return
  fi

  if [[ "$app_seen" != true && "$icon_seen" != true ]]; then
    apply_help
    return 2
  fi
  [[ "$app_seen" == true ]] || { usage_fail "apply requires an app argument"; return 2; }
  [[ "$icon_seen" == true && -n "$icon_file" ]] || { usage_fail "direct apply requires -i/--icon <file.icns>"; return 2; }
  strategy_validate_name "$strategy_name" || return $?
  [[ "$do_nuke" != true ]] || nuke_validate_current_user || return 1
  inspect_app_metadata "$app_arg" || return 1
  selected_strategy="$(select_apply_strategy "$strategy_name")" || return 1
  apply_icon_with_strategy "$selected_strategy" "$icon_file" || return $?
  run_requested_nuke "$do_nuke" "$APP_PATH" || return 1
  print_direct_apply_result "$selected_strategy" "$do_nuke"
}

collect_internal_backups() {
  INTERNAL_BACKUPS=()
  local backup
  [[ -d "$APP_RESOURCES_DIR" ]] || return 0
  while IFS= read -r backup; do
    [[ -n "$backup" ]] || continue
    require_safe_loose_icon_path "Internal backup" "$APP_RESOURCES_DIR" "$backup" || return 1
    INTERNAL_BACKUPS+=("$backup")
  done < <(find "$APP_RESOURCES_DIR" -mindepth 1 -maxdepth 1 -iname '*_ugly.icns' -print 2>/dev/null | sort)
}

restore_internal_backup() {
  local backup_file="$1"
  local target_file="${APP_ICON_TARGET:-}"
  local temp_root
  local rollback_file=""
  local transaction_status=0

  require_nonempty_path "Resolved current internal icon" "$target_file" || return 1
  require_existing_file_path "Current internal icon" "$target_file" || return 1
  require_safe_loose_icon_path "Internal backup" "$APP_RESOURCES_DIR" "$backup_file" || return 1
  require_safe_loose_icon_path "Current internal icon" "$APP_RESOURCES_DIR" "$target_file" || return 1
  require_safe_mutable_app_info_plist "$APP_PATH" || return 1
  validate_icns_file "$backup_file" || return 1
  APP_ICON_TARGET="$target_file"
  APP_ICON_BACKUP="$backup_file"
  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    printf 'Planned internal restore: %s -> %s\n' "$backup_file" "$target_file"
    printf 'Planned ad hoc re-sign: %s\n' "$APP_PATH"
    return 0
  fi

  temp_root="$(iconforge_temp_root)"
  rollback_file="$(mktemp "${temp_root%/}/iconforge-restore.XXXXXX")" || {
    fail "Could not create restore rollback file under $temp_root"; return 1;
  }
  internal_transaction_begin restore "$rollback_file"
  if ! "$CP_BIN" -p "$target_file" "$rollback_file"; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi
  if [[ "$INTERNAL_TRANSACTION_INTERRUPT_STATUS" -ne 0 ]]; then
    internal_transaction_abort 1 || transaction_status=$?
    return "$transaction_status"
  fi

  INTERNAL_TRANSACTION_DIRTY=true
  if ! strategy_internal_icns_atomic_copy "$backup_file" "$target_file"; then
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
  if [[ "$transaction_status" -ne 0 ]]; then
    return "$transaction_status"
  fi
  printf 'Restored internal icon: %s\n' "$target_file"
  printf 'Ad hoc re-signed: %s\n' "$APP_PATH"
}

cmd_restore() {
  local app_arg=""
  local app_seen=false
  local do_nuke=false
  local options_done=false
  local had_native=false
  local native_presence_status=0
  local restored_any=false

  while [[ $# -gt 0 ]]; do
    if [[ "$options_done" != true ]]; then
      case "$1" in
        --) options_done=true; shift; continue ;;
        -n|--nuke) do_nuke=true; shift; continue ;;
        -d|--dry-run) ICONFORGE_DRY_RUN=true; shift; continue ;;
        -h|--help) restore_help; return 0 ;;
        -*) usage_fail "Unknown restore flag: $1" || return 2 ;;
      esac
    fi
    [[ "$app_seen" != true ]] || { usage_fail "Unexpected restore argument: $1"; return 2; }
    [[ -n "$1" ]] || { usage_fail "Restore app must not be empty"; return 2; }
    app_arg="$1"
    app_seen=true
    shift
  done

  [[ "$app_seen" == true ]] || { restore_help; return 2; }
  [[ "$do_nuke" != true ]] || nuke_validate_current_user || return 1
  inspect_app_metadata "$app_arg" || return 1
  require_native_icon_helper || return 1
  collect_internal_backups || return 1
  [[ "${#INTERNAL_BACKUPS[@]}" -le 1 ]] || {
    fail "Multiple internal icon backups found; refusing an ambiguous restore"
    return 1
  }
  if strategy_native_icon_is_present; then
    had_native=true
  else
    native_presence_status=$?
    if [[ "$native_presence_status" -ne 1 ]]; then
      fail "Native helper could not determine whether $APP_PATH has a Finder custom icon (status $native_presence_status)" || true
      return 1
    fi
  fi
  [[ "${#INTERNAL_BACKUPS[@]}" -eq 1 || "$had_native" == true ]] || {
    fail "No Finder custom icon or unambiguous internal backup exists for $APP_PATH"
    return 1
  }

  if [[ "${#INTERNAL_BACKUPS[@]}" -eq 1 ]]; then
    APP_ICON_BACKUP="${INTERNAL_BACKUPS[0]}"
    [[ -n "$APP_ICON_TARGET" ]] || {
      fail "Could not resolve the live internal icon that corresponds to the backup" || return 1
    }
    internal_backup_matches_target "$APP_ICON_BACKUP" "$APP_ICON_TARGET" || {
      fail "The internal backup does not correspond to the resolved app icon: $APP_ICON_BACKUP" || return 1
    }
    require_existing_file_path "Current internal icon" "$APP_ICON_TARGET" || return 1
    require_safe_mutable_app_info_plist "$APP_PATH" || return 1
    strategy_internal_icns_is_writable || {
      fail "Internal icon restore requires write access to the app bundle: $APP_PATH"
      return 1
    }
    require_tool "$CODESIGN_BIN" "Missing required tool: codesign" || return 1
  fi
  if [[ "$had_native" == true && "$ICONFORGE_DRY_RUN" != true ]] && strategy_native_icon_requires_authorization; then
    strategy_native_icon_authorization_error
    return 1
  fi

  if [[ "${#INTERNAL_BACKUPS[@]}" -eq 1 ]]; then
    restore_internal_backup "${INTERNAL_BACKUPS[0]}" || return $?
    restored_any=true
  fi
  if [[ "$had_native" == true ]]; then
    strategy_native_icon_restore || return 1
    if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
      printf 'Planned removal of Finder custom icon: %s\n' "$APP_PATH"
    else
      printf 'Removed Finder custom icon: %s\n' "$APP_PATH"
    fi
    restored_any=true
  fi

  [[ "$restored_any" == true ]] || return 1
  run_requested_nuke "$do_nuke" "$APP_PATH" || return 1
}

collect_nuke_targets() {
  local darwin_cache_dir=""
  local entry

  [[ -n "$NUKE_USER_HOME" ]] || {
    fail "Nuke current-account home was not initialized" || return 1
  }
  printf '%s\n' "$NUKE_USER_HOME/Library/Caches/com.apple.iconservices.store"
  printf '%s\n' "$NUKE_USER_HOME/Library/Caches/com.apple.iconservices"
  darwin_cache_dir="$(/usr/bin/getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
  if [[ -n "$darwin_cache_dir" && -d "$darwin_cache_dir" ]]; then
    darwin_cache_dir="$(realpath -- "$darwin_cache_dir")" || return 1
    for entry in "$darwin_cache_dir"/com.apple.dock.iconcache "$darwin_cache_dir"/com.apple.iconservices*; do
      [[ -e "$entry" ]] && printf '%s\n' "$entry"
    done
  fi
}

cmd_nuke() {
  local app_arg=""
  local app_seen=false
  local options_done=false
  local target

  while [[ $# -gt 0 ]]; do
    if [[ "$options_done" != true ]]; then
      case "$1" in
        --) options_done=true; shift; continue ;;
        -d|--dry-run) ICONFORGE_DRY_RUN=true; shift; continue ;;
        -h|--help) nuke_help; return 0 ;;
        -*) usage_fail "Unknown nuke flag: $1" || return 2 ;;
      esac
    fi
    [[ "$app_seen" != true ]] || { usage_fail "Unexpected nuke argument: $1"; return 2; }
    [[ -n "$1" ]] || { usage_fail "Nuke app must not be empty"; return 2; }
    app_arg="$1"
    app_seen=true
    shift
  done

  nuke_validate_current_user || return 1
  if [[ "$app_seen" == true ]]; then
    inspect_app_metadata "$app_arg" || return 1
    touch_app_bundle "$APP_PATH" || return 1
  fi

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    if [[ -e "$target" || "$ICONFORGE_DRY_RUN" == true ]]; then
      run_cmd "$RM_BIN" -rf "$target" || return 1
    fi
  done < <(collect_nuke_targets | /usr/bin/awk '!seen[$0]++')

  run_quiet_cmd "$KILLALL_BIN" Finder || true
  run_quiet_cmd "$KILLALL_BIN" Dock || true
  run_quiet_cmd "$KILLALL_BIN" iconservicesagent || true
  if command -v qlmanage >/dev/null 2>&1; then
    run_quiet_cmd qlmanage -r cache || true
  fi

  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    printf 'Planned current-user icon cache refresh\n'
    [[ -z "$app_arg" ]] || printf 'Planned app touch: %s\n' "$APP_PATH"
  else
    printf 'Icon caches refreshed\n'
  [[ "$app_seen" != true ]] || printf 'Touched app: %s\n' "$APP_PATH"
  fi
}
