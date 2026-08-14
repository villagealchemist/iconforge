#!/usr/bin/env bash

if ! command -v realpath >/dev/null 2>&1; then
  realpath() {
    [[ "${1:-}" != -- ]] || shift
    if [[ -d "$1" ]]; then
      (cd "$1" && pwd)
    else
      echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    fi
  }
fi

ICONFORGE_ROOT="${ICONFORGE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ICONFORGE_PROCESSOR="${ICONFORGE_PROCESSOR:-$ICONFORGE_ROOT/iconforge-processor/iconforge-processor}"
ICONFORGE_NATIVE_ICON="${ICONFORGE_NATIVE_ICON:-$ICONFORGE_ROOT/iconforge-native-icon/iconforge-native-icon}"
ICONFORGE_VERSION="$(<"$ICONFORGE_ROOT/VERSION")"

PLIST_BUDDY_BIN="${ICONFORGE_PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"
CODESIGN_BIN="${ICONFORGE_CODESIGN_BIN:-codesign}"
TOUCH_BIN="${ICONFORGE_TOUCH_BIN:-touch}"
KILLALL_BIN="${ICONFORGE_KILLALL_BIN:-killall}"
RM_BIN="${ICONFORGE_RM_BIN:-rm}"
CP_BIN="${ICONFORGE_CP_BIN:-cp}"

ICONFORGE_DRY_RUN=false

APP_PATH=""
APP_INFO_PLIST=""
APP_RESOURCES_DIR=""
APP_CF_BUNDLE_ICON_FILE=""
APP_CF_BUNDLE_ICON_NAME=""
APP_PRIMARY_ICON_NAME=""
APP_PRIMARY_ICON_FILES=()
APP_CAR_FILES=()
APP_USES_ASSET_CATALOG=false
APP_ICON_TARGET=""
APP_ICON_BACKUP=""

stderr() {
  printf '%s\n' "$*" >&2
}

fail() {
  stderr "Error: $*"
  return 1
}

usage_fail() {
  stderr "Error: $*"
  return 2
}

warn() {
  stderr "Warning: $*"
}

note() {
  stderr "$*"
}

join_by() {
  local separator="$1"
  shift || true
  local first=true
  local item
  for item in "$@"; do
    if [[ "$first" == true ]]; then
      printf '%s' "$item"
      first=false
    else
      printf '%s%s' "$separator" "$item"
    fi
  done
}

format_cmd() {
  local chunk
  local rendered=""
  for chunk in "$@"; do
    printf -v chunk '%q' "$chunk"
    rendered+="${chunk} "
  done
  printf '%s' "${rendered% }"
}

run_cmd() {
  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    stderr "[dry-run] $(format_cmd "$@")"
    return 0
  fi

  "$@"
}

run_quiet_cmd() {
  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    stderr "[dry-run] $(format_cmd "$@")"
    return 0
  fi

  "$@" >/dev/null 2>&1
}

require_tool() {
  local tool="$1"
  local message="${2:-Required tool missing: $tool}"
  if ! command -v "$tool" >/dev/null 2>&1; then
    fail "$message" || return 1
  fi
}

require_nonempty_path() {
  local label="$1"
  local path_value="${2:-}"

  [[ -n "$path_value" ]] || fail "$label must not be empty" || return 1
}

require_existing_file_path() {
  local label="$1"
  local path_value="${2:-}"

  require_nonempty_path "$label" "$path_value" || return 1
  [[ -f "$path_value" ]] || fail "$label not found: $path_value" || return 1
}

require_app_bundle_path() {
  local app_path="${1:-}"
  local trimmed_path=""

  require_nonempty_path "App bundle path" "$app_path" || return 1
  trimmed_path="${app_path%/}"
  case "$trimmed_path" in
    *.[aA][pP][pP]) ;;
    *) fail "App bundle path must end in .app: $app_path" || return 1 ;;
  esac
  [[ -d "$app_path" ]] || fail "App bundle not found: $app_path" || return 1
  [[ -f "$app_path/Contents/Info.plist" ]] || fail "App bundle is missing Contents/Info.plist: $app_path" || return 1
}

require_processor() {
  [[ -x "$ICONFORGE_PROCESSOR" ]] || fail "iconforge-processor not found at $ICONFORGE_PROCESSOR"
}

validate_icns_file() {
  local icon_file="${1:-}"
  local extension=""

  require_existing_file_path "Icon file" "$icon_file" || return 1
  extension="${icon_file##*.}"
  extension="$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"
  [[ "$extension" == "icns" ]] || { fail "Icon file must have an .icns extension: $icon_file"; return 1; }

  require_native_icon_helper || return 1
  "$ICONFORGE_NATIVE_ICON" validate "$icon_file" >/dev/null || {
    fail "Invalid ICNS file: $icon_file" || return 1
  }
}

iconforge_temp_root() {
  printf '%s\n' "${TMPDIR:-/tmp}"
}

plist_print() {
  "$PLIST_BUDDY_BIN" -c "Print $2" "$1" 2>/dev/null || true
}

