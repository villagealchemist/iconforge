#!/bin/zsh

# Uninstall script for iconforge
# Removes the global command symlink and makes cleanup easy.

TARGET_PATH="/usr/local/bin/iconforge"
SCRIPT_PATH="$(readlink "$TARGET_PATH")"

# Remove global symlink
if [[ -L "$TARGET_PATH" ]]; then
  echo "🗑 Removing global command: $TARGET_PATH"
  sudo rm "$TARGET_PATH"
else
  echo "⚠️ No global command found at $TARGET_PATH"
fi

# Optionally, prompt to remove local files
read -p "🗑️  Also remove local script files at $SCRIPT_PATH? [y/N] " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  if [[ -f "$SCRIPT_PATH" ]]; then
    echo "🗑 Removing local script: $SCRIPT_PATH"
    rm -f "$SCRIPT_PATH"
  else
    echo "⚠️ Local script not found: $SCRIPT_PATH"
  fi
fi

echo "✅ Uninstall complete."
