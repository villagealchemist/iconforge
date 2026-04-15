#!/usr/bin/env bash

ICONFORGE_VERSION="2.0.0"

if ! command -v realpath >/dev/null 2>&1; then
  realpath() {
    if [[ -d "$1" ]]; then
      (cd "$1" && pwd)
    else
      echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    fi
  }
fi

ICONFORGE_ROOT="${ICONFORGE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ICONFORGE_PROCESSOR="${ICONFORGE_PROCESSOR:-$ICONFORGE_ROOT/iconforge-processor/iconforge-processor}"

PLIST_BUDDY_BIN="${ICONFORGE_PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"
PLUTIL_BIN="${ICONFORGE_PLUTIL_BIN:-/usr/bin/plutil}"
CODESIGN_BIN="${ICONFORGE_CODESIGN_BIN:-codesign}"
ICONUTIL_BIN="${ICONFORGE_ICONUTIL_BIN:-iconutil}"
TOUCH_BIN="${ICONFORGE_TOUCH_BIN:-touch}"
KILLALL_BIN="${ICONFORGE_KILLALL_BIN:-killall}"
RM_BIN="${ICONFORGE_RM_BIN:-rm}"

CONFIG_FILE="$HOME/.iconforgerc"
PROJECT_CONFIG="$ICONFORGE_ROOT/.iconforge.env"
LOCAL_CONFIG="$ICONFORGE_ROOT/.iconforge.local.env"

CUSTOM_OUTPUT="${CUSTOM_OUTPUT:-}"
KEEP_PNG="${KEEP_PNG:-false}"
RECURSIVE="${RECURSIVE:-false}"
SUPPRESS_WARNINGS="${SUPPRESS_WARNINGS:-false}"

[[ -f "$PROJECT_CONFIG" ]] && source "$PROJECT_CONFIG"
[[ -f "$LOCAL_CONFIG" ]] && source "$LOCAL_CONFIG"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

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
APP_ICON_TARGET_SOURCE=""
APP_ICON_BACKUP=""
APP_CF_BUNDLE_ICONS_RAW=""

stderr() {
  printf '%s\n' "$*" >&2
}

fail() {
  stderr "Error: $*"
  return 1
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

require_processor() {
  [[ -x "$ICONFORGE_PROCESSOR" ]] || fail "iconforge-processor not found at $ICONFORGE_PROCESSOR"
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

_dedupe_push() {
  local value="$1"
  shift
  local existing
  for existing in "$@"; do
    [[ "$existing" == "$value" ]] && return 1
  done
  return 0
}

resolve_app_path() {
  local input="$1"
  local normalized="$input"
  local candidate
  local root
  local match
  local matches=()

  if [[ -d "$input" ]]; then
    if [[ -f "$input/Contents/Info.plist" ]]; then
      realpath "$input"
      return 0
    fi
  fi

  if [[ "$normalized" != *.app ]]; then
    normalized="${normalized}.app"
  fi

  for candidate in "$PWD/$normalized" "$HOME/Applications/$normalized" "/Applications/$normalized" "/System/Applications/$normalized"; do
    if [[ -d "$candidate" && -f "$candidate/Contents/Info.plist" ]]; then
      candidate="$(realpath "$candidate")"
      if _dedupe_push "$candidate" "${matches[@]}"; then
        matches+=("$candidate")
      fi
    fi
  done

  for root in "$PWD" "$HOME/Applications" "/Applications" "/System/Applications"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      match="$(realpath "$match")"
      if _dedupe_push "$match" "${matches[@]}"; then
        matches+=("$match")
      fi
    done < <(find "$root" -maxdepth 2 -type d -iname "$normalized" -print 2>/dev/null || true)
  done

  case "${#matches[@]}" in
    0)
      fail "Could not resolve app bundle: $input" || return 1
      ;;
    1)
      printf '%s\n' "${matches[0]}"
      ;;
    *)
      stderr "Error: App name is ambiguous: $input"
      stderr "Matches:"
      printf '%s\n' "${matches[@]}" >&2
      return 1
      ;;
  esac
}

find_car_files() {
  local resources_dir="$1"
  [[ -d "$resources_dir" ]] || return 0
  find "$resources_dir" -maxdepth 1 -type f \( -name '*.car' -o -name 'Assets.car' \) -print 2>/dev/null | sort
}

find_loose_icns_files() {
  local resources_dir="$1"
  [[ -d "$resources_dir" ]] || return 0
  find "$resources_dir" -maxdepth 1 -type f -name '*.icns' ! -name '*_ugly.icns' -print 2>/dev/null | sort
}

