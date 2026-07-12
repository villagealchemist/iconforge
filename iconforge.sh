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

source "$SCRIPT_DIR/lib/iconforge/common.sh"
source "$SCRIPT_DIR/lib/iconforge/forge.sh"
source "$SCRIPT_DIR/lib/iconforge/config.sh"
source "$SCRIPT_DIR/lib/iconforge/library.sh"
source "$SCRIPT_DIR/lib/iconforge/discovery.sh"
source "$SCRIPT_DIR/lib/iconforge/match.sh"
source "$SCRIPT_DIR/lib/iconforge/strategy_internal_icns.sh"
source "$SCRIPT_DIR/lib/iconforge/strategy_fileicon.sh"
source "$SCRIPT_DIR/lib/iconforge/strategy.sh"
source "$SCRIPT_DIR/lib/iconforge/apps.sh"

root_help() {
  cat <<EOF
iconforge v$ICONFORGE_VERSION

Usage:
  iconforge forge <input> [output_name] [options]
  iconforge inspect <app>
  iconforge apply <app> --icon <file.icns> [--nuke] [--force-asset]
  iconforge restore <app> [--nuke]
  iconforge nuke [app]

Legacy shorthand:
  iconforge <input> [output_name] [options]
  This still routes to \`iconforge forge\`.

Global flags:
  -h, --help            Show this help text
      --version         Show version and exit
EOF
}

dispatch_subcommand() {
  local command="$1"
  shift || true

  case "$command" in
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
    nuke)
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
    --version)
      printf 'iconforge v%s\n' "$ICONFORGE_VERSION"
      ;;
    *)
      dispatch_subcommand "$@"
      ;;
  esac
}

main "$@"
