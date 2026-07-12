#!/usr/bin/env bash

strategy_validate_name() {
  local strategy_name="$1"

  case "$strategy_name" in
    auto|fileicon|internal-icns)
      return 0
      ;;
    *)
      fail "Unknown strategy: $strategy_name" || return 1
      ;;
  esac
}

strategy_requires_bundle_refresh() {
  local strategy_name="$1"

  case "$strategy_name" in
    internal-icns)
      return 0
      ;;
  esac

  return 1
}

select_apply_strategy() {
  local requested_strategy="${1:-auto}"

  [[ -n "$requested_strategy" ]] || requested_strategy="auto"
  strategy_validate_name "$requested_strategy" || return 1

  case "$requested_strategy" in
    internal-icns)
      require_nonempty_path "Loose icon target path" "$APP_ICON_TARGET" || return 1
      require_existing_file_path "Loose icon target" "$APP_ICON_TARGET" || return 1
      printf 'internal-icns\n'
      return 0
      ;;
    fileicon)
      require_tool "$FILEICON_BIN" "Missing required tool: fileicon" || return 1
      printf 'fileicon\n'
      return 0
      ;;
  esac

  if [[ "$APP_USES_ASSET_CATALOG" == true ]]; then
    if strategy_fileicon_available; then
      printf 'fileicon\n'
      return 0
    fi

    fail "This app appears asset-catalog backed and fileicon is unavailable" || return 1
  fi

  if [[ -n "$APP_ICON_TARGET" && -f "$APP_ICON_TARGET" ]]; then
    printf 'internal-icns\n'
    return 0
  fi

  fail "No valid icon application strategy is available for $APP_PATH" || return 1
}

apply_icon_with_strategy() {
  local strategy_name="$1"
  local icon_file="$2"
  local force_asset="${3:-false}"

  strategy_validate_name "$strategy_name" || return 1

  case "$strategy_name" in
    internal-icns)
      strategy_internal_icns_apply "$icon_file" "$force_asset"
      ;;
    fileicon)
      strategy_fileicon_apply "$icon_file"
      ;;
    *)
      fail "Strategy execution is not implemented for: $strategy_name" || return 1
      ;;
  esac
}
