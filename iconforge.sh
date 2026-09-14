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
# shellcheck source=lib/iconforge/config.sh
source "$SCRIPT_DIR/lib/iconforge/config.sh"
# shellcheck source=lib/iconforge/forge.sh
source "$SCRIPT_DIR/lib/iconforge/forge.sh"
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
  config     Set, get, or unset the default icon directory
  inspect    Explain how an application bundle provides its icon
  apply      Apply one icon directly or apply a directory of icons in bulk
  restore    Restore an internal backup and/or remove a Finder custom icon
  nuke       Refresh current-user macOS icon caches
  help       Show this overview or help for one command

Command help:
  iconforge forge --help
  iconforge config --help
  iconforge inspect --help
  iconforge apply --help
  iconforge restore --help
  iconforge nuke --help

Image-first shorthand:
  iconforge logo.png BrandMark -o ./icons
  Existing supported image paths route to \`iconforge forge\`.

Global options:
  -h, --help       Show this overview
  -v, --version    Show the Icon Forge version

Quick start:
  iconforge config set default-directory "\$HOME/app-icons"
  iconforge forge ./messages.png google-messages
  iconforge inspect "/Applications/Google Messages.app"
  iconforge apply "/Applications/Google Messages.app" -i "\$HOME/app-icons/google-messages.icns"
  iconforge apply -a -d -v

Full reference:
  https://github.com/villagealchemist/iconforge/blob/main/docs/USAGE.md
EOF
}

is_supported_forge_path() {
  local input="${1:-}"
  local extension=""

  [[ -f "$input" && ! -L "$input" ]] || return 1
  extension="${input##*.}"
  extension="$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"
  case "$extension" in
    png|jpg|jpeg|webp|tiff|tif|gif) return 0 ;;
  esac
  return 1
}

cmd_help() {
  local topic=""
  local topic_seen=false
  local options_done=false

  while [[ $# -gt 0 ]]; do
    if [[ "$options_done" != true ]]; then
      case "$1" in
        --)
          options_done=true
          shift
          continue
          ;;
        -h|--help)
          [[ $# -eq 1 && "$topic_seen" != true ]] || { usage_fail "Help cannot combine a topic with -h/--help"; return 2; }
          root_help
          return 0
          ;;
        -*)
          usage_fail "Unknown help flag: $1" || return 2
          ;;
      esac
    fi

    [[ "$topic_seen" != true ]] || { usage_fail "Unexpected help argument: $1"; return 2; }
    [[ -n "$1" ]] || { usage_fail "Help topic must not be empty"; return 2; }
    topic="$1"
    topic_seen=true
    shift
  done

  if [[ "$topic_seen" != true ]]; then
    root_help
    return 0
  fi

  case "$topic" in
    forge|config|inspect|apply|restore|nuke)
      dispatch_subcommand "$topic" --help
      ;;
    help)
      root_help
      ;;
    *)
      usage_fail "Unknown help topic: $topic" || return 2
      ;;
  esac
}

dispatch_subcommand() {
  local command="$1"
  shift || true

  case "$command" in
    help)
      cmd_help "$@"
      ;;
    forge)
      cmd_forge "$@"
      ;;
    config)
      cmd_config "$@"
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
    nuke)
      ICONFORGE_DRY_RUN=false
      cmd_nuke "$@"
      ;;
    *)
      usage_fail "Unknown command: $command" || return 2
      ;;
  esac
}

main() {
  if [[ $# -eq 0 ]]; then
    root_help
    return 0
  fi

  case "$1" in
    -h|--help)
      [[ $# -eq 1 ]] || { usage_fail "$1 does not accept arguments"; return 2; }
      root_help
      ;;
    -v|--version)
      [[ $# -eq 1 ]] || { usage_fail "$1 does not accept arguments"; return 2; }
      printf 'iconforge v%s\n' "$ICONFORGE_VERSION"
      ;;
    --)
      shift
      [[ $# -gt 0 ]] || { usage_fail "-- requires a supported input image path"; return 2; }
      is_supported_forge_path "$@" || { usage_fail "Not a supported forge input: $1"; return 2; }
      cmd_forge -- "$@"
      ;;
    -*)
      usage_fail "Unknown global flag: $1" || return 2
      ;;
    *)
      case "$1" in
        forge|config|inspect|apply|restore|nuke|help)
          dispatch_subcommand "$@"
          ;;
        *)
          if is_supported_forge_path "$@"; then
            cmd_forge "$@"
          else
            usage_fail "Unknown command or unsupported input image: $1" || return 2
          fi
          ;;
      esac
      ;;
  esac
}

main "$@"
