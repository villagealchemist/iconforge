#!/usr/bin/env bash

inspect_help() {
  cat <<EOF
Usage:
  iconforge inspect <app>

Inspect an app bundle's icon-related metadata and explain whether loose .icns
replacement is likely to work.
EOF
}

apply_help() {
  cat <<EOF
Usage:
  iconforge apply
  iconforge apply --all
  iconforge apply <managed-key>
  iconforge apply <app> --icon <file.icns> [--strategy <auto|internal-icns|fileicon>] [--nuke] [--force-asset] [--dry-run]

\`apply\` performs app-bundle mutation. Asset-catalog-backed apps are
refused by default. Use --force-asset to override.

Reconciliation flags:
      --all             Reconcile the complete managed icon library
      --icon-root PATH  Override the managed icon library root
      --verbose         Print per-entry reconciliation details
EOF
}

restore_help() {
  cat <<EOF
Usage:
  iconforge restore <app> [--nuke] [--dry-run]

Restore the original icon from the *_ugly.icns backup created by apply.
For apps changed with the fileicon strategy, remove the file-level custom icon.
EOF
}

nuke_help() {
  cat <<EOF
Usage:
  iconforge nuke [app] [--dry-run]

Clear user-level icon caches and restart Finder, Dock, and iconservicesagent.
If an app is provided, its bundle and Info.plist are touched first.
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

  if [[ -n "$APP_ICON_TARGET" ]]; then
    printf 'Resolved loose icon: %s\n' "$APP_ICON_TARGET"
  else
    printf 'Resolved loose icon: (not found)\n'
  fi

  printf 'Appears asset catalog backed: %s\n' "$([[ "$APP_USES_ASSET_CATALOG" == true ]] && printf 'yes' || printf 'no')"

  if [[ -n "$APP_CF_BUNDLE_ICONS_RAW" ]]; then
    printf 'CFBundleIcons:\n%s\n' "$APP_CF_BUNDLE_ICONS_RAW"
  else
    printf 'CFBundleIcons: (none)\n'
  fi

  if [[ "$APP_USES_ASSET_CATALOG" == true ]]; then
    printf 'Summary: This app advertises an asset-catalog icon. Replacing a loose .icns may have no visible effect.\n'
  elif [[ -n "$APP_ICON_TARGET" ]]; then
    printf 'Summary: This app exposes a loose .icns target and is a good candidate for icon replacement.\n'
  else
    printf 'Summary: No clear loose .icns target was found. Manual inspection may be required.\n'
  fi
}

cmd_inspect() {
  [[ $# -gt 0 ]] || { inspect_help; return 1; }
  case "${1:-}" in
    -h|--help)
      inspect_help
      return 0
      ;;
  esac

  inspect_app_metadata "$1" || return 1
  print_inspect_summary
}

icon_file_checksum() {
  local icon_file="$1"

  require_existing_file_path "Icon file" "$icon_file" || return 1
  shasum -a 256 "$icon_file" | awk '{print $1}'
}

inspected_app_icon_matches() {
  local icon_file="$1"
  local strategy_name="$2"
  local replacement_checksum=""
  local target_checksum=""

  case "$strategy_name" in
    internal-icns)
      require_existing_file_path "Loose icon target" "$APP_ICON_TARGET" || return 1
      replacement_checksum="$(icon_file_checksum "$icon_file")" || return 1
      target_checksum="$(icon_file_checksum "$APP_ICON_TARGET")" || return 1
      [[ "$replacement_checksum" == "$target_checksum" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

apply_to_inspected_app() {
  local icon_file="$1"
  local strategy_name="$2"
  local force_asset="${3:-false}"
  local no_resign="${4:-false}"

  apply_icon_with_strategy "$strategy_name" "$icon_file" "$force_asset" || return 1

  if strategy_requires_bundle_refresh "$strategy_name"; then
    touch_app_bundle "$APP_PATH" || return 1
    if [[ "$no_resign" != true ]]; then
      resign_app_bundle "$APP_PATH" || return 1
    fi
  fi

  return 0
}

print_explicit_apply_result() {
  local selected_strategy="$1"
  local do_nuke="$2"
  local no_resign="$3"

  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    printf 'Strategy: %s\n' "$selected_strategy"
    printf 'Planned icon target: %s\n' "$APP_ICON_TARGET"
    printf 'Planned backup path: %s\n' "$APP_ICON_BACKUP"
    if strategy_requires_bundle_refresh "$selected_strategy" && [[ "$no_resign" != true ]]; then
      printf 'Planned re-sign: %s\n' "$APP_PATH"
    fi
    if [[ "$do_nuke" == true ]]; then
      printf 'Planned cache refresh: yes\n'
    fi
  else
    printf 'Strategy: %s\n' "$selected_strategy"
    printf 'Applied icon: %s\n' "$APP_ICON_TARGET"
    printf 'Backup icon: %s\n' "$APP_ICON_BACKUP"
    if strategy_requires_bundle_refresh "$selected_strategy" && [[ "$no_resign" != true ]]; then
      printf 'Re-signed: %s\n' "$APP_PATH"
    fi
    if [[ "$do_nuke" == true ]]; then
      printf 'Cache refresh: requested\n'
    fi
  fi

  return 0
}

RECONCILE_LAST_STATUS=""
RECONCILE_LAST_MESSAGE=""
RECONCILE_LAST_CHANGED=false

reconcile_reset_last_result() {
  RECONCILE_LAST_STATUS=""
  RECONCILE_LAST_MESSAGE=""
  RECONCILE_LAST_CHANGED=false
}

reconcile_note_entry() {
  local verbose="$1"
  local key="$2"
  local status="$3"
  local message="${4:-}"

  [[ "$verbose" == true ]] || return 0

  if [[ -n "$message" ]]; then
    printf '%s: %s (%s)\n' "$key" "$status" "$message"
  else
    printf '%s: %s\n' "$key" "$status"
  fi
}

reconcile_capture_or_print_log() {
  local verbose="$1"
  local log_file="$2"

  [[ -f "$log_file" ]] || return 0
  if [[ "$verbose" == true ]]; then
    cat "$log_file"
  fi
}

reconcile_managed_entry() {
  local icon_root="$1"
  local key="$2"
  local strategy_arg="$3"
  local force_asset="$4"
  local no_resign="$5"
  local verbose="$6"
  local log_file
  local configured_strategy=""
  local effective_strategy=""
  local selected_strategy=""
  local matched_app_path=""

  reconcile_reset_last_result
  log_file="$(mktemp -t iconforge-reconcile-entry.XXXXXX)"
  trap '[[ -n "${log_file:-}" ]] && /bin/rm -f "${log_file:-}"' RETURN

  resolve_icon_library_entry "$icon_root" "$key" || true

  if config_is_excluded "$key"; then
    RECONCILE_LAST_STATUS="skipped"
    RECONCILE_LAST_MESSAGE="excluded by configuration"
    reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
    return 0
  fi

  case "$ICON_LIBRARY_RESOLUTION_STATUS" in
    ready)
      ;;
    needs-forge)
      RECONCILE_LAST_STATUS="needs-forge"
      RECONCILE_LAST_MESSAGE="$ICON_LIBRARY_RESOLUTION_MESSAGE"
      reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
      return 0
      ;;
    ambiguous-icns|ambiguous-png|missing-icon|missing-directory)
      RECONCILE_LAST_STATUS="failed"
      RECONCILE_LAST_MESSAGE="$ICON_LIBRARY_RESOLUTION_MESSAGE"
      reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
      return 0
      ;;
    *)
      RECONCILE_LAST_STATUS="failed"
      RECONCILE_LAST_MESSAGE="Unexpected library resolution status: $ICON_LIBRARY_RESOLUTION_STATUS"
      reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
      return 0
      ;;
  esac

  if ! match_configured_application "$key" >"$log_file" 2>&1; then
    case "$MATCH_STATUS" in
      excluded)
        RECONCILE_LAST_STATUS="skipped"
        RECONCILE_LAST_MESSAGE="$MATCH_MESSAGE"
        ;;
      ambiguous-name|ambiguous-partial)
        RECONCILE_LAST_STATUS="ambiguous"
        RECONCILE_LAST_MESSAGE="$MATCH_MESSAGE"
        ;;
      missing|missing-explicit-path)
        RECONCILE_LAST_STATUS="missing-app"
        RECONCILE_LAST_MESSAGE="$MATCH_MESSAGE"
        ;;
      *)
        RECONCILE_LAST_STATUS="failed"
        RECONCILE_LAST_MESSAGE="${MATCH_MESSAGE:-Failed to match application}"
        ;;
    esac
    reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
    reconcile_capture_or_print_log "$verbose" "$log_file"
    return 0
  fi

  matched_app_path="$(discovered_app_path "$MATCH_RECORD")"

  if ! inspect_app_metadata "$matched_app_path" >"$log_file" 2>&1; then
    RECONCILE_LAST_STATUS="failed"
    RECONCILE_LAST_MESSAGE="Failed to inspect matched application"
    reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
    reconcile_capture_or_print_log "$verbose" "$log_file"
    return 0
  fi

  configured_strategy="$(config_lookup_value "$key" ICONFORGE_CONFIG_APP_STRATEGIES || true)"
  effective_strategy="$strategy_arg"
  if [[ "$effective_strategy" == "auto" && -n "$configured_strategy" ]]; then
    effective_strategy="$configured_strategy"
  fi

  if ! selected_strategy="$(select_apply_strategy "$effective_strategy" 2>"$log_file")"; then
    RECONCILE_LAST_STATUS="failed"
    RECONCILE_LAST_MESSAGE="Strategy selection failed"
    reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
    reconcile_capture_or_print_log "$verbose" "$log_file"
    return 0
  fi

  if inspected_app_icon_matches "$ICON_LIBRARY_RESOLVED_ICNS" "$selected_strategy" >"$log_file" 2>&1; then
    RECONCILE_LAST_STATUS="already-correct"
    RECONCILE_LAST_MESSAGE="$selected_strategy"
    reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
    return 0
  fi

  : > "$log_file"
  if ! apply_to_inspected_app "$ICON_LIBRARY_RESOLVED_ICNS" "$selected_strategy" "$force_asset" "$no_resign" >"$log_file" 2>&1; then
    RECONCILE_LAST_STATUS="failed"
    RECONCILE_LAST_MESSAGE="Apply failed"
    reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
    reconcile_capture_or_print_log "$verbose" "$log_file"
    return 0
  fi

  RECONCILE_LAST_STATUS="applied"
  RECONCILE_LAST_MESSAGE="$selected_strategy"
  RECONCILE_LAST_CHANGED=true
  reconcile_note_entry "$verbose" "$key" "$RECONCILE_LAST_STATUS" "$RECONCILE_LAST_MESSAGE"
  return 0
}

print_reconciliation_summary() {
  local applied="$1"
  local already_correct="$2"
  local missing_apps="$3"
  local ambiguous_matches="$4"
  local needs_forge="$5"
  local failed="$6"

  printf 'IconForge reconciliation\n\n'
  printf 'Applied: %s\n' "$applied"
  printf 'Already correct: %s\n' "$already_correct"
  printf 'Missing applications: %s\n' "$missing_apps"
  printf 'Ambiguous matches: %s\n' "$ambiguous_matches"
  printf 'Needs forge: %s\n' "$needs_forge"
  printf 'Failed: %s\n' "$failed"
}

cmd_apply_reconcile() {
  local managed_key="${1:-}"
  local cli_icon_root="${2:-}"
  local strategy_arg="${3:-auto}"
  local force_asset="${4:-false}"
  local no_resign="${5:-false}"
  local verbose="${6:-false}"
  local icon_root=""
  local key
  local applied=0
  local already_correct=0
  local missing_apps=0
  local ambiguous_matches=0
  local needs_forge=0
  local failed=0
  local changed_any=false
  local selected_keys=()

  config_load || return 1
  icon_root="$(resolve_icon_root "$cli_icon_root")"
  scan_icon_library "$icon_root" || return 1
  discover_applications

  if [[ -n "$managed_key" ]]; then
    selected_keys=("$managed_key")
  else
    for key in "${ICON_LIBRARY_KEYS[@]+"${ICON_LIBRARY_KEYS[@]}"}"; do
      selected_keys+=("$key")
    done
  fi

  if [[ "${#selected_keys[@]}" -eq 0 ]]; then
    fail "No managed icon entries were found under $icon_root" || return 1
  fi

  for key in "${selected_keys[@]+"${selected_keys[@]}"}"; do
    reconcile_managed_entry "$icon_root" "$key" "$strategy_arg" "$force_asset" "$no_resign" "$verbose"
    case "$RECONCILE_LAST_STATUS" in
      applied)
        applied=$((applied + 1))
        changed_any=true
        ;;
      already-correct)
        already_correct=$((already_correct + 1))
        ;;
      missing-app)
        missing_apps=$((missing_apps + 1))
        ;;
      ambiguous)
        ambiguous_matches=$((ambiguous_matches + 1))
        ;;
      needs-forge)
        needs_forge=$((needs_forge + 1))
        ;;
      failed)
        failed=$((failed + 1))
        ;;
      skipped)
        ;;
    esac
  done

  if [[ "$changed_any" == true && "$ICONFORGE_DRY_RUN" != true ]]; then
    if [[ "$verbose" == true ]]; then
      printf 'Refreshing icon caches once after reconciliation\n'
    fi
    cmd_nuke >/dev/null
  fi

  print_reconciliation_summary "$applied" "$already_correct" "$missing_apps" "$ambiguous_matches" "$needs_forge" "$failed"

  [[ "$failed" -eq 0 ]]
}

cmd_apply() {
  local app_arg=""
  local icon_file=""
  local icon_flag_provided=false
  local icon_root_arg=""
  local strategy_arg="auto"
  local selected_strategy=""
  local apply_all=false
  local do_nuke=false
  local force_asset=false
  local no_resign=false
  local verbose=false
  local nuke_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --icon)
        icon_flag_provided=true
        icon_file="$2"
        shift 2
        ;;
      --strategy)
        strategy_arg="$2"
        shift 2
        ;;
      --icon-root)
        icon_root_arg="$2"
        shift 2
        ;;
      --all)
        apply_all=true
        shift
        ;;
      --nuke)
        do_nuke=true
        shift
        ;;
      --force-asset)
        force_asset=true
        shift
        ;;
      --dry-run)
        ICONFORGE_DRY_RUN=true
        shift
        ;;
      --verbose)
        verbose=true
        shift
        ;;
      --no-resign)
        no_resign=true
        shift
        ;;
      -h|--help)
        apply_help
        return 0
        ;;
      -*)
        fail "Unknown apply flag: $1" || return 1
        ;;
      *)
        if [[ -z "$app_arg" ]]; then
          app_arg="$1"
        else
          fail "Unexpected argument: $1" || return 1
        fi
        shift
        ;;
    esac
  done

  if [[ "$icon_flag_provided" == true ]]; then
    [[ "$apply_all" != true ]] || fail "--all cannot be combined with --icon" || return 1
    [[ -n "$app_arg" ]] || fail "apply requires an app argument" || return 1
    [[ -n "$icon_file" ]] || fail "apply requires --icon <file.icns>" || return 1

    inspect_app_metadata "$app_arg" || return 1
    selected_strategy="$(select_apply_strategy "$strategy_arg")" || return 1

    apply_to_inspected_app "$icon_file" "$selected_strategy" "$force_asset" "$no_resign" || return 1
    if [[ "$do_nuke" == true ]]; then
      [[ "$ICONFORGE_DRY_RUN" == true ]] && nuke_args+=("--dry-run")
      cmd_nuke "$APP_PATH" "${nuke_args[@]}"
    fi

    print_explicit_apply_result "$selected_strategy" "$do_nuke" "$no_resign"
    return 0
  fi

  cmd_apply_reconcile "$app_arg" "$icon_root_arg" "$strategy_arg" "$force_asset" "$no_resign" "$verbose"
}

cmd_restore() {
  local app_arg=""
  local do_nuke=false
  local no_resign=false
  local backup_file=""
  local nuke_args=()
  local restored_with_fileicon=false

  [[ $# -gt 0 ]] || { restore_help; return 1; }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --nuke)
        do_nuke=true
        shift
        ;;
      --dry-run)
        ICONFORGE_DRY_RUN=true
        shift
        ;;
      --no-resign)
        no_resign=true
        shift
        ;;
      -h|--help)
        restore_help
        return 0
        ;;
      -*)
        fail "Unknown restore flag: $1" || return 1
        ;;
      *)
        if [[ -z "$app_arg" ]]; then
          app_arg="$1"
        else
          fail "Unexpected argument: $1" || return 1
        fi
        shift
        ;;
    esac
  done

  [[ -n "$app_arg" ]] || fail "restore requires an app argument" || return 1

  inspect_app_metadata "$app_arg" || return 1
  backup_file="$(find_restore_backup || true)"

  if [[ -n "$backup_file" ]]; then
    if [[ -z "$APP_ICON_TARGET" ]]; then
      APP_ICON_TARGET="${backup_file%_ugly.icns}.icns"
      APP_ICON_BACKUP="$backup_file"
    fi

    require_existing_file_path "Backup icon file" "$backup_file" || return 1
    require_nonempty_path "Restore icon target path" "$APP_ICON_TARGET" || return 1
    run_cmd "$CP_BIN" "$backup_file" "$APP_ICON_TARGET" || return 1
    touch_app_bundle "$APP_PATH" || return 1
    if [[ "$no_resign" != true ]]; then
      resign_app_bundle "$APP_PATH" || return 1
    fi
  elif strategy_fileicon_available; then
    strategy_fileicon_restore || return 1
    restored_with_fileicon=true
  else
    fail "No *_ugly.icns backup found and fileicon is unavailable for $APP_PATH" || return 1
  fi
  if [[ "$do_nuke" == true ]]; then
    [[ "$ICONFORGE_DRY_RUN" == true ]] && nuke_args+=("--dry-run")
    cmd_nuke "$APP_PATH" "${nuke_args[@]}"
  fi

  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    if [[ "$restored_with_fileicon" == true ]]; then
      printf 'Planned removal of fileicon custom icon: %s\n' "$APP_PATH"
    else
      printf 'Planned restore target: %s\n' "$APP_ICON_TARGET"
      [[ "$no_resign" == true ]] || printf 'Planned re-sign: %s\n' "$APP_PATH"
    fi
  else
    if [[ "$restored_with_fileicon" == true ]]; then
      printf 'Removed fileicon custom icon: %s\n' "$APP_PATH"
    else
      printf 'Restored icon: %s\n' "$APP_ICON_TARGET"
      if [[ "$no_resign" != true ]]; then
        printf 'Re-signed: %s\n' "$APP_PATH"
      fi
    fi
  fi

  return 0
}

collect_nuke_targets() {
  local targets=()
  local entry
  local darwin_cache_dir

  targets+=("$HOME/Library/Caches/com.apple.iconservices.store")
  targets+=("$HOME/Library/Caches/com.apple.iconservices")

  # getconf resolves the current user's cache directory directly. Avoid walking
  # all of /private/var/folders, which is both slow and unnecessary.
  darwin_cache_dir="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
  if [[ -n "$darwin_cache_dir" && -d "$darwin_cache_dir" ]]; then
    for entry in "$darwin_cache_dir"/com.apple.dock.iconcache "$darwin_cache_dir"/com.apple.iconservices*; do
      [[ -e "$entry" ]] && targets+=("$entry")
    done
  fi

  printf '%s\n' "${targets[@]}" | awk '!seen[$0]++'
}

cmd_nuke() {
  local app_arg=""
  local target
  local had_target=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        ICONFORGE_DRY_RUN=true
        shift
        ;;
      -h|--help)
        nuke_help
        return 0
        ;;
      -*)
        fail "Unknown nuke flag: $1" || return 1
        ;;
      *)
        if [[ -z "$app_arg" ]]; then
          app_arg="$1"
        else
          fail "Unexpected argument: $1" || return 1
        fi
        shift
        ;;
    esac
  done

  if [[ -n "$app_arg" ]]; then
    inspect_app_metadata "$app_arg" || return 1
    touch_app_bundle "$APP_PATH" || return 1
  fi

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    had_target=true
    if [[ -e "$target" || "$ICONFORGE_DRY_RUN" == true ]]; then
      run_cmd "$RM_BIN" -rf "$target"
    fi
  done < <(collect_nuke_targets)

  run_quiet_cmd "$KILLALL_BIN" Finder || true
  run_quiet_cmd "$KILLALL_BIN" Dock || true
  run_quiet_cmd "$KILLALL_BIN" iconservicesagent || true
  if command -v qlmanage >/dev/null 2>&1; then
    run_quiet_cmd qlmanage -r cache || true
  fi

  if [[ "$had_target" == false ]]; then
    note "No icon cache files were found, but Finder/Dock refresh was still attempted."
  fi

  printf 'Icon caches refreshed\n'
  if [[ -n "$app_arg" ]]; then
    printf 'Touched app: %s\n' "$APP_PATH"
  fi

  return 0
}
