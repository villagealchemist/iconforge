#!/usr/bin/env bash

# Public CLI policy: normalize -> resolve preferences -> plan -> backend.
# Existing cmd_* implementations are the macOS execution adapter, not a second
# source of public defaults. They receive resolved, explicit operands.
CLI_ARGS=()
CLI_ICON=""

# Accept standard --name=value forms. Preserve the end-of-options marker and
# argv boundaries; never eval or join user input into shell source.
cli_normalize_options() {
  local command="$1" token name value options_done=false
  shift
  CLI_ARGS=()
  while [[ $# -gt 0 ]]; do
    token="$1"; shift
    if [[ "$options_done" == true ]]; then CLI_ARGS+=("$token"); continue; fi
    case "$token" in
      --) options_done=true; CLI_ARGS+=("--") ;;
      --*=*)
        name="${token%%=*}"; value="${token#*=}"
        case "$command:$name" in
          forge:--output|apply:--icon|apply:--from|apply:--strategy|apply:--app-root|inspect:--app-root|restore:--app-root|nuke:--app-root|refresh:--app-root)
            [[ -n "$value" ]] || { usage_fail "$name requires a nonempty value"; return 2; }
            CLI_ARGS+=("$name" "$value")
            ;;
          *) usage_fail "Unknown value option for $command: $name"; return 2 ;;
        esac
        ;;
      *) CLI_ARGS+=("$token") ;;
    esac
  done
}

cli_forge_help() {
  forge_help
  cat <<'HELP'

Output preference: --output, then the-forge, then legacy default-directory,
then the current directory. --output=<directory> is also accepted.
Use iconforge config show to see which preference is active.
HELP
}

cli_forge() {
  local output_seen=false options_done=false token
  local -a args=()
  cli_normalize_options forge "$@" || return $?
  args=("${CLI_ARGS[@]+"${CLI_ARGS[@]}"}")
  [[ "${#args[@]}" -gt 0 ]] || {
    cli_forge_help
    usage_fail "forge requires an input image or directory" || return 2
  }
  # The engine still validates all forge grammar, duplicates, and collisions.
  for token in "${args[@]+"${args[@]}"}"; do
    [[ "$options_done" != true ]] || continue
    case "$token" in
      --) options_done=true ;;
      -h|--help) cli_forge_help; return 0 ;;
      -o|--output) output_seen=true ;;
    esac
  done
  backend_require forge || return 1
  if [[ "$output_seen" != true ]]; then
    config_effective_directory the-forge || return 1
    args=(--output "$CONFIG_DIRECTORY" "${args[@]}")
  fi
  backend_forge "${args[@]}"
}

cli_apply_help() {
  cat <<'HELP'
Apply an icon from your hearth, or choose an explicit file.

Usage:
  iconforge apply <app> [nuke] [options]
  iconforge apply --all [directory] [options]
  iconforge apply -a [directory] [options]

Examples:
  iconforge apply Firefox
  iconforge apply Firefox nuke
  iconforge apply "Visual Studio Code" --dry-run
  iconforge apply Firefox --from "$HOME/alternate-icons"
  iconforge apply Firefox --icon ./experimental.icns
  iconforge apply --all --nuke --dry-run

Options:
  -i, --icon <file>       Explicit ICNS file, bypassing library lookup
      --from <directory> Override the-hearth for this invocation
      --app-root <dir>   Additional app search root (repeatable)
  -a, --all              Explicitly select all eligible library icons
  -s, --strategy <name>  native (default) or internal-icns (single app only)
  -n, --nuke             Refresh current-user icon caches after success
      --refresh         Alias for --nuke
  -d, --dry-run          Validate and preview without making changes
  -v, --verbose          Show resolution details and bulk entry statuses
  -h, --help             Show this help

Library: --from, then the-hearth, then legacy default-directory.
Only an unambiguous exact normalized icon match is automatic. Explicit --icon
never consults the library. --all is always required for bulk changes.
'nuke' is shorthand only after a direct app operand, before --. To address the
application Nuke, use 'iconforge apply Nuke'. Flags also accept --name=value.
HELP
}

