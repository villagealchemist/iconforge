#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_TARGET="$PREFIX/bin/iconforge"
RUNTIME_DIR="$PREFIX/lib/iconforge"
removed=0

[[ "$PREFIX" != "/" ]] || { echo "Error: PREFIX must not be /"; exit 1; }

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
