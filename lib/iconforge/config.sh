#!/usr/bin/env bash

# Configuration is data, never executable shell. Legacy consumers still use
# load_iconforge_config; the public CLI resolves a purpose-specific directory.
ICONFORGE_CONFIG_PLIST_KEY="default_directory"
ICONFORGE_DEFAULT_DIRECTORY=""
ICONFORGE_HAS_DEFAULT_DIRECTORY=false
CONFIG_XML=""
CONFIG_VALUE=""
CONFIG_HAS_VALUE=false
CONFIG_DIRECTORY=""
CONFIG_DIRECTORY_SOURCE=""

config_help() {
  cat <<'HELP'
Choose where icons are made and where finished icons live.

Usage:
  iconforge config set the-forge <directory>
  iconforge config set the-hearth <directory>
  iconforge config get <key>
  iconforge config unset <key>
  iconforge config show
  iconforge config path
  iconforge config set default-directory <directory>
  iconforge config get default-directory
  iconforge config unset default-directory

Keys:
  the-forge          Default forge output directory
  the-hearth         Finished ICNS library for single and bulk apply
  default-directory Legacy fallback for both, unless separately configured

Paths are independent, absolute, and do not need to exist yet. Setting a path
never creates that directory. Explicit --output, --icon, or --from wins.
get prints the saved value; show explains effective values and their sources.
unset removes only the named preference, preserving all other settings.

Options:
  -h, --help  Show this help
HELP
}

