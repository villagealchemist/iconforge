#!/usr/bin/env bash

ICONFORGE_CONFIG_PATH_DEFAULT="$HOME/.config/iconforge/config.plist"
ICONFORGE_ICON_ROOT_DEFAULT="$HOME/alchemy/app_icons"

ICONFORGE_CONFIG_PATH=""
ICONFORGE_CONFIG_ICON_ROOT=""
ICONFORGE_CONFIG_APPLICATION_KEYS=()
ICONFORGE_CONFIG_APP_ALIASES=()
ICONFORGE_CONFIG_APP_PATHS=()
ICONFORGE_CONFIG_APP_BUNDLE_IDS=()
ICONFORGE_CONFIG_APP_STRATEGIES=()
ICONFORGE_CONFIG_EXCLUSIONS=()

expand_user_path() {
  local raw_path="$1"

  if [[ "$raw_path" == "~" ]]; then
    printf '%s\n' "$HOME"
    return 0
  fi

  if [[ "${raw_path:0:2}" == "~/" ]]; then
    printf '%s/%s\n' "$HOME" "${raw_path:2}"
    return 0
  fi

  printf '%s\n' "$raw_path"
}

plist_has_key() {
  local plist_path="$1"
  local key_path="$2"

  "$PLIST_BUDDY_BIN" -c "Print $key_path" "$plist_path" >/dev/null 2>&1
}

plist_root_dict_keys() {
  local plist_path="$1"
  local dict_path="$2"

  "$PLIST_BUDDY_BIN" -c "Print $dict_path" "$plist_path" 2>/dev/null | awk '
    /^[[:space:]]*Dict[[:space:]]*\{/ { next }
    /^[[:space:]]*\}[[:space:]]*$/ { next }
    /^[[:space:]]*$/ { next }
    {
      gsub(/^[[:space:]]+/, "", $0)
      if ($0 ~ /=/) {
        split($0, parts, " =")
        print parts[1]
      }
    }
  '
}

config_reset() {
  ICONFORGE_CONFIG_PATH=""
  ICONFORGE_CONFIG_ICON_ROOT=""
  ICONFORGE_CONFIG_APPLICATION_KEYS=()
  ICONFORGE_CONFIG_APP_ALIASES=()
  ICONFORGE_CONFIG_APP_PATHS=()
  ICONFORGE_CONFIG_APP_BUNDLE_IDS=()
  ICONFORGE_CONFIG_APP_STRATEGIES=()
  ICONFORGE_CONFIG_EXCLUSIONS=()
}

config_record_error() {
  local message="$1"
  if [[ -n "${ICONFORGE_CONFIG_ERROR:-}" ]]; then
    ICONFORGE_CONFIG_ERROR="${ICONFORGE_CONFIG_ERROR}"$'\n'"$message"
  else
    ICONFORGE_CONFIG_ERROR="$message"
  fi
}

config_validate_strategy() {
  local app_key="$1"
  local strategy="$2"

  [[ -z "$strategy" ]] && return 0

  case "$strategy" in
    auto|fileicon|internal-icns)
      return 0
      ;;
    *)
      config_record_error "Invalid strategy '$strategy' for application key '$app_key'"
      return 1
      ;;
  esac
}

