#!/usr/bin/env bash

# Records are tab-separated: path, bundle id, display name, bundle name,
# filename. This keeps the data model portable to macOS's system Bash.
DISCOVERED_APP_RECORDS=()

discovery_reset() {
  DISCOVERED_APP_RECORDS=()
}

normalize_match_token_fallback() {
  local raw_value="$1"

  printf '%s\n' "$raw_value" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/\.[aA][pP][pP]$//; s/[^[:alnum:]]+/ /g; s/^ +//; s/ +$//; s/ +/ /g'
}

normalize_match_token() {
  local raw_value="$1"
  local normalized=""

  # The bundled Foundation helper provides canonical Unicode normalization.
  # Keep a locale-aware fallback so inspect still works before a development
  # checkout has built its helper.
  if [[ -x "${ICONFORGE_NATIVE_ICON:-}" ]]; then
    normalized="$("$ICONFORGE_NATIVE_ICON" normalize "$raw_value" 2>/dev/null || true)"
  fi
  if [[ -n "$normalized" ]]; then
    printf '%s\n' "$normalized"
  else
    normalize_match_token_fallback "$raw_value"
  fi
}

discovery_add_record() {
  local app_path="$1"
  local existing
  local existing_path
  local info_plist="$app_path/Contents/Info.plist"
  local bundle_id
  local display_name
  local bundle_name
  local file_name

  app_path="$(realpath -- "$app_path")"
  for existing in "${DISCOVERED_APP_RECORDS[@]+"${DISCOVERED_APP_RECORDS[@]}"}"; do
    existing_path="${existing%%$'\t'*}"
    [[ "$existing_path" == "$app_path" ]] && return 0
  done

  bundle_id="$(plist_string "$info_plist" ":CFBundleIdentifier")"
  display_name="$(plist_string "$info_plist" ":CFBundleDisplayName")"
  bundle_name="$(plist_string "$info_plist" ":CFBundleName")"
  file_name="$(basename "$app_path")"
  DISCOVERED_APP_RECORDS+=(
    "$app_path"$'\t'"$bundle_id"$'\t'"$display_name"$'\t'"$bundle_name"$'\t'"$file_name"
  )
}

discover_applications() {
  local search_roots=(
    "${ICONFORGE_TEST_CURRENT_APPLICATIONS_DIR:-$PWD}"
    "${ICONFORGE_TEST_USER_APPLICATIONS_DIR:-$HOME/Applications}"
    "${ICONFORGE_TEST_APPLICATIONS_DIR:-/Applications}"
    "${ICONFORGE_TEST_SYSTEM_APPLICATIONS_DIR:-/System/Applications}"
  )
  local search_root
  local app_path

  discovery_reset
  for search_root in "${search_roots[@]}"; do
    [[ -d "$search_root" ]] || continue
    while IFS= read -r app_path; do
      [[ -f "$app_path/Contents/Info.plist" ]] || continue
      discovery_add_record "$app_path"
    done < <(find "$search_root" -mindepth 1 -maxdepth 2 -type d -iname '*.app' -prune -print 2>/dev/null | sort)
  done
}

discovered_app_field() {
  local record="$1"
  local field_index="$2"
  printf '%s\n' "$record" | awk -F '\t' -v index="$field_index" '{print $index}'
}

discovered_app_path() { discovered_app_field "$1" 1; }
discovered_app_bundle_id() { discovered_app_field "$1" 2; }
discovered_app_display_name() { discovered_app_field "$1" 3; }
discovered_app_bundle_name() { discovered_app_field "$1" 4; }
discovered_app_file_name() { discovered_app_field "$1" 5; }
