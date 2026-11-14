#!/usr/bin/env bash

# Records are tab-separated: path, bundle id, display name, bundle name,
# filename. This keeps the data model portable to macOS's system Bash.
DISCOVERED_APP_RECORDS=()

discovery_reset() { DISCOVERED_APP_RECORDS=(); }

normalize_match_token_fallback() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' |
    sed -E 's/\.[aA][pP][pP]$//; s/[^[:alnum:]]+/ /g; s/^ +//; s/ +$//; s/ +/ /g'
}

normalize_match_token() {
  local raw_value="$1" normalized=""
  # One native Unicode-normalization implementation for direct and bulk apply.
  if [[ -x "${ICONFORGE_NATIVE_ICON:-}" ]]; then
    if ! normalized="$("$ICONFORGE_NATIVE_ICON" normalize "$raw_value")"; then
      warn "Native application-name normalization failed; using the locale-aware fallback."
      remedy "Rebuild or reinstall the native helper to restore Unicode normalization, or use an exact application path."
      normalized=""
    fi
  fi
  if [[ -n "$normalized" ]]; then printf '%s\n' "$normalized"; else normalize_match_token_fallback "$raw_value"; fi
}

discovery_add_record() {
  local app_path="$1" existing existing_path info_plist="$1/Contents/Info.plist"
  local bundle_id display_name bundle_name file_name
  app_path="$(realpath -- "$app_path")" || {
    fail "Could not resolve a discovered application path: $1" || return 1
  }
  for existing in "${DISCOVERED_APP_RECORDS[@]+"${DISCOVERED_APP_RECORDS[@]}"}"; do
    existing_path="${existing%%$'\t'*}"
    [[ "$existing_path" == "$app_path" ]] && return 0
  done
  bundle_id="$(plist_string "$info_plist" ':CFBundleIdentifier')"
  display_name="$(plist_string "$info_plist" ':CFBundleDisplayName')"
  bundle_name="$(plist_string "$info_plist" ':CFBundleName')"
  file_name="$(basename "$app_path")"
  DISCOVERED_APP_RECORDS+=("$app_path"$'\t'"$bundle_id"$'\t'"$display_name"$'\t'"$bundle_name"$'\t'"$file_name")
}

discover_applications() {
  local -a search_roots=(
    "${ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR:-$PWD}"
    "${ICONFORGE_TEST_USER_APPLICATIONS_DIR:-$HOME/Applications}"
    "${ICONFORGE_TEST_APPLICATIONS_DIR:-/Applications}"
    "${ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR:-/System/Applications}"
    "${ICONFORGE_TEST_CORE_SERVICES_DIR:-/System/Library/CoreServices}"
    "${ICONFORGE_EXTRA_APPLICATION_ROOTS[@]+"${ICONFORGE_EXTRA_APPLICATION_ROOTS[@]}"}"
  )
  local search_root app_path scan_output
  local scan_failed=false

  discovery_reset
  for search_root in "${search_roots[@]}"; do
    [[ -d "$search_root" ]] || continue
    if ! scan_output="$(set -o pipefail; find "$search_root" -mindepth 1 -maxdepth 2 -type d -iname '*.app' -prune -print | sort)"; then
      fail "Could not completely scan applications under: $search_root" || true
      scan_failed=true
      continue
    fi
    while IFS= read -r app_path; do
      [[ -n "$app_path" && -f "$app_path/Contents/Info.plist" ]] || continue
      discovery_add_record "$app_path" || scan_failed=true
    done <<<"$scan_output"
  done
  if [[ "$scan_failed" == true ]]; then
    discovery_reset
    remedy "Resolve the reported application-directory scan errors and retry, or supply an exact application path. Incomplete discovery results were discarded."
    return 1
  fi
  return 0
}

discovered_app_field() { printf '%s\n' "$1" | awk -F '\t' -v index="$2" '{print $index}'; }
discovered_app_path() { discovered_app_field "$1" 1; }
discovered_app_bundle_id() { discovered_app_field "$1" 2; }
discovered_app_display_name() { discovered_app_field "$1" 3; }
discovered_app_bundle_name() { discovered_app_field "$1" 4; }
discovered_app_file_name() { discovered_app_field "$1" 5; }
