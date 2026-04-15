#!/usr/bin/env bash

set -euo pipefail

BIN_TARGET="/usr/local/bin/iconforge"
RUNTIME_DIR="/usr/local/lib/iconforge"
removed=0

if [[ -f "$BIN_TARGET" ]]; then
  echo "Removing $BIN_TARGET"
  rm -f "$BIN_TARGET"
  removed=$((removed + 1))
fi

if [[ -d "$RUNTIME_DIR" ]]; then
  echo "Removing $RUNTIME_DIR"
  rm -rf "$RUNTIME_DIR"
  removed=$((removed + 1))
fi

if [[ "$removed" -eq 0 ]]; then
  echo "No iconforge installation found"
  exit 1
fi

echo "Uninstall complete"
