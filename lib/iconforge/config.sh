#!/usr/bin/env bash

ICONFORGE_CONFIG_PLIST_KEY="default_directory"
ICONFORGE_DEFAULT_DIRECTORY=""
ICONFORGE_HAS_DEFAULT_DIRECTORY=false

config_help() {
  cat <<'EOF'
Set, get, or unset the default directory used by forge and bulk apply.

Usage:
  iconforge config set default-directory <directory>
  iconforge config get default-directory
  iconforge config unset default-directory

Options:
  -h, --help  Show this help

The saved path is absolute. An explicit forge --output or bulk apply directory
always overrides it. Configuration is stored as data and is never sourced as
shell code.
EOF
}

iconforge_config_directory() {
  local config_home="${XDG_CONFIG_HOME:-}"

  if [[ -z "$config_home" ]]; then
    [[ -n "${HOME:-}" ]] || { fail "HOME is not set; cannot locate IconForge configuration"; return 1; }
    config_home="$HOME/.config"
  fi
  [[ "$config_home" == /* ]] || {
    fail "XDG_CONFIG_HOME must be an absolute path: $config_home" || return 1
  }
  printf '%s/iconforge\n' "${config_home%/}"
}

iconforge_config_file() {
  local config_directory
  config_directory="$(iconforge_config_directory)" || return 1
  printf '%s/config.plist\n' "$config_directory"
}

config_lexical_absolute_path() {
  local raw_path="$1"
  local absolute_path
  local component
  local -a source_parts=()
  local -a normalized_parts=()

  if [[ "$raw_path" == /* ]]; then
    absolute_path="$raw_path"
  else
    absolute_path="$PWD/$raw_path"
  fi

  IFS='/' read -r -a source_parts <<< "$absolute_path"
  for component in "${source_parts[@]+"${source_parts[@]}"}"; do
    case "$component" in
      ''|.) ;;
      ..)
        if [[ "${#normalized_parts[@]}" -gt 0 ]]; then
          unset 'normalized_parts[${#normalized_parts[@]}-1]'
        fi
        ;;
      *) normalized_parts+=("$component") ;;
    esac
  done

  if [[ "${#normalized_parts[@]}" -eq 0 ]]; then
    printf '/\n'
  else
    printf '/%s\n' "$(join_by '/' "${normalized_parts[@]}")"
  fi
}

config_canonical_directory_path() {
  local raw_path="$1"
  local absolute_path
  local existing_prefix
  local canonical_prefix
  local parent_directory
  local remainder=""
  local leaf

  if [[ "$raw_path" == /* ]]; then
    absolute_path="$raw_path"
  else
    absolute_path="$PWD/$raw_path"
  fi
  existing_prefix="$absolute_path"
  while [[ ! -e "$existing_prefix" && ! -L "$existing_prefix" ]]; do
    leaf="$(basename -- "$existing_prefix")"
    if [[ -n "$remainder" ]]; then
      remainder="$leaf/$remainder"
    else
      remainder="$leaf"
    fi
    [[ "$existing_prefix" != / ]] || break
    existing_prefix="$(dirname -- "$existing_prefix")"
  done

  if [[ -L "$existing_prefix" && ! -e "$existing_prefix" ]]; then
    fail "Default directory contains a dangling symlink: $existing_prefix" || return 1
  fi
  if [[ -n "$remainder" && ! -d "$existing_prefix" ]]; then
    fail "Default directory ancestor is not a directory: $existing_prefix" || return 1
  fi

  if [[ -d "$existing_prefix" ]]; then
    canonical_prefix="$(cd -P "$existing_prefix" && pwd)" || return 1
  else
    parent_directory="$(cd -P "$(dirname -- "$existing_prefix")" && pwd)" || return 1
    canonical_prefix="$parent_directory/$(basename -- "$existing_prefix")"
  fi

  if [[ -n "$remainder" ]]; then
    config_lexical_absolute_path "${canonical_prefix%/}/$remainder"
  else
    printf '%s\n' "$canonical_prefix"
  fi
}

config_validate_file_for_read() {
  local config_file="$1"

  [[ ! -L "$config_file" ]] || {
    fail "IconForge configuration must not be a symlink: $config_file" || return 1
  }
  [[ -f "$config_file" ]] || {
    fail "IconForge configuration is not a regular file: $config_file" || return 1
  }
}

load_iconforge_config() {
  local config_file
  local config_xml=""
  local root_type=""
  local key_count=""
  local value_type=""
  local key_xpath='/plist/dict/key[text()="default_directory"]'
  local value_xpath=""
  local value=""
  local value_with_sentinel=""
  local canonical_value=""

  ICONFORGE_DEFAULT_DIRECTORY=""
  ICONFORGE_HAS_DEFAULT_DIRECTORY=false
  config_file="$(iconforge_config_file)" || return 1
  [[ -e "$config_file" || -L "$config_file" ]] || return 0
  config_validate_file_for_read "$config_file" || return 1
  require_tool /usr/bin/plutil "Missing required tool: plutil" || return 1
  require_tool /usr/bin/xmllint "Missing required tool: xmllint" || return 1
  /usr/bin/plutil -lint "$config_file" >/dev/null 2>&1 || {
    fail "IconForge configuration is not a valid property list: $config_file" || return 1
  }
  config_xml="$(/usr/bin/plutil -convert xml1 -o - "$config_file" 2>/dev/null)" || {
    fail "Could not decode IconForge configuration: $config_file" || return 1
  }
  root_type="$(/usr/bin/xmllint --xpath 'name(/plist/*[1])' - <<< "$config_xml" 2>/dev/null)" || {
    fail "Could not inspect IconForge configuration: $config_file" || return 1
  }
  [[ "$root_type" == dict ]] || {
    fail "IconForge configuration root must be a dictionary: $config_file" || return 1
  }
  key_count="$(/usr/bin/xmllint --xpath "count($key_xpath)" - <<< "$config_xml" 2>/dev/null)" || {
    fail "Could not inspect IconForge configuration: $config_file" || return 1
  }
  if [[ "$key_count" == 0 ]]; then
    return 0
  fi
  [[ "$key_count" == 1 ]] || {
    fail "IconForge configuration contains duplicate '$ICONFORGE_CONFIG_PLIST_KEY' keys" || return 1
  }
  value_xpath="($key_xpath)[1]/following-sibling::*[1]"
  value_type="$(/usr/bin/xmllint --xpath "name($value_xpath)" - <<< "$config_xml" 2>/dev/null)" || {
    fail "Could not inspect IconForge configuration: $config_file" || return 1
  }
  [[ "$value_type" == string ]] || {
    fail "IconForge configuration key '$ICONFORGE_CONFIG_PLIST_KEY' must be a string" || return 1
  }
  value_with_sentinel="$(
    /usr/bin/xmllint --xpath "string($value_xpath)" - <<< "$config_xml" 2>/dev/null
    xpath_status=$?
    printf '\034'
    exit "$xpath_status"
  )" || {
    fail "Could not read IconForge configuration: $config_file" || return 1
  }
  value="${value_with_sentinel%$'\034'}"
  [[ "$value" != *$'\n' ]] || value="${value%$'\n'}"
  [[ "$value" != *$'\n'* ]] || {
    fail "IconForge configuration key '$ICONFORGE_CONFIG_PLIST_KEY' must be a single-line string" || return 1
  }
  [[ -n "$value" && "$value" == /* && "$value" != / ]] || {
    fail "Configured default directory must be one absolute path" || return 1
  }
  canonical_value="$(config_canonical_directory_path "$value")" || {
    fail "Could not resolve configured default directory: $value" || return 1
  }
  [[ "$canonical_value" != / ]] || {
    fail "Configured default directory resolves to the filesystem root" || return 1
  }
  if [[ -e "$canonical_value" && ! -d "$canonical_value" ]]; then
    fail "Configured default directory is not a directory: $canonical_value" || return 1
  fi

  ICONFORGE_DEFAULT_DIRECTORY="$canonical_value"
  ICONFORGE_HAS_DEFAULT_DIRECTORY=true
}

config_set_default_directory() {
  local requested_directory="$1"
  local canonical_directory
  local config_file
  local config_directory
  local temporary_file=""

  require_nonempty_path "Default directory" "$requested_directory" || return 1
  [[ "$requested_directory" != *$'\n'* ]] || {
    fail "Default directory must not contain a newline" || return 1
  }
  canonical_directory="$(config_canonical_directory_path "$requested_directory")" || {
    fail "Could not resolve default directory: $requested_directory" || return 1
  }
  [[ "$canonical_directory" != / ]] || {
    fail "Default directory must not be the filesystem root" || return 1
  }
  if [[ -e "$canonical_directory" && ! -d "$canonical_directory" ]]; then
    fail "Default directory path is not a directory: $canonical_directory" || return 1
  fi

  config_file="$(iconforge_config_file)" || return 1
  config_directory="$(dirname -- "$config_file")"
  if [[ -e "$config_directory" && ! -d "$config_directory" ]]; then
    fail "IconForge configuration directory path is not a directory: $config_directory" || return 1
  fi
  if [[ -e "$config_file" || -L "$config_file" ]]; then
    config_validate_file_for_read "$config_file" || return 1
  fi

  mkdir -p "$config_directory" || {
    fail "Could not create IconForge configuration directory: $config_directory" || return 1
  }
  temporary_file="$(mktemp "$config_directory/.config.plist.XXXXXX")" || {
    fail "Could not create a temporary IconForge configuration file" || return 1
  }
  if ! /usr/bin/plutil -create xml1 "$temporary_file" >/dev/null 2>&1 ||
     ! /usr/bin/plutil -insert "$ICONFORGE_CONFIG_PLIST_KEY" -string "$canonical_directory" "$temporary_file" >/dev/null 2>&1 ||
     ! chmod 600 "$temporary_file" ||
     ! mv -f "$temporary_file" "$config_file"; then
    rm -f "$temporary_file"
    fail "Could not save IconForge configuration: $config_file" || return 1
  fi

  printf 'Default icon directory: %s\n' "$canonical_directory"
}

config_get_default_directory() {
  load_iconforge_config || return 1
  if [[ "$ICONFORGE_HAS_DEFAULT_DIRECTORY" != true ]]; then
    note "Default icon directory is not set"
    return 1
  fi
  printf '%s\n' "$ICONFORGE_DEFAULT_DIRECTORY"
}

config_unset_default_directory() {
  local config_file

  config_file="$(iconforge_config_file)" || return 1
  if [[ ! -e "$config_file" && ! -L "$config_file" ]]; then
    printf 'Default icon directory is not set\n'
    return 0
  fi
  config_validate_file_for_read "$config_file" || return 1
  rm -f "$config_file" || {
    fail "Could not remove IconForge configuration: $config_file" || return 1
  }
  printf 'Default icon directory unset\n'
}

cmd_config() {
  local options_done=false
  local -a operands=()

  while [[ $# -gt 0 ]]; do
    if [[ "$options_done" != true ]]; then
      case "$1" in
        --) options_done=true; shift; continue ;;
        -h|--help) config_help; return 0 ;;
        --*=*) usage_fail "Option values must be separate tokens: $1"; return 2 ;;
        -*) usage_fail "Unknown config option: $1"; return 2 ;;
      esac
    fi
    operands+=("$1")
    shift
  done

  [[ "${#operands[@]}" -gt 0 ]] || { config_help; return 2; }
  case "${operands[0]}" in
    set)
      [[ "${#operands[@]}" -eq 3 && "${operands[1]}" == default-directory && -n "${operands[2]}" ]] || {
        usage_fail "Usage: iconforge config set default-directory <directory>" || return 2
      }
      config_set_default_directory "${operands[2]}"
      ;;
    get)
      [[ "${#operands[@]}" -eq 2 && "${operands[1]}" == default-directory ]] || {
        usage_fail "Usage: iconforge config get default-directory" || return 2
      }
      config_get_default_directory
      ;;
    unset)
      [[ "${#operands[@]}" -eq 2 && "${operands[1]}" == default-directory ]] || {
        usage_fail "Usage: iconforge config unset default-directory" || return 2
      }
      config_unset_default_directory
      ;;
    *)
      usage_fail "Unknown config action: ${operands[0]}" || return 2
      ;;
  esac
}
