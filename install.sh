#!/usr/bin/env bash
set -e

# iconforge installer — checks dependencies and creates symlink

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICONFORGE_SH="$SCRIPT_DIR/iconforge.sh"
TARGET_PATH="/usr/local/bin/iconforge"

# Ensure iconforge.sh exists
if [[ ! -f "$ICONFORGE_SH" ]]; then
  echo "❌ iconforge.sh not found in $SCRIPT_DIR"
  exit 1
fi

# Gather missing dependencies
missing_auto=()
missing_manual=()

# Check for realpath (coreutils)
if ! command -v realpath >/dev/null 2>&1; then
  missing_auto+=("coreutils")
fi

# Check built-in tools
for cmd in sips iconutil find; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing_manual+=("$cmd")
  fi
done

# Abort if any manual deps missing
if [[ ${#missing_manual[@]} -gt 0 ]]; then
  echo "❌ Missing required macOS tools: ${missing_manual[*]}"
  echo "   Please install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

# Prompt and install auto deps if missing
if [[ ${#missing_auto[@]} -gt 0 ]]; then
  echo "⚠️  Missing dependencies: ${missing_auto[*]}"
  read -p "Install missing dependencies via Homebrew now? [Y/n]: " resp
  case "$resp" in
    [yY]|"")
      # Ensure Homebrew is installed
      if ! command -v brew >/dev/null 2>&1; then
        echo "🔧 Homebrew not found. Installing Homebrew..."
        /usr/bin/env bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo "✅ Homebrew installed."
      fi
      # Install each missing auto dependency
      for dep in "${missing_auto[@]}"; do
        case "$dep" in
          coreutils)
            echo "🔧 Installing coreutils..."
            brew install coreutils
            ;;
        esac
      done
      ;;
    *)
      echo "❌ Cannot proceed without installing dependencies. Aborting."
      exit 1
      ;;
  esac
fi

# Make iconforge.sh executable
target="$ICONFORGE_SH"
chmod +x "$target"

# Create or update symlink
ln -sf "$target" "$TARGET_PATH"

echo "🔗 Linked $target -> $TARGET_PATH"
echo "✅ Installation complete. Run 'iconforge --help' to get started."
