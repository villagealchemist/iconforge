#!/usr/bin/env bash

ICON_LIBRARY_ROOT=""
ICON_LIBRARY_FILES=()
ICON_LIBRARY_KEYS=()
ICON_LIBRARY_NORMALIZED_KEYS=()

library_reset() {
  ICON_LIBRARY_ROOT=""
  ICON_LIBRARY_FILES=()
  ICON_LIBRARY_KEYS=()
  ICON_LIBRARY_NORMALIZED_KEYS=()
}

scan_icon_library() {
  local icon_root="${1:-}"
  local canonical_root
  local root_name
  local root_name_folded
  local icon_file
  local basename_value
  local key

  library_reset
  [[ -d "$icon_root" ]] || { fail "Icon directory not found: $icon_root"; return 1; }
  canonical_root="$(realpath -- "$icon_root")" || {
    fail "Could not resolve icon directory: $icon_root"
    return 1
  }
  root_name="$(basename "$canonical_root")"
  root_name_folded="$(printf '%s' "$root_name" | tr '[:upper:]' '[:lower:]')"

  case "$root_name" in
    .*)
      fail "Icon directory root must not be dot-hidden: $icon_root"
      return 1
      ;;
  esac
  case "$root_name_folded" in
    *.app|*.iconset)
      fail "Icon directory root must not be an app bundle or iconset: $icon_root"
      return 1
      ;;
  esac

  ICON_LIBRARY_ROOT="$canonical_root"

  while IFS= read -r icon_file; do
    [[ -n "$icon_file" ]] || continue
    basename_value="$(basename "$icon_file")"
    case "$basename_value" in
      *_[uU][gG][lL][yY].[iI][cC][nN][sS]) continue ;;
    esac
    key="${basename_value%.*}"
    ICON_LIBRARY_FILES+=("$(realpath -- "$icon_file")")
    ICON_LIBRARY_KEYS+=("$key")
    ICON_LIBRARY_NORMALIZED_KEYS+=("$(normalize_match_token "$key")")
  done < <(
    find "$ICON_LIBRARY_ROOT" -mindepth 1 \
      \( -type l -o -type d \( -name '.*' -o -name '_*' -o -iname '*.app' -o -iname '*.iconset' \) \) -prune -o \
      -type f -iname '*.icns' ! -name '.*' ! -name '_*' -print 2>/dev/null | sort
  )

  return 0
}