plist_string() {
  local value
  value=$(plist_print "$1" "$2")
  if [[ -n "$value" ]]; then
    printf '%s' "$value" | sed 's/^"\(.*\)"$/\1/'
  fi
}

plist_array_values() {
  local raw
  raw=$(plist_print "$1" "$2")
  [[ -n "$raw" ]] || return 0

  printf '%s\n' "$raw" | awk '
    /^[[:space:]]*Array[[:space:]]*\{/ { next }
    /^[[:space:]]*\}[[:space:]]*$/ { next }
    /^[[:space:]]*$/ { next }
    {
      gsub(/^[[:space:]]+/, "", $0)
      gsub(/[[:space:]]+$/, "", $0)
      gsub(/^"/, "", $0)
      gsub(/"$/, "", $0)
      print $0
    }
  '
}

find_car_files() {
  local resources_dir="$1"
  [[ -d "$resources_dir" ]] || return 0
  find "$resources_dir" -mindepth 1 -maxdepth 1 -iname '*.car' -print 2>/dev/null | sort
}

find_loose_icns_files() {
  local resources_dir="$1"
  [[ -d "$resources_dir" ]] || return 0
  find "$resources_dir" -maxdepth 1 -type f -iname '*.icns' ! -iname '*_ugly.icns' -print 2>/dev/null | sort
}

strip_icns_extension() {
  local value="$1"
  case "$value" in
    *.[iI][cC][nN][sS]) printf '%s\n' "${value%?????}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

internal_backup_matches_target() {
  local backup_path="$1"
  local target_path="$2"
  local backup_name
  local target_name
  local expected_path
  local expected_name
  local backup_key
  local expected_key

  require_native_icon_helper || return 1
  backup_name="$(basename -- "$backup_path")"
  target_name="$(basename -- "$target_path")"
  expected_name="$(strip_icns_extension "$target_name")_ugly.icns"
  expected_path="$(dirname -- "$target_path")/$expected_name"

  if [[ -e "$backup_path" && -e "$expected_path" ]]; then
    [[ "$backup_path" -ef "$expected_path" ]]
    return
  fi

  backup_key="$("$ICONFORGE_NATIVE_ICON" path-key "$backup_name")" || return 1
  expected_key="$("$ICONFORGE_NATIVE_ICON" path-key "$expected_name")" || return 1
  [[ "$backup_key" == "$expected_key" ]]
}

mutable_app_info_plist_is_safe() {
  local app_path="${1:-}"
  local app_real
  local contents_path
  local contents_real
  local plist_path
  local plist_real
  local plist_parent_real

  [[ -n "$app_path" && -d "$app_path" ]] || return 1
  app_real="$(realpath -- "$app_path")" || return 1
  contents_path="${app_path%/}/Contents"
  plist_path="$contents_path/Info.plist"

  [[ -d "$contents_path" && ! -L "$contents_path" ]] || return 1
  [[ -f "$plist_path" && ! -L "$plist_path" ]] || return 1
  contents_real="$(realpath -- "$contents_path")" || return 1
  plist_real="$(realpath -- "$plist_path")" || return 1
  plist_parent_real="$(realpath -- "$(dirname -- "$plist_path")")" || return 1

  [[ "$contents_real" == "$app_real/Contents" ]] || return 1
  [[ "$plist_parent_real" == "$contents_real" ]] || return 1
  [[ "$plist_real" == "$contents_real/Info.plist" ]]
}

require_safe_mutable_app_info_plist() {
  local app_path="${1:-}"

  mutable_app_info_plist_is_safe "$app_path" && return 0
  fail "Bundle mutation requires a direct, non-symlink Contents/Info.plist contained inside the app: $app_path" || return 1
}

loose_icon_path_is_safe() {
  local resources_dir="$1"
  local icon_path="$2"
  local allow_missing="${3:-false}"
  local app_real
  local resources_real
  local parent_real

  [[ -n "$APP_PATH" && -d "$APP_PATH" ]] || return 1
  [[ -d "$resources_dir" && ! -L "$resources_dir" ]] || return 1
  [[ ! -L "$icon_path" ]] || return 1
  if [[ -e "$icon_path" ]]; then
    [[ -f "$icon_path" ]] || return 1
  else
    [[ "$allow_missing" == true ]] || return 1
  fi

  app_real="$(realpath -- "$APP_PATH")" || return 1
  resources_real="$(realpath -- "$resources_dir")" || return 1
  parent_real="$(realpath -- "$(dirname "$icon_path")")" || return 1
  [[ "$resources_real" == "$app_real/Contents/Resources" ]] || return 1
  [[ "$parent_real" == "$resources_real" ]] || return 1
}

require_safe_loose_icon_path() {
  local label="$1"
  local resources_dir="$2"
  local icon_path="$3"
  local allow_missing="${4:-false}"

  loose_icon_path_is_safe "$resources_dir" "$icon_path" "$allow_missing" && return 0
  fail "$label must be a direct, non-symlink regular file inside the app's Contents/Resources directory: $icon_path" || return 1
}

normalize_icon_candidate() {
  local value="$1"
  if [[ "$value" == *.[iI][cC][nN][sS] ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n%s.icns\n' "$value" "$value"
  fi
}

resolve_icon_target_from_candidates() {
  local resources_dir="$1"
  shift
  local candidates=("$@")
  local candidate
  local normalized

  for candidate in "${candidates[@]+"${candidates[@]}"}"; do
    [[ -n "$candidate" ]] || continue
    while IFS= read -r normalized; do
      [[ -n "$normalized" ]] || continue
      if [[ -e "$resources_dir/$normalized" || -L "$resources_dir/$normalized" ]]; then
        loose_icon_path_is_safe "$resources_dir" "$resources_dir/$normalized" || return 1
        APP_ICON_TARGET="$resources_dir/$normalized"
        APP_ICON_BACKUP="$(strip_icns_extension "$APP_ICON_TARGET")_ugly.icns"
        return 0
      fi
    done < <(normalize_icon_candidate "$candidate")
  done

  local loose_icns=()
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    loose_icns+=("$candidate")
  done < <(find_loose_icns_files "$resources_dir")

  if [[ "${loose_icns[0]+set}" == set && "${#loose_icns[@]}" -eq 1 ]]; then
    loose_icon_path_is_safe "$resources_dir" "${loose_icns[0]}" || return 1
    APP_ICON_TARGET="${loose_icns[0]}"
    APP_ICON_BACKUP="$(strip_icns_extension "$APP_ICON_TARGET")_ugly.icns"
    return 0
  fi

  return 1
}

inspect_app_metadata() {
  local input="$1"
  local value
  local candidate_names=()
  local line

  APP_PATH="$(resolve_app_path "$input")" || return 1
  require_app_bundle_path "$APP_PATH" || return 1
  APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
  APP_RESOURCES_DIR="$APP_PATH/Contents/Resources"
  APP_CF_BUNDLE_ICON_FILE=""
  APP_CF_BUNDLE_ICON_NAME=""
  APP_PRIMARY_ICON_NAME=""
  APP_PRIMARY_ICON_FILES=()
  APP_CAR_FILES=()
  APP_USES_ASSET_CATALOG=false
  APP_ICON_TARGET=""
  APP_ICON_BACKUP=""

  [[ -f "$APP_INFO_PLIST" ]] || fail "Missing Info.plist in $APP_PATH" || return 1

  APP_CF_BUNDLE_ICON_FILE="$(plist_string "$APP_INFO_PLIST" ":CFBundleIconFile")"
  APP_CF_BUNDLE_ICON_NAME="$(plist_string "$APP_INFO_PLIST" ":CFBundleIconName")"
  APP_PRIMARY_ICON_NAME="$(plist_string "$APP_INFO_PLIST" ":CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName")"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    APP_PRIMARY_ICON_FILES+=("$line")
  done < <(plist_array_values "$APP_INFO_PLIST" ":CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles")

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    APP_CAR_FILES+=("$line")
  done < <(find_car_files "$APP_RESOURCES_DIR")

  [[ "${APP_CAR_FILES[0]+set}" == set ]] && APP_USES_ASSET_CATALOG=true

  [[ -n "$APP_CF_BUNDLE_ICON_FILE" ]] && candidate_names+=("$APP_CF_BUNDLE_ICON_FILE")
  [[ -n "$APP_PRIMARY_ICON_NAME" ]] && candidate_names+=("$APP_PRIMARY_ICON_NAME")
  [[ -n "$APP_CF_BUNDLE_ICON_NAME" ]] && candidate_names+=("$APP_CF_BUNDLE_ICON_NAME")
  if [[ "${APP_PRIMARY_ICON_FILES[0]+set}" == set ]]; then
    for value in "${APP_PRIMARY_ICON_FILES[@]}"; do
      candidate_names+=("$value")
    done
  fi

  resolve_icon_target_from_candidates "$APP_RESOURCES_DIR" "${candidate_names[@]+"${candidate_names[@]}"}" || true
}

print_icon_source_summary() {
  if [[ "$APP_USES_ASSET_CATALOG" == true ]]; then
    printf 'asset catalog backed\n'
  elif [[ -n "$APP_ICON_TARGET" ]]; then
    printf 'loose .icns\n'
  else
    printf 'unresolved\n'
  fi
}

resign_app_bundle() {
  local app_path="$1"

  require_app_bundle_path "$app_path" || return 1
  require_safe_mutable_app_info_plist "$app_path" || return 1
  require_tool "$CODESIGN_BIN" "Missing required tool: codesign" || return 1
  run_cmd "$CODESIGN_BIN" --force --deep --sign - "$app_path" || return 1

  if [[ "$ICONFORGE_DRY_RUN" != true ]]; then
    "$CODESIGN_BIN" --verify --deep --strict --all-architectures "$app_path" || {
      fail "Ad hoc signature verification failed for $app_path" || return 1
    }
  fi
}

touch_app_bundle() {
  local app_path="$1"
  local plist_path="$app_path/Contents/Info.plist"

  require_app_bundle_path "$app_path" || return 1
  require_safe_mutable_app_info_plist "$app_path" || return 1
  run_cmd "$TOUCH_BIN" "$app_path" || return 1
  run_cmd "$TOUCH_BIN" "$plist_path" || return 1
}
