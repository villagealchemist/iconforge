#!/usr/bin/env bash

DISCOVERED_APP_RECORDS=()

discovery_reset() {
  DISCOVERED_APP_RECORDS=()
}

normalize_match_token() {
  local raw_value="$1"

  printf '%s\n' "$raw_value" | tr '[:upper:]' '[:lower:]' | sed -E 's/\.app$//; s/[^a-z0-9]+/ /g; s/^ +//; s/ +$//; s/ +/ /g'
}

discover_applications() {
  local search_roots=(
    "${ICONFORGE_USER_APPLICATIONS_DIR:-$HOME/Applications}"
    "${ICONFORGE_SYSTEM_APPLICATIONS_DIR:-/Applications}"
  )
  local search_root
  local app_path
  local info_plist
  local bundle_id
  local display_name
  local bundle_name
  local file_name

  discovery_reset

  for search_root in "${search_roots[@]}"; do
    [[ -d "$search_root" ]] || continue

    while IFS= read -r app_path; do
      [[ -n "$app_path" ]] || continue
      info_plist="$app_path/Contents/Info.plist"
      [[ -f "$info_plist" ]] || continue

      bundle_id="$(plist_string "$info_plist" ":CFBundleIdentifier")"
      display_name="$(plist_string "$info_plist" ":CFBundleDisplayName")"
      bundle_name="$(plist_string "$info_plist" ":CFBundleName")"
      file_name="$(basename "$app_path")"

      DISCOVERED_APP_RECORDS+=(
        "$app_path"$'\t'"$bundle_id"$'\t'"$display_name"$'\t'"$bundle_name"$'\t'"$file_name"
      )
    done < <(find "$search_root" -mindepth 1 -maxdepth 2 -type d -name '*.app' | sort)
  done
}

discovered_app_field() {
  local record="$1"
  local field_index="$2"
  printf '%s\n' "$record" | awk -F '\t' -v index="$field_index" '{print $index}'
}

discovered_app_path() {
  discovered_app_field "$1" 1
}

discovered_app_bundle_id() {
  discovered_app_field "$1" 2
}

discovered_app_display_name() {
  discovered_app_field "$1" 3
}

discovered_app_bundle_name() {
  discovered_app_field "$1" 4
}

discovered_app_file_name() {
  discovered_app_field "$1" 5
}
