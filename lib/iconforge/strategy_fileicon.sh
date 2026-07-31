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

  if [[ "$ICONFORGE_DRY_RUN" != true ]]; then
    run_quiet_cmd "$FILEICON_BIN" test "$APP_PATH" || fail "fileicon did not persist a custom icon for $APP_PATH" || return 1
  fi
}

strategy_fileicon_restore() {
  require_tool "$FILEICON_BIN" "Missing required tool: fileicon"
  require_app_bundle_path "$APP_PATH" || return 1

  run_cmd "$FILEICON_BIN" rm "$APP_PATH"
}