iconforge_config_directory() {
  local config_home="${XDG_CONFIG_HOME:-}"
  if [[ -z "$config_home" ]]; then
    [[ -n "${HOME:-}" ]] || { fail "HOME is not set; cannot locate IconForge configuration"; return 1; }
    config_home="$HOME/.config"
  fi
  [[ "$config_home" == /* ]] || { fail "XDG_CONFIG_HOME must be an absolute path: $config_home"; return 1; }
  printf '%s/iconforge\n' "${config_home%/}"
}

iconforge_config_file() {
  local config_directory
  config_directory="$(iconforge_config_directory)" || return 1
  printf '%s/config.plist\n' "$config_directory"
}

config_lexical_absolute_path() {
  local raw_path="$1" absolute_path component
  local -a source_parts=() normalized_parts=()
  if [[ "$raw_path" == /* ]]; then absolute_path="$raw_path"; else absolute_path="$PWD/$raw_path"; fi
  IFS='/' read -r -a source_parts <<< "$absolute_path"
  for component in "${source_parts[@]+"${source_parts[@]}"}"; do
    case "$component" in
      ''|.) ;;
      ..) if [[ "${#normalized_parts[@]}" -gt 0 ]]; then unset 'normalized_parts[${#normalized_parts[@]}-1]'; fi ;;
      *) normalized_parts+=("$component") ;;
    esac
  done
  if [[ "${#normalized_parts[@]}" -eq 0 ]]; then printf '/\n'; else printf '/%s\n' "$(join_by '/' "${normalized_parts[@]}")"; fi
}

config_canonical_directory_path() {
  local raw_path="$1" absolute_path existing_prefix canonical_prefix parent_directory remainder="" leaf
  # Quoted ~/... is common in CLI configuration. Expand it without eval.
  case "$raw_path" in
    '~') raw_path="${HOME:?HOME is not set}" ;;
    '~/'*) raw_path="${HOME:?HOME is not set}/${raw_path#\~/}" ;;
  esac
  if [[ "$raw_path" == /* ]]; then absolute_path="$raw_path"; else absolute_path="$PWD/$raw_path"; fi
  existing_prefix="$absolute_path"
  while [[ ! -e "$existing_prefix" && ! -L "$existing_prefix" ]]; do
    leaf="$(basename -- "$existing_prefix")"
    if [[ -n "$remainder" ]]; then remainder="$leaf/$remainder"; else remainder="$leaf"; fi
    [[ "$existing_prefix" != / ]] || break
    existing_prefix="$(dirname -- "$existing_prefix")"
  done
  [[ ! -L "$existing_prefix" || -e "$existing_prefix" ]] || { fail "Default directory contains a dangling symlink: $existing_prefix"; return 1; }
  [[ -z "$remainder" || -d "$existing_prefix" ]] || { fail "Default directory ancestor is not a directory: $existing_prefix"; return 1; }
  if [[ -d "$existing_prefix" ]]; then
    canonical_prefix="$(cd -P "$existing_prefix" && pwd)" || return 1
  else
    parent_directory="$(cd -P "$(dirname -- "$existing_prefix")" && pwd)" || return 1
    canonical_prefix="$parent_directory/$(basename -- "$existing_prefix")"
  fi
  if [[ -n "$remainder" ]]; then config_lexical_absolute_path "${canonical_prefix%/}/$remainder"; else printf '%s\n' "$canonical_prefix"; fi
}

config_validate_file_for_read() {
  [[ ! -L "$1" ]] || { fail "IconForge configuration must not be a symlink: $1"; return 1; }
  [[ -f "$1" ]] || { fail "IconForge configuration is not a regular file: $1"; return 1; }
}

config_key() {
  case "$1" in
    the-forge) printf 'the_forge\n' ;;
    the-hearth) printf 'the_hearth\n' ;;
    default-directory) printf 'default_directory\n' ;;
    *) usage_fail "Unknown config key '$1'. Choose the-forge, the-hearth, or default-directory."; return 2 ;;
  esac
}

config_read_document() {
  local config_file root_type
  CONFIG_XML=""
  config_file="$(iconforge_config_file)" || return 1
  [[ -e "$config_file" || -L "$config_file" ]] || return 0
  config_validate_file_for_read "$config_file" || return 1
  require_tool /usr/bin/plutil "Missing required tool: plutil" || return 1
  require_tool /usr/bin/xmllint "Missing required tool: xmllint" || return 1
  /usr/bin/plutil -lint "$config_file" >/dev/null 2>&1 || { fail "IconForge configuration is not a valid property list: $config_file"; return 1; }
  CONFIG_XML="$(/usr/bin/plutil -convert xml1 -o - "$config_file" 2>/dev/null)" || { fail "Could not decode IconForge configuration: $config_file"; return 1; }
  root_type="$(/usr/bin/xmllint --nonet --xpath 'name(/plist/*[1])' - <<< "$CONFIG_XML" 2>/dev/null)" || return 1
  [[ "$root_type" == dict ]] || { fail "IconForge configuration root must be a dictionary: $config_file"; return 1; }
}

config_read_saved_directory() {
  local key="$1" plist_key key_xpath key_count value_xpath value_type sentinel canonical
  CONFIG_VALUE=""; CONFIG_HAS_VALUE=false
  plist_key="$(config_key "$key")" || return $?
  config_read_document || return 1
  [[ -n "$CONFIG_XML" ]] || return 0
  key_xpath="/plist/dict/key[text()='$plist_key']"
  key_count="$(/usr/bin/xmllint --nonet --xpath "count($key_xpath)" - <<< "$CONFIG_XML" 2>/dev/null)" || return 1
  [[ "$key_count" != 0 ]] || return 0
  [[ "$key_count" == 1 ]] || { fail "IconForge configuration contains duplicate '$plist_key' keys"; return 1; }
  value_xpath="($key_xpath)[1]/following-sibling::*[1]"
  value_type="$(/usr/bin/xmllint --nonet --xpath "name($value_xpath)" - <<< "$CONFIG_XML" 2>/dev/null)" || return 1
  [[ "$value_type" == string ]] || { fail "IconForge configuration key '$plist_key' must be a string"; return 1; }
  sentinel="$(/usr/bin/xmllint --nonet --xpath "string($value_xpath)" - <<< "$CONFIG_XML" 2>/dev/null; status=$?; printf '\034'; exit "$status")" || return 1
  CONFIG_VALUE="${sentinel%$'\034'}"
  # xmllint adds one newline when printing an XPath string.
  [[ "$CONFIG_VALUE" != *$'\n' ]] || CONFIG_VALUE="${CONFIG_VALUE%$'\n'}"
  [[ "$CONFIG_VALUE" != *$'\n'* ]] || { fail "IconForge configuration key '$plist_key' must be a single-line string"; return 1; }
  [[ -n "$CONFIG_VALUE" && "$CONFIG_VALUE" == /* && "$CONFIG_VALUE" != / ]] || {
    fail "Configured $key must be one absolute path (a single-line string)"; return 1;
  }
  canonical="$(config_canonical_directory_path "$CONFIG_VALUE")" || return 1
  [[ "$canonical" != / ]] || { fail "Configured $key resolves to the filesystem root"; return 1; }
  [[ ! -e "$canonical" || -d "$canonical" ]] || { fail "Configured $key is not a directory: $canonical"; return 1; }
  CONFIG_VALUE="$canonical"; CONFIG_HAS_VALUE=true
}

# Purpose-aware lookup. Missing the-forge falls back to cwd; missing the-hearth
# stays unset. No implicit filesystem scan or cross-coupling between the keys.
config_effective_directory() {
  local purpose="$1"
  CONFIG_DIRECTORY=""; CONFIG_DIRECTORY_SOURCE="unset"
  config_read_saved_directory "$purpose" || return $?
  if [[ "$CONFIG_HAS_VALUE" == true ]]; then
    CONFIG_DIRECTORY="$CONFIG_VALUE"; CONFIG_DIRECTORY_SOURCE="$purpose"; return 0
  fi
  config_read_saved_directory default-directory || return 1
  if [[ "$CONFIG_HAS_VALUE" == true ]]; then
    CONFIG_DIRECTORY="$CONFIG_VALUE"; CONFIG_DIRECTORY_SOURCE="default-directory (legacy)"
  elif [[ "$purpose" == the-forge ]]; then
    CONFIG_DIRECTORY="$PWD"; CONFIG_DIRECTORY_SOURCE="current directory"
  fi
}

# Compatibility API for existing engine callers; the public CLI always sends
# explicitly resolved paths to those engines.
load_iconforge_config() {
  ICONFORGE_DEFAULT_DIRECTORY=""; ICONFORGE_HAS_DEFAULT_DIRECTORY=false
  config_read_saved_directory default-directory || return 1
  ICONFORGE_DEFAULT_DIRECTORY="$CONFIG_VALUE"; ICONFORGE_HAS_DEFAULT_DIRECTORY="$CONFIG_HAS_VALUE"
}

config_write_directory() (
  # Subshell scopes cleanup traps so configuration cannot replace engine traps.
  local action="$1" key="$2" requested="${3:-}" canonical="" plist_key
  local config_file config_directory temporary_file="" lock_directory count label="$key"
  [[ "$key" != default-directory ]] || label="Default icon directory"
  plist_key="$(config_key "$key")" || exit $?
  if [[ "$action" == set ]]; then
    require_nonempty_path "Default directory" "$requested" || exit 1
    [[ "$requested" != *$'\n'* ]] || { fail "Default directory must not contain a newline"; exit 1; }
    canonical="$(config_canonical_directory_path "$requested")" || exit 1
    [[ "$canonical" != / ]] || { fail "Default directory must not be the filesystem root"; exit 1; }
    [[ ! -e "$canonical" || -d "$canonical" ]] || { fail "Default directory path is not a directory: $canonical"; exit 1; }
  fi
  config_file="$(iconforge_config_file)" || exit 1
  config_directory="$(dirname -- "$config_file")"
  if [[ "$action" == unset && ! -e "$config_file" && ! -L "$config_file" ]]; then
    printf '%s is not set\n' "$label"; exit 0
  fi
  mkdir -p "$config_directory" || { fail "Could not create IconForge configuration directory: $config_directory"; exit 1; }
  lock_directory="$config_directory/.config.lock"
  mkdir "$lock_directory" 2>/dev/null || { fail "Configuration is locked by another update: $lock_directory. If an earlier process was interrupted, remove its stale empty lock directory after checking it is no longer running."; exit 1; }
  trap '[[ -z "$temporary_file" ]] || rm -f "$temporary_file"; rmdir "$lock_directory" 2>/dev/null || true' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  config_read_document || exit 1
  if [[ "$action" == unset && -n "$CONFIG_XML" ]]; then
    count="$(/usr/bin/xmllint --nonet --xpath "count(/plist/dict/key[text()='$plist_key'])" - <<< "$CONFIG_XML" 2>/dev/null)" || exit 1
    [[ "$count" != 0 ]] || { printf '%s is not set\n' "$label"; exit 0; }
  fi
  temporary_file="$(mktemp "$config_directory/.config.plist.XXXXXX")" || exit 1
  if [[ -n "$CONFIG_XML" ]]; then
    printf '%s\n' "$CONFIG_XML" > "$temporary_file" || exit 1
  else
    /usr/bin/plutil -create xml1 "$temporary_file" >/dev/null 2>&1 || exit 1
  fi
  # Do not reset the plist: preferences unknown to this version also survive.
  if [[ "$action" == set ]]; then
    /usr/bin/plutil -remove "$plist_key" "$temporary_file" >/dev/null 2>&1 || true
    /usr/bin/plutil -insert "$plist_key" -string "$canonical" "$temporary_file" >/dev/null 2>&1 || exit 1
  else
    /usr/bin/plutil -remove "$plist_key" "$temporary_file" >/dev/null 2>&1 || true
  fi
  /usr/bin/plutil -lint "$temporary_file" >/dev/null 2>&1 || exit 1
  chmod 600 "$temporary_file" || exit 1
  [[ ! -e "$config_file" && ! -L "$config_file" ]] || config_validate_file_for_read "$config_file" || exit 1
  if [[ "$action" == unset ]] && [[ "$(/usr/bin/xmllint --nonet --xpath 'count(/plist/dict/key)' "$temporary_file" 2>/dev/null)" == 0 ]]; then
    rm -f "$config_file" || exit 1
  else
    mv -f "$temporary_file" "$config_file" || { fail "Could not save IconForge configuration: $config_file"; exit 1; }
    temporary_file=""
  fi
  if [[ "$action" == set ]]; then printf '%s: %s\n' "$label" "$canonical"; else printf '%s unset\n' "$label"; fi
)

config_set_default_directory() { config_write_directory set default-directory "$1"; }
config_get_default_directory() {
  load_iconforge_config || return 1
  [[ "$ICONFORGE_HAS_DEFAULT_DIRECTORY" == true ]] || { note "Default icon directory is not set"; return 1; }
  printf '%s\n' "$ICONFORGE_DEFAULT_DIRECTORY"
}
config_unset_default_directory() { config_write_directory unset default-directory; }

config_show() {
  local key
  printf 'Configuration: %s\n\n' "$(iconforge_config_file)"
  for key in the-forge the-hearth; do
    config_effective_directory "$key" || return 1
    printf '%-12s %s\n' "$key" "${CONFIG_DIRECTORY:-(not configured)}"
    printf '             source: %s\n' "$CONFIG_DIRECTORY_SOURCE"
  done
}

cmd_config() {
  local options_done=false
  local -a operands=()
  while [[ $# -gt 0 ]]; do
    if [[ "$options_done" != true ]]; then
      case "$1" in
        --) options_done=true; shift; continue ;;
        -h|--help) config_help; return 0 ;;
        -*) usage_fail "Unknown config option: $1"; return 2 ;;
      esac
    fi
    operands+=("$1"); shift
  done
  [[ "${#operands[@]}" -gt 0 ]] || { config_help; return 2; }
  case "${operands[0]}" in
    set)
      [[ "${#operands[@]}" -eq 3 && -n "${operands[2]}" ]] || { usage_fail "Usage: iconforge config set <key> <directory>"; return 2; }
      config_write_directory set "${operands[1]}" "${operands[2]}"
      ;;
    get)
      [[ "${#operands[@]}" -eq 2 ]] || { usage_fail "Usage: iconforge config get <key>"; return 2; }
      [[ "${operands[1]}" != default-directory ]] || { config_get_default_directory; return $?; }
      config_read_saved_directory "${operands[1]}" || return $?
      [[ "$CONFIG_HAS_VALUE" == true ]] || { note "${operands[1]} is not set; use iconforge config show to see fallbacks"; return 1; }
      printf '%s\n' "$CONFIG_VALUE"
      ;;
    unset)
      [[ "${#operands[@]}" -eq 2 ]] || { usage_fail "Usage: iconforge config unset <key>"; return 2; }
      config_write_directory unset "${operands[1]}"
      ;;
    show|path)
      [[ "${#operands[@]}" -eq 1 ]] || { usage_fail "${operands[0]} does not accept arguments"; return 2; }
      if [[ "${operands[0]}" == show ]]; then config_show; else iconforge_config_file; fi
      ;;
    *) usage_fail "Unknown config action: ${operands[0]}"; return 2 ;;
  esac
}