normalize_icon_candidate() {
  local value="$1"
  if [[ "$value" == *.icns ]]; then
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

  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    while IFS= read -r normalized; do
      [[ -n "$normalized" ]] || continue
      if [[ -f "$resources_dir/$normalized" ]]; then
        APP_ICON_TARGET="$resources_dir/$normalized"
        APP_ICON_TARGET_SOURCE="$candidate"
        APP_ICON_BACKUP="${APP_ICON_TARGET%.icns}_ugly.icns"
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
    APP_ICON_TARGET="${loose_icns[0]}"
    APP_ICON_TARGET_SOURCE="inferred-single-icns"
    APP_ICON_BACKUP="${APP_ICON_TARGET%.icns}_ugly.icns"
    return 0
  fi

  return 1
}

inspect_app_metadata() {
  local input="$1"
  local resolved
  local value
  local candidate_names=()
  local line

  APP_PATH="$(resolve_app_path "$input")" || return 1
  APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
  APP_RESOURCES_DIR="$APP_PATH/Contents/Resources"
  APP_CF_BUNDLE_ICON_FILE=""
  APP_CF_BUNDLE_ICON_NAME=""
  APP_PRIMARY_ICON_NAME=""
  APP_PRIMARY_ICON_FILES=()
  APP_CAR_FILES=()
  APP_USES_ASSET_CATALOG=false
  APP_ICON_TARGET=""
  APP_ICON_TARGET_SOURCE=""
  APP_ICON_BACKUP=""
  APP_CF_BUNDLE_ICONS_RAW=""

  [[ -f "$APP_INFO_PLIST" ]] || fail "Missing Info.plist in $APP_PATH" || return 1

  APP_CF_BUNDLE_ICON_FILE="$(plist_string "$APP_INFO_PLIST" ":CFBundleIconFile")"
  APP_CF_BUNDLE_ICON_NAME="$(plist_string "$APP_INFO_PLIST" ":CFBundleIconName")"
  APP_PRIMARY_ICON_NAME="$(plist_string "$APP_INFO_PLIST" ":CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName")"
  APP_CF_BUNDLE_ICONS_RAW="$(plist_print "$APP_INFO_PLIST" ":CFBundleIcons")"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    APP_PRIMARY_ICON_FILES+=("$line")
  done < <(plist_array_values "$APP_INFO_PLIST" ":CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles")

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    APP_CAR_FILES+=("$line")
  done < <(find_car_files "$APP_RESOURCES_DIR")

  [[ "${APP_CAR_FILES[0]+set}" == set && ( -n "$APP_CF_BUNDLE_ICON_NAME" || -n "$APP_PRIMARY_ICON_NAME" ) ]] && APP_USES_ASSET_CATALOG=true

  [[ -n "$APP_CF_BUNDLE_ICON_FILE" ]] && candidate_names+=("$APP_CF_BUNDLE_ICON_FILE")
  [[ -n "$APP_PRIMARY_ICON_NAME" ]] && candidate_names+=("$APP_PRIMARY_ICON_NAME")
  [[ -n "$APP_CF_BUNDLE_ICON_NAME" ]] && candidate_names+=("$APP_CF_BUNDLE_ICON_NAME")
  if [[ "${APP_PRIMARY_ICON_FILES[0]+set}" == set ]]; then
    for value in "${APP_PRIMARY_ICON_FILES[@]}"; do
      candidate_names+=("$value")
    done
  fi

  resolve_icon_target_from_candidates "$APP_RESOURCES_DIR" "${candidate_names[@]}" || true
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

  require_tool "$CODESIGN_BIN" "Missing required tool: codesign"
  run_cmd "$CODESIGN_BIN" --force --deep --sign - "$app_path"
}

touch_app_bundle() {
  local app_path="$1"
  local plist_path="$app_path/Contents/Info.plist"

  run_cmd "$TOUCH_BIN" "$app_path"
  [[ -f "$plist_path" ]] && run_cmd "$TOUCH_BIN" "$plist_path"
}

find_restore_backup() {
  if [[ -n "$APP_ICON_BACKUP" && -f "$APP_ICON_BACKUP" ]]; then
    printf '%s\n' "$APP_ICON_BACKUP"
    return 0
  fi

  local backups=()
  local match
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    backups+=("$match")
  done < <(find "$APP_RESOURCES_DIR" -maxdepth 1 -type f -name '*_ugly.icns' -print 2>/dev/null | sort)

  if [[ "${#backups[@]}" -eq 1 ]]; then
    printf '%s\n' "${backups[0]}"
    return 0
  fi

  return 1
}
