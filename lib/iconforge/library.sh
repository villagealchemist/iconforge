#!/usr/bin/env bash

ICON_LIBRARY_KEYS=()
ICON_LIBRARY_PROBLEMS=()
ICON_LIBRARY_RESOLVED_KEY=""
ICON_LIBRARY_RESOLVED_DIR=""
ICON_LIBRARY_RESOLVED_ICNS=""
ICON_LIBRARY_RESOLVED_PNG=""
ICON_LIBRARY_RESOLUTION_STATUS=""
ICON_LIBRARY_RESOLUTION_MESSAGE=""

library_reset() {
  ICON_LIBRARY_KEYS=()
  ICON_LIBRARY_PROBLEMS=()
}

scan_icon_library() {
  local icon_root="$1"
  local entry
  local key

  library_reset

  if [[ ! -d "$icon_root" ]]; then
    ICON_LIBRARY_PROBLEMS+=("icon root missing"$'\t'"$icon_root")
    return 1
  fi

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    key="$(basename "$entry")"
    ICON_LIBRARY_KEYS+=("$key")
  done < <(find "$icon_root" -mindepth 1 -maxdepth 1 -type d | sort)

  return 0
}

count_matching_files() {
  local dir_path="$1"
  local pattern="$2"
  local count=0
  local file_path

  while IFS= read -r file_path; do
    [[ -n "$file_path" ]] || continue
    count=$((count + 1))
  done < <(find "$dir_path" -maxdepth 1 -type f -name "$pattern" | sort)

  printf '%s\n' "$count"
}

resolve_icon_library_entry() {
  local icon_root="$1"
  local key="$2"
  local dir_path="$icon_root/$key"
  local preferred_icns="$dir_path/$key.icns"
  local preferred_png="$dir_path/$key.png"
  local icns_count
  local png_count
  local only_icns=""
  local only_png=""

  ICON_LIBRARY_RESOLVED_KEY="$key"
  ICON_LIBRARY_RESOLVED_DIR="$dir_path"
  ICON_LIBRARY_RESOLVED_ICNS=""
  ICON_LIBRARY_RESOLVED_PNG=""
  ICON_LIBRARY_RESOLUTION_STATUS=""
  ICON_LIBRARY_RESOLUTION_MESSAGE=""

  if [[ ! -d "$dir_path" ]]; then
    ICON_LIBRARY_RESOLUTION_STATUS="missing-directory"
    ICON_LIBRARY_RESOLUTION_MESSAGE="Icon directory not found"
    return 1
  fi

  if [[ -f "$preferred_icns" ]]; then
    ICON_LIBRARY_RESOLVED_ICNS="$preferred_icns"
    [[ -f "$preferred_png" ]] && ICON_LIBRARY_RESOLVED_PNG="$preferred_png"
    ICON_LIBRARY_RESOLUTION_STATUS="ready"
    return 0
  fi

  icns_count="$(count_matching_files "$dir_path" '*.icns')"
  if [[ "$icns_count" -eq 1 ]]; then
    only_icns="$(find "$dir_path" -maxdepth 1 -type f -name '*.icns' | sort | head -n 1)"
    ICON_LIBRARY_RESOLVED_ICNS="$only_icns"
    [[ -f "$preferred_png" ]] && ICON_LIBRARY_RESOLVED_PNG="$preferred_png"
    ICON_LIBRARY_RESOLUTION_STATUS="ready"
    ICON_LIBRARY_RESOLUTION_MESSAGE="Using the only .icns file in the directory"
    return 0
  fi

  if [[ "$icns_count" -gt 1 ]]; then
    ICON_LIBRARY_RESOLUTION_STATUS="ambiguous-icns"
    ICON_LIBRARY_RESOLUTION_MESSAGE="Multiple .icns files found and none matches the directory name"
    return 1
  fi

  png_count="$(count_matching_files "$dir_path" '*.png')"
  if [[ -f "$preferred_png" ]]; then
    ICON_LIBRARY_RESOLVED_PNG="$preferred_png"
    ICON_LIBRARY_RESOLUTION_STATUS="needs-forge"
    ICON_LIBRARY_RESOLUTION_MESSAGE="PNG exists but .icns has not been forged yet"
    return 1
  fi

  if [[ "$png_count" -eq 1 ]]; then
    only_png="$(find "$dir_path" -maxdepth 1 -type f -name '*.png' | sort | head -n 1)"
    ICON_LIBRARY_RESOLVED_PNG="$only_png"
    ICON_LIBRARY_RESOLUTION_STATUS="needs-forge"
    ICON_LIBRARY_RESOLUTION_MESSAGE="Single PNG exists but .icns has not been forged yet"
    return 1
  fi

  if [[ "$png_count" -gt 1 ]]; then
    ICON_LIBRARY_RESOLUTION_STATUS="ambiguous-png"
    ICON_LIBRARY_RESOLUTION_MESSAGE="Multiple PNG files found and no deterministic source can be chosen"
    return 1
  fi

  ICON_LIBRARY_RESOLUTION_STATUS="missing-icon"
  ICON_LIBRARY_RESOLUTION_MESSAGE="No .icns or PNG asset found"
  return 1
}