config_load() {
  local requested_path="${1:-$ICONFORGE_CONFIG_PATH_DEFAULT}"
  local config_path
  local icon_root
  local app_key
  local alias_value
  local app_path
  local bundle_id
  local strategy

  config_reset
  ICONFORGE_CONFIG_ERROR=""
  config_path="$(expand_user_path "$requested_path")"
  ICONFORGE_CONFIG_PATH="$config_path"

  if [[ ! -e "$config_path" ]]; then
    return 0
  fi

  if [[ ! -f "$config_path" ]]; then
    config_record_error "Config path is not a regular file: $config_path"
    return 1
  fi

  "$PLUTIL_BIN" -lint "$config_path" >/dev/null 2>&1 || {
    config_record_error "Config plist is invalid: $config_path"
    return 1
  }

  if plist_has_key "$config_path" ":icon_root"; then
    icon_root="$(plist_string "$config_path" ":icon_root")"
    if [[ -z "$icon_root" ]]; then
      config_record_error "Config key 'icon_root' must not be empty"
    else
      ICONFORGE_CONFIG_ICON_ROOT="$(expand_user_path "$icon_root")"
    fi
  fi

  if plist_has_key "$config_path" ":exclusions"; then
    while IFS= read -r alias_value; do
      [[ -n "$alias_value" ]] || continue
      ICONFORGE_CONFIG_EXCLUSIONS+=("$alias_value")
    done < <(plist_array_values "$config_path" ":exclusions")
  fi

  if plist_has_key "$config_path" ":applications"; then
    while IFS= read -r app_key; do
      [[ -n "$app_key" ]] || continue
      ICONFORGE_CONFIG_APPLICATION_KEYS+=("$app_key")

      if plist_has_key "$config_path" ":applications:$app_key:aliases"; then
        while IFS= read -r alias_value; do
          [[ -n "$alias_value" ]] || continue
          ICONFORGE_CONFIG_APP_ALIASES+=("$app_key"$'\t'"$alias_value")
        done < <(plist_array_values "$config_path" ":applications:$app_key:aliases")
      fi

      app_path="$(plist_string "$config_path" ":applications:$app_key:app_path")"
      if [[ -n "$app_path" ]]; then
        ICONFORGE_CONFIG_APP_PATHS+=("$app_key"$'\t'"$(expand_user_path "$app_path")")
      fi

      bundle_id="$(plist_string "$config_path" ":applications:$app_key:bundle_id")"
      if [[ -n "$bundle_id" ]]; then
        ICONFORGE_CONFIG_APP_BUNDLE_IDS+=("$app_key"$'\t'"$bundle_id")
      fi

      strategy="$(plist_string "$config_path" ":applications:$app_key:strategy")"
      if [[ -n "$strategy" ]]; then
        ICONFORGE_CONFIG_APP_STRATEGIES+=("$app_key"$'\t'"$strategy")
      fi
      config_validate_strategy "$app_key" "$strategy" || true
    done < <(plist_root_dict_keys "$config_path" ":applications")
  fi

  if [[ -n "$ICONFORGE_CONFIG_ERROR" ]]; then
    return 1
  fi

  return 0
}

config_lookup_value() {
  local key="$1"
  local records_name="$2"
  local record

  case "$records_name" in
    ICONFORGE_CONFIG_APP_PATHS)
      for record in "${ICONFORGE_CONFIG_APP_PATHS[@]+"${ICONFORGE_CONFIG_APP_PATHS[@]}"}"; do
        [[ "${record%%$'\t'*}" == "$key" ]] || continue
        printf '%s\n' "${record#*$'\t'}"
        return 0
      done
      ;;
    ICONFORGE_CONFIG_APP_BUNDLE_IDS)
      for record in "${ICONFORGE_CONFIG_APP_BUNDLE_IDS[@]+"${ICONFORGE_CONFIG_APP_BUNDLE_IDS[@]}"}"; do
        [[ "${record%%$'\t'*}" == "$key" ]] || continue
        printf '%s\n' "${record#*$'\t'}"
        return 0
      done
      ;;
    ICONFORGE_CONFIG_APP_STRATEGIES)
      for record in "${ICONFORGE_CONFIG_APP_STRATEGIES[@]+"${ICONFORGE_CONFIG_APP_STRATEGIES[@]}"}"; do
        [[ "${record%%$'\t'*}" == "$key" ]] || continue
        printf '%s\n' "${record#*$'\t'}"
        return 0
      done
      ;;
  esac

  return 1
}

config_get_aliases() {
  local key="$1"
  local record
  for record in "${ICONFORGE_CONFIG_APP_ALIASES[@]+"${ICONFORGE_CONFIG_APP_ALIASES[@]}"}"; do
    [[ "${record%%$'\t'*}" == "$key" ]] || continue
    printf '%s\n' "${record#*$'\t'}"
  done
}

config_is_excluded() {
  local key="$1"
  local exclusion
  for exclusion in "${ICONFORGE_CONFIG_EXCLUSIONS[@]+"${ICONFORGE_CONFIG_EXCLUSIONS[@]}"}"; do
    [[ "$exclusion" == "$key" ]] && return 0
  done
  return 1
}

resolve_icon_root() {
  local cli_root="${1:-}"
  local env_root="${ICONFORGE_ICON_ROOT:-}"
  local config_root="${ICONFORGE_CONFIG_ICON_ROOT:-}"

  if [[ -n "$cli_root" ]]; then
    printf '%s\n' "$(expand_user_path "$cli_root")"
    return 0
  fi

  if [[ -n "$env_root" ]]; then
    printf '%s\n' "$(expand_user_path "$env_root")"
    return 0
  fi

  if [[ -n "$config_root" ]]; then
    printf '%s\n' "$config_root"
    return 0
  fi

  printf '%s\n' "$ICONFORGE_ICON_ROOT_DEFAULT"
}
