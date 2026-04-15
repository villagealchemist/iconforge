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
  iconforge apply <app> --icon <file.icns> [--nuke] [--force-asset] [--dry-run]

\`apply\` performs app-bundle mutation. Asset-catalog-backed apps are
refused by default. Use --force-asset to override.
EOF
}

restore_help() {
  cat <<EOF
Usage:
  iconforge restore <app> [--nuke] [--dry-run]

Restore the original icon from the *_ugly.icns backup created by apply.
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

copy_icon_into_bundle() {
  local source_icns="$1"
  local target_icns="$2"

  [[ -f "$source_icns" ]] || fail "Icon file not found: $source_icns" || return 1
  [[ "$source_icns" == *.icns ]] || fail "Icon file must be a .icns file: $source_icns" || return 1
  [[ -n "$target_icns" ]] || fail "Could not resolve target icon file inside app bundle" || return 1

  if [[ ! -f "$APP_ICON_BACKUP" ]]; then
    run_cmd cp "$target_icns" "$APP_ICON_BACKUP" || return 1
  fi

  run_cmd cp "$source_icns" "$target_icns" || return 1
}

cmd_apply() {
  local app_arg=""
  local icon_file=""
  local do_nuke=false
  local force_asset=false
  local no_resign=false
  local replacement_checksum=""
  local target_checksum=""
  local nuke_args=()

  [[ $# -gt 0 ]] || { apply_help; return 1; }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --icon)
        icon_file="$2"
        shift 2
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

  [[ -n "$app_arg" ]] || fail "apply requires an app argument" || return 1
  [[ -n "$icon_file" ]] || fail "apply requires --icon <file.icns>" || return 1

  inspect_app_metadata "$app_arg" || return 1

  if [[ "$APP_USES_ASSET_CATALOG" == true && "$force_asset" != true ]]; then
    warn "This app appears asset-catalog backed."
    warn "Replacing $APP_ICON_TARGET may have no visible effect."
    fail "Refusing icon replacement without --force-asset" || return 1
  fi

  [[ -n "$APP_ICON_TARGET" ]] || fail "No loose .icns target could be resolved for $APP_PATH" || return 1

  replacement_checksum="$(shasum -a 256 "$icon_file" | awk '{print $1}')"
  if [[ -f "$APP_ICON_TARGET" ]]; then
    target_checksum="$(shasum -a 256 "$APP_ICON_TARGET" | awk '{print $1}')"
  fi

  if [[ -n "$target_checksum" && "$replacement_checksum" == "$target_checksum" ]]; then
    note "Target icon already matches $icon_file"
  fi

  copy_icon_into_bundle "$icon_file" "$APP_ICON_TARGET" || return 1
  touch_app_bundle "$APP_PATH" || return 1
  if [[ "$no_resign" != true ]]; then
    resign_app_bundle "$APP_PATH" || return 1
  fi
  if [[ "$do_nuke" == true ]]; then
    [[ "$ICONFORGE_DRY_RUN" == true ]] && nuke_args+=("--dry-run")
    cmd_nuke "$APP_PATH" "${nuke_args[@]}"
  fi

  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    printf 'Planned icon target: %s\n' "$APP_ICON_TARGET"
    printf 'Planned backup path: %s\n' "$APP_ICON_BACKUP"
    [[ "$no_resign" == true ]] || printf 'Planned re-sign: %s\n' "$APP_PATH"
    [[ "$do_nuke" == true ]] && printf 'Planned cache refresh: yes\n'
  else
    printf 'Applied icon: %s\n' "$APP_ICON_TARGET"
    printf 'Backup icon: %s\n' "$APP_ICON_BACKUP"
    if [[ "$no_resign" != true ]]; then
      printf 'Re-signed: %s\n' "$APP_PATH"
    fi
    if [[ "$do_nuke" == true ]]; then
      printf 'Cache refresh: requested\n'
    fi
  fi

  return 0
}

cmd_restore() {
  local app_arg=""
  local do_nuke=false
  local no_resign=false
  local backup_file=""
  local nuke_args=()

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
  backup_file="$(find_restore_backup)" || { fail "No *_ugly.icns backup found for $APP_PATH" || return 1; }

  if [[ -z "$APP_ICON_TARGET" ]]; then
    APP_ICON_TARGET="${backup_file%_ugly.icns}.icns"
    APP_ICON_BACKUP="$backup_file"
  fi

  run_cmd cp "$backup_file" "$APP_ICON_TARGET" || return 1
  touch_app_bundle "$APP_PATH" || return 1
  if [[ "$no_resign" != true ]]; then
    resign_app_bundle "$APP_PATH" || return 1
  fi
  if [[ "$do_nuke" == true ]]; then
    [[ "$ICONFORGE_DRY_RUN" == true ]] && nuke_args+=("--dry-run")
    cmd_nuke "$APP_PATH" "${nuke_args[@]}"
  fi

  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    printf 'Planned restore target: %s\n' "$APP_ICON_TARGET"
    [[ "$no_resign" == true ]] || printf 'Planned re-sign: %s\n' "$APP_PATH"
  else
    printf 'Restored icon: %s\n' "$APP_ICON_TARGET"
    if [[ "$no_resign" != true ]]; then
      printf 'Re-signed: %s\n' "$APP_PATH"
    fi
  fi

  return 0
}

collect_nuke_targets() {
  local targets=()
  local entry
  local user_name

  targets+=("$HOME/Library/Caches/com.apple.iconservices.store")
  targets+=("$HOME/Library/Caches/com.apple.iconservices")

  user_name="$(id -un)"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    targets+=("$entry")
  done < <(find /private/var/folders -user "$user_name" \( -name 'com.apple.dock.iconcache' -o -name 'com.apple.iconservices*' \) -print 2>/dev/null || true)

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
