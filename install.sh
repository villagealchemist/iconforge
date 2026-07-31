#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
RUNTIME_DIR="$PREFIX/lib/iconforge"
BIN_DIR="$PREFIX/bin"
BIN_TARGET="$BIN_DIR/iconforge"
PROCESSOR_SOURCE="$SCRIPT_DIR/iconforge-processor/iconforge-processor"
MAIN_SOURCE="$SCRIPT_DIR/iconforge.sh"

[[ "$PREFIX" != "/" ]] || { echo "Error: PREFIX must not be /"; exit 1; }
[[ -x "$MAIN_SOURCE" ]] || { echo "Error: iconforge entrypoint not found at $MAIN_SOURCE"; exit 1; }
[[ -x "$PROCESSOR_SOURCE" ]] || { echo "Error: iconforge-processor not found at $PROCESSOR_SOURCE. Run 'make build' first."; exit 1; }

if ! command -v iconutil >/dev/null 2>&1; then
  echo "Error: Missing required macOS tool: iconutil"
  echo "Install Xcode Command Line Tools with: xcode-select --install"
  exit 1
fi

mkdir -p "$BIN_DIR"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR/lib" "$RUNTIME_DIR/iconforge-processor"
cp "$SCRIPT_DIR/VERSION" "$RUNTIME_DIR/VERSION"
cp "$MAIN_SOURCE" "$RUNTIME_DIR/iconforge"
cp "$PROCESSOR_SOURCE" "$RUNTIME_DIR/iconforge-processor/iconforge-processor"
cp -R "$SCRIPT_DIR/lib/iconforge" "$RUNTIME_DIR/lib/"

cat > "$BIN_TARGET" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../lib/iconforge/iconforge" "$@"
EOF
chmod +x "$RUNTIME_DIR/iconforge" "$RUNTIME_DIR/iconforge-processor/iconforge-processor" "$BIN_TARGET"

echo "Installed runtime: $RUNTIME_DIR"
echo "Installed launcher: $BIN_TARGET"
"$BIN_TARGET" --version
