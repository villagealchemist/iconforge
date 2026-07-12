#!/usr/bin/env bash

strategy_fileicon_available() {
  command -v "$FILEICON_BIN" >/dev/null 2>&1
}

strategy_fileicon_apply() {
  local icon_file="$1"

  require_tool "$FILEICON_BIN" "Missing required tool: fileicon"
  require_app_bundle_path "$APP_PATH" || return 1
  require_existing_file_path "Icon file" "$icon_file" || return 1
  [[ "$icon_file" == *.icns ]] || fail "Icon file must be a .icns file: $icon_file" || return 1

  run_cmd "$FILEICON_BIN" set "$APP_PATH" "$icon_file"
}