cli_select_icon() {
  local library="$1" index key matches=0
  CLI_ICON=""
  backend_scan_icons "$library" || return 1
  for ((index=0; index<${#BACKEND_ICON_FILES[@]}; index++)); do
    for key in "${BACKEND_TARGET_KEYS[@]+"${BACKEND_TARGET_KEYS[@]}"}"; do
      [[ "${BACKEND_ICON_KEYS[$index]}" == "$key" ]] || continue
      matches=$((matches + 1))
      CLI_ICON="${BACKEND_ICON_FILES[$index]}"
      break
    done
  done
  if [[ "$matches" -eq 0 ]]; then
    fail "No matching icon for '$BACKEND_TARGET' in $library" || true
    note "Name an ICNS file after the application, or choose one with --icon <file.icns>."
    note "To change libraries, use --from <directory> or iconforge config set the-hearth <directory>."
    return 1
  fi
  if [[ "$matches" -gt 1 ]]; then
    fail "Multiple icons match '$BACKEND_TARGET'; refusing to choose by scan order:" || true
    for ((index=0; index<${#BACKEND_ICON_FILES[@]}; index++)); do
      for key in "${BACKEND_TARGET_KEYS[@]+"${BACKEND_TARGET_KEYS[@]}"}"; do
        if [[ "${BACKEND_ICON_KEYS[$index]}" == "$key" ]]; then
          note "  ${BACKEND_ICON_FILES[$index]}"; break
        fi
      done
    done
    note "Select the intended file explicitly with --icon <file.icns>."
    CLI_ICON=""; return 1
  fi
}

cli_apply() {
  local app="" app_seen=false icon="" icon_seen=false library="" from_seen=false
  local all=false strategy="native" strategy_seen=false refresh=false dry=false verbose=false
  local options_done=false shorthand_seen=false option root
  local -a args=() flags=() ICONFORGE_EXTRA_APPLICATION_ROOTS=()
  cli_normalize_options apply "$@" || return $?
  args=("${CLI_ARGS[@]+"${CLI_ARGS[@]}"}")
  set -- "${args[@]+"${args[@]}"}"
  while [[ $# -gt 0 ]]; do
    if [[ "$options_done" != true ]]; then
      case "$1" in
        --) options_done=true; shift; continue ;;
        -h|--help) cli_apply_help; return 0 ;;
        -i|--icon|--from|-s|--strategy|--app-root)
          option="$1"
          [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { usage_fail "$option requires a value (prefix leading-dash paths with ./)"; return 2; }
          case "$option" in
            -i|--icon)
              [[ "$icon_seen" != true ]] || { usage_fail '--icon may be supplied only once'; return 2; }
              icon="$2"; icon_seen=true ;;
            --from)
              [[ "$from_seen" != true ]] || { usage_fail '--from may be supplied only once'; return 2; }
              library="$2"; from_seen=true ;;
            -s|--strategy)
              [[ "$strategy_seen" != true ]] || { usage_fail '--strategy may be supplied only once'; return 2; }
              strategy="$2"; strategy_seen=true ;;
            --app-root)
              root="$(config_canonical_directory_path "$2")" || return 1
              [[ -d "$root" && "$root" != / && "$root" != *$'\n'* && "$root" != *$'\t'* ]] || { usage_fail 'An --app-root must be an existing directory other than /, without tabs or newlines'; return 2; }
              ICONFORGE_EXTRA_APPLICATION_ROOTS+=("$root") ;;
          esac
          shift 2; continue
          ;;
        -a|--all) all=true; shift; continue ;;
        -n|--nuke|--refresh) refresh=true; shift; continue ;;
        -d|--dry-run) dry=true; shift; continue ;;
        -v|--verbose) verbose=true; shift; continue ;;
        -*) usage_fail "Unknown apply flag: $1"; return 2 ;;
      esac
      if [[ "$app_seen" == true && "$1" == nuke && "$shorthand_seen" != true && "$all" != true ]]; then
        shorthand_seen=true; refresh=true; shift; continue
      fi
    fi
    [[ "$app_seen" != true ]] || { usage_fail "Unexpected apply argument: $1"; return 2; }
    [[ -n "$1" ]] || { usage_fail 'Apply operand must not be empty'; return 2; }
    app="$1"; app_seen=true; shift
  done
  [[ "$all" != true || "$shorthand_seen" != true ]] || { usage_fail "Use --nuke with --all; a bare 'nuke' could be a directory"; return 2; }
  [[ "$icon_seen" != true || "$from_seen" != true ]] || { usage_fail '--icon and --from are alternatives; choose one'; return 2; }
  case "$strategy" in native|internal-icns) ;; *) usage_fail "Unknown strategy: $strategy"; return 2 ;; esac
  if [[ "$all" == true ]]; then
    [[ "$icon_seen" != true && "$strategy_seen" != true ]] || { usage_fail '--all cannot use --icon or --strategy'; return 2; }
    [[ "$app_seen" != true || "$from_seen" != true ]] || { usage_fail 'Supply a bulk directory or --from, not both'; return 2; }
    [[ "$app_seen" != true ]] || library="$app"
  else
    [[ "$app_seen" == true ]] || { cli_apply_help; return 2; }
  fi
  [[ "$dry" != true ]] || flags+=(--dry-run)
  [[ "$refresh" != true ]] || flags+=(--nuke)
  [[ "$verbose" != true ]] || flags+=(--verbose)
  backend_require apply || return 1
  if [[ "$icon_seen" != true && -z "$library" ]]; then
    config_effective_directory the-hearth || return 1
    library="$CONFIG_DIRECTORY"
    [[ -n "$library" ]] || {
      [[ "$all" != true ]] || note '--all requires an icon directory or a configured default-directory (legacy) or the-hearth.'
      usage_fail 'No icon library is configured. Use iconforge config set the-hearth <directory>, --from <directory>, or --icon <file.icns>.'; return 2;
    }
  fi
  if [[ "$all" == true ]]; then
    # One backend batch, one final refresh. Existing whole-batch preflight stays.
    backend_apply_all "${flags[@]+"${flags[@]}"}" -- "$library"
    return $?
  fi
  if [[ "$icon_seen" == true ]]; then
    # Keep explicit invocations independent of an unrelated broken preference.
    backend_apply_one --icon "$icon" --strategy "$strategy" "${flags[@]+"${flags[@]}"}" -- "$app"
    return $?
  fi
  backend_resolve_target "$app" || return 1
  cli_select_icon "$library" || return 1
  if [[ "$verbose" == true || "$dry" == true ]]; then
    printf 'Application: %s\nIcon: %s\nLibrary: %s\n' "$BACKEND_TARGET" "$CLI_ICON" "$library"
  fi
  backend_apply_one --icon "$CLI_ICON" --strategy "$strategy" "${flags[@]+"${flags[@]}"}" -- "$BACKEND_TARGET"
}

