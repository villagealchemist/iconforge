#!/usr/bin/env bash

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
ICONFORGE_ROOT="$SCRIPT_DIR"

# shellcheck source=lib/iconforge/common.sh
source "$SCRIPT_DIR/lib/iconforge/common.sh"
# shellcheck source=lib/iconforge/forge.sh
source "$SCRIPT_DIR/lib/iconforge/forge.sh"
# shellcheck source=lib/iconforge/config.sh
source "$SCRIPT_DIR/lib/iconforge/config.sh"
# shellcheck source=lib/iconforge/library.sh
source "$SCRIPT_DIR/lib/iconforge/library.sh"
# shellcheck source=lib/iconforge/discovery.sh
source "$SCRIPT_DIR/lib/iconforge/discovery.sh"
# shellcheck source=lib/iconforge/match.sh
source "$SCRIPT_DIR/lib/iconforge/match.sh"
# shellcheck source=lib/iconforge/strategy-internal-icns.sh
source "$SCRIPT_DIR/lib/iconforge/strategy-internal-icns.sh"
# shellcheck source=lib/iconforge/strategy-native-icon.sh
source "$SCRIPT_DIR/lib/iconforge/strategy-native-icon.sh"
# shellcheck source=lib/iconforge/strategy.sh
source "$SCRIPT_DIR/lib/iconforge/strategy.sh"
# shellcheck source=lib/iconforge/apps.sh
source "$SCRIPT_DIR/lib/iconforge/apps.sh"

root_help() {
  cat <<EOF
iconforge v$ICONFORGE_VERSION

Usage:
  iconforge <command> [arguments] [options]
  iconforge <input-image> [output-name] [forge-options]

Commands:
  forge      Convert an image, image list, or directory into macOS .icns files
  inspect    Explain how an application bundle provides its icon
  apply      Apply one icon, one managed library entry, or the whole library
  restore    Restore an internal backup and/or remove a Finder custom icon
  refresh    Refresh macOS icon caches (preferred name; alias: nuke)
  nuke       Alias for refresh
  help       Show this overview or help for one command

Command help:
  iconforge forge --help
  iconforge inspect --help
  iconforge apply --help
  iconforge restore --help
  iconforge refresh --help

Legacy shorthand:
  iconforge logo.png BrandMark -o ./icons
  Image-first commands still route to \`iconforge forge\`.

Global options:
  -h, --help       Show this overview
  -V, --version    Show the Icon Forge version

Quick start:
  iconforge forge ./messages.png google-messages -o ./icons
  iconforge inspect "/Applications/Google Messages.app"
  iconforge apply "/Applications/Google Messages.app" -i ./icons/google-messages.icns -c

Full reference:
  https://github.com/villagealchemist/iconforge/blob/main/docs/USAGE.md
EOF
}

dispatch_subcommand() {
  local command="$1"
  shift || true

  case "$command" in
    help)
      if [[ $# -eq 0 ]]; then
        root_help
      else
        case "$1" in
          forge|inspect|apply|restore|refresh|nuke)
            dispatch_subcommand "$1" --help
            ;;
          *)
            fail "Unknown help topic: $1" || return 1
            ;;
        esac
      fi
      ;;
    forge)
      cmd_forge "$@"
      ;;
    inspect)
      cmd_inspect "$@"
      ;;
    apply)
      ICONFORGE_DRY_RUN=false
      cmd_apply "$@"
      ;;
    restore)
      ICONFORGE_DRY_RUN=false
      cmd_restore "$@"
      ;;
    refresh|nuke)
      ICONFORGE_DRY_RUN=false
      cmd_nuke "$@"
      ;;
    *)
      cmd_forge "$command" "$@"
      ;;
  esac
}

main() {
  if [[ $# -eq 0 ]]; then
    if [[ -t 0 && -t 1 ]]; then
      cmd_forge
    else
      root_help
    fi
    return
  fi

  case "$1" in
    -h|--help)
      root_help
      ;;
    -V|--version)
      printf 'iconforge v%s\n' "$ICONFORGE_VERSION"
      ;;
    *)
      dispatch_subcommand "$@"
      ;;
  esac
}

main "$@"
