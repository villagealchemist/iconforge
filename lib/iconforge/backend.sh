#!/usr/bin/env bash

# Built-in backend boundary. CLI policy does not execute platform tools directly.
# No dynamically sourced plugins or arbitrary executable paths from preferences.
BACKEND_TARGET=""
BACKEND_TARGET_KEYS=()
BACKEND_ICON_FILES=()
BACKEND_ICON_KEYS=()

backend_name() {
  case "$(uname -s)" in Darwin) printf 'macos\n' ;; *) printf 'unsupported\n' ;; esac
}

backend_require() {
  [[ "$(backend_name)" == macos ]] || {
    fail "'$1' currently requires the macOS backend. Other platforms are not implemented; no system changes were made."
    return 1
  }
}

backend_resolve_target() {
  local query="$1" value key existing found
  BACKEND_TARGET=""; BACKEND_TARGET_KEYS=()
  inspect_app_metadata "$query" || return 1
  BACKEND_TARGET="$APP_PATH"
  # App identity and normalization are shared with existing bulk matching.
  for value in "$(basename "$APP_PATH")" \
    "$(plist_string "$APP_INFO_PLIST" ':CFBundleDisplayName')" \
    "$(plist_string "$APP_INFO_PLIST" ':CFBundleName')"; do
    [[ -n "$value" ]] || continue
    key="$(normalize_match_token "$value")" || return 1
    [[ -n "$key" ]] || continue
    found=false
    for existing in "${BACKEND_TARGET_KEYS[@]+"${BACKEND_TARGET_KEYS[@]}"}"; do
      [[ "$existing" != "$key" ]] || found=true
    done
    [[ "$found" == true ]] || BACKEND_TARGET_KEYS+=("$key")
  done
}

backend_scan_icons() {
  scan_icon_library "$1" || return 1
  BACKEND_ICON_FILES=("${ICON_LIBRARY_FILES[@]+"${ICON_LIBRARY_FILES[@]}"}")
  BACKEND_ICON_KEYS=("${ICON_LIBRARY_NORMALIZED_KEYS[@]+"${ICON_LIBRARY_NORMALIZED_KEYS[@]}"}")
}

backend_forge() { cmd_forge "$@"; }
backend_inspect() { cmd_inspect "$@"; }
backend_restore() { cmd_restore "$@"; }
backend_refresh() { cmd_nuke "$@"; }
backend_apply_one() { cmd_apply "$@"; }
backend_apply_all() { cmd_apply --all "$@"; }

capabilities_help() {
  cat <<'HELP'
Show built-in backend capabilities without changing your system.
Usage: iconforge capabilities
HELP
}

cmd_capabilities() {
  [[ $# -eq 0 ]] || {
    if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then capabilities_help; return 0; fi
    usage_fail 'Usage: iconforge capabilities'; return 2
  }
  printf 'Backend: %s\n' "$(backend_name)"
  printf 'Implemented backend: macos\n'
  printf 'Format: ICNS\n'
  printf 'Operations: forge, inspect, apply, restore, refresh\n'
  printf 'Default application strategy: native\n'
  printf 'Explicit expert strategy: internal-icns (single app only)\n'
  printf 'Mobile and other platform backends: not implemented\n'
}

doctor_help() {
  cat <<'HELP'
Check configuration, installation, and an optional app without making changes.
Usage: iconforge doctor [app]

This checks backend availability and reports system-managed app locations.
It does not clear caches, request administrator privileges, or change security.
HELP
}

cmd_doctor() {
  local failed=0 tool
  [[ $# -le 1 ]] || { usage_fail 'Usage: iconforge doctor [app]'; return 2; }
  case "${1:-}" in -h|--help) doctor_help; return 0 ;; -*) usage_fail 'Usage: iconforge doctor [app]'; return 2 ;; esac
  cmd_capabilities
  printf '\n'
  backend_require doctor || return 1
  for tool in "$ICONFORGE_PROCESSOR" "$ICONFORGE_NATIVE_ICON" /usr/bin/plutil /usr/bin/xmllint; do
    if [[ -x "$tool" ]]; then printf 'OK       %s\n' "$tool"; else printf 'MISSING  %s\n' "$tool"; failed=1; fi
  done
  printf '\n'
  config_show || failed=1
  if [[ $# -eq 1 ]]; then
    backend_resolve_target "$1" || return 1
    printf '\nApplication: %s\n' "$BACKEND_TARGET"
    case "$BACKEND_TARGET" in
      /System/*)
        printf 'System-managed location. Ordinary icon writes may be blocked by OS protections.\n'
        printf 'Changing a Finder application icon is not a guarantee of changing its Dock icon.\n'
        printf 'IconForge does not change SIP, Gatekeeper, or the system volume.\n'
        ;;
      *)
        if [[ -w "$BACKEND_TARGET" ]]; then printf 'Application root is writable.\n'; else printf 'Application root is not writable by the current user.\n'; fi
        ;;
    esac
  fi
  return "$failed"
}