# Shared routing for inspect/restore/refresh. Extra roots remain invocation-local
# and are visible to the discovery adapter via Bash's dynamic local scope.
cli_target_command() {
  local command="$1" options_done=false root token
  local -a args=() ICONFORGE_EXTRA_APPLICATION_ROOTS=()
  shift
  cli_normalize_options "$command" "$@" || return $?
  set -- "${CLI_ARGS[@]+"${CLI_ARGS[@]}"}"
  while [[ $# -gt 0 ]]; do
    if [[ "$options_done" != true ]]; then
      case "$1" in
        --) options_done=true ;;
        -h|--help)
          case "$command" in inspect) inspect_help ;; restore) restore_help ;; nuke|refresh) nuke_help ;; esac
          printf '\nAdditional app search root: --app-root <directory> (repeatable)\n'
          return 0 ;;
        --app-root)
          [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { usage_fail '--app-root requires a directory'; return 2; }
          root="$(config_canonical_directory_path "$2")" || return 1
          [[ -d "$root" && "$root" != / && "$root" != *$'\n'* && "$root" != *$'\t'* ]] || { usage_fail 'Invalid --app-root'; return 2; }
          ICONFORGE_EXTRA_APPLICATION_ROOTS+=("$root"); shift 2; continue ;;
        --refresh)
          [[ "$command" == restore ]] || { usage_fail "$command does not accept --refresh"; return 2; }
          args+=(--nuke); shift; continue ;;
      esac
    fi
    token="$1"; args+=("$token"); shift
  done
  backend_require "$command" || return 1
  case "$command" in
    inspect) backend_inspect "${args[@]+"${args[@]}"}" ;;
    restore) backend_restore "${args[@]+"${args[@]}"}" ;;
    nuke|refresh) backend_refresh "${args[@]+"${args[@]}"}" ;;
  esac
}
