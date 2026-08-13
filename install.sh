#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
RUNTIME_DIR="$PREFIX/lib/iconforge"
BIN_DIR="$PREFIX/bin"
BIN_TARGET="$BIN_DIR/iconforge"
PROCESSOR_SOURCE="$SCRIPT_DIR/iconforge-processor/iconforge-processor"
NATIVE_ICON_SOURCE="$SCRIPT_DIR/iconforge-native-icon/iconforge-native-icon"
MAIN_SOURCE="$SCRIPT_DIR/iconforge.sh"

[[ "$PREFIX" != "/" ]] || { echo "Error: PREFIX must not be /"; exit 1; }
[[ -x "$MAIN_SOURCE" ]] || { echo "Error: iconforge entrypoint not found at $MAIN_SOURCE"; exit 1; }
[[ -x "$PROCESSOR_SOURCE" ]] || { echo "Error: iconforge-processor not found at $PROCESSOR_SOURCE. Run 'make build' first."; exit 1; }
[[ -x "$NATIVE_ICON_SOURCE" ]] || { echo "Error: iconforge-native-icon not found at $NATIVE_ICON_SOURCE. Run 'make build' first."; exit 1; }

if [[ -e "$PREFIX" && ! -d "$PREFIX" ]]; then
  echo "Error: install prefix exists but is not a directory: $PREFIX" >&2
  exit 1
fi

writable_parent="$PREFIX"
while [[ ! -e "$writable_parent" && "$writable_parent" != "/" ]]; do
  writable_parent="$(dirname "$writable_parent")"
done

if [[ ! -w "$writable_parent" ]]; then
  cat >&2 <<EOF
Error: install prefix is not writable: $PREFIX

Install for the current user:
  PREFIX="\$HOME/.local" make install

Or install system-wide after building as your normal user:
  make build
  sudo env PREFIX=/usr/local ./install.sh
EOF
  exit 1
fi

mkdir -p "$BIN_DIR"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR/lib" "$RUNTIME_DIR/iconforge-processor" "$RUNTIME_DIR/iconforge-native-icon"
cp "$SCRIPT_DIR/VERSION" "$RUNTIME_DIR/VERSION"
cp "$MAIN_SOURCE" "$RUNTIME_DIR/iconforge"
cp "$PROCESSOR_SOURCE" "$RUNTIME_DIR/iconforge-processor/iconforge-processor"
cp "$NATIVE_ICON_SOURCE" "$RUNTIME_DIR/iconforge-native-icon/iconforge-native-icon"
cp -R "$SCRIPT_DIR/lib/iconforge" "$RUNTIME_DIR/lib/"

cat > "$BIN_TARGET" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../lib/iconforge/iconforge" "$@"
EOF
chmod +x "$RUNTIME_DIR/iconforge" "$RUNTIME_DIR/iconforge-processor/iconforge-processor" "$RUNTIME_DIR/iconforge-native-icon/iconforge-native-icon" "$BIN_TARGET"

echo "Installed runtime: $RUNTIME_DIR"
echo "Installed launcher: $BIN_TARGET"
"$BIN_TARGET" --version
