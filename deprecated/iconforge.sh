#!/usr/bin/env bash
# iconforge.sh
# Version: 1.0.0
# Author: Meghan Johnson (@villagealchemist)
# License: MIT
# Homepage: https://github.com/villagealchemist/iconforge

set -euo pipefail

VERSION="1.0.0"

# === Load optional user config file ===
CONFIG_FILE="$HOME/.iconforgerc"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# === Defaults (can be overridden by flags or config file) ===
CUSTOM_OUTPUT="${CUSTOM_OUTPUT:-}"
KEEP_PNG="${KEEP_PNG:-false}"
RECURSIVE="${RECURSIVE:-false}"
SHOW_VERSION=false

# === Provide realpath fallback for macOS if needed ===
if ! command -v realpath >/dev/null 2>&1; then
  realpath() {
    [[ -d "$1" ]] && (cd "$1" && pwd) || echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  }
fi

# === Dependency check ===
for cmd in sips iconutil find; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Missing required tool: $cmd"
    echo "   Please run: xcode-select --install"
    exit 1
  fi
done

# === Supported extensions ===
SUPPORTED_EXT="png jpg jpeg webp tiff tif gif heic"

# === CLI help ===
print_help() {
  cat <<EOF
Usage: iconforge [options] <input_image(s)> [output_name]

Options:
  -o, --output PATH     Set output directory
  -k, --keep-png        Preserve intermediate PNG
  -r, --recursive       Recursively process files in a directory
  -h, --help            Show this help text
      --version         Show version and exit
EOF
}

# === Parse arguments ===
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) CUSTOM_OUTPUT="$2"; shift 2 ;;
    -k|--keep-png) KEEP_PNG=true; shift ;;
    -r|--recursive) RECURSIVE=true; shift ;;
    -h|--help) print_help; exit 0 ;;
    --version) SHOW_VERSION=true; shift ;;
    -*) echo "❌ Unknown flag: $1"; exit 1 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

# === Version output ===
if $SHOW_VERSION; then
  echo "iconforge v$VERSION"
  exit 0
fi

# === Interactive fallback ===
if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
  echo "🔧 Interactive mode"
  read -p "Input file(s) or directory: " resp
  POSITIONAL=($resp)
  read -p "Output directory [${CUSTOM_OUTPUT:-$(pwd)}]: " od
  [[ -n "$od" ]] && CUSTOM_OUTPUT="$od"
  read -p "Keep intermediate PNG? (y/N): " kp
  [[ "$kp" =~ ^[Yy] ]] && KEEP_PNG=true
  read -p "Recursive scan (for folders)? (y/N): " rc
  [[ "$rc" =~ ^[Yy] ]] && RECURSIVE=true
fi

# === Collect files ===
FILES=()
override_name=""
if [[ "$RECURSIVE" == true && -d "${POSITIONAL[0]}" ]]; then
  while IFS= read -r -d '' f; do FILES+=("$f"); done < <(
    find "${POSITIONAL[0]}" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
      -o -iname '*.webp' -o -iname '*.tiff' -o -iname '*.tif' -o -iname '*.gif' -o -iname '*.heic' \) -print0
  )
elif [[ ${#POSITIONAL[@]} -eq 2 && "$RECURSIVE" != true && -f "${POSITIONAL[0]}" && ! -f "${POSITIONAL[1]}" ]]; then
  override_name="${POSITIONAL[1]}"
  FILES=("${POSITIONAL[0]}")
else
  FILES=("${POSITIONAL[@]}")
fi

# === Fail on duplicate base names (Bash 3.2 safe) ===
base_names=()
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")
  base="${base%.*}"
  if [[ ${#base_names[@]} -gt 0 ]] && printf '%s\n' "${base_names[@]}" | grep -qx "$base"; then
    echo "❌ File name conflict: '$base' appears more than once."
    echo "   All input filenames must be unique after extension is stripped."
    exit 1
  fi
  base_names+=("$base")
done

# === Process a single file ===
process_file() {
  local input="$1"
  local ext="${input##*.}"
  local ext_lc=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

  if ! echo " $SUPPORTED_EXT " | grep -q " $ext_lc "; then
    echo "❌ Skipping unsupported: $(basename "$input")"
    return 1
  fi

  if [[ ! -f "$input" ]]; then
    echo "❌ Skipping missing file: $input"
    return 1
  fi

  local base="${override_name:-$(basename "$input")}"
  base="${base%.*}"
  [[ -z "$base" ]] && base="icon"
  local base_safe=$(echo "$base" | tr -cd '[:alnum:]_-')
  [[ -z "$base_safe" ]] && base_safe="icon"

  local abs_input=$(realpath "$input")
  local tmp_png="/tmp/iconforge_${base_safe}.png"
  local src_png

  # Convert to PNG if necessary
  if [[ "$ext_lc" != "png" ]]; then
    sips -s format png "$abs_input" --out "$tmp_png" >/dev/null 2>&1 || {
      echo "❌ Failed to convert: $(basename "$input")"
      return 1
    }
    src_png="$tmp_png"
  else
    src_png="$abs_input"
  fi

  # Define output structure
  local out_dir="${CUSTOM_OUTPUT:-$(pwd)}"
  local app_dir="$out_dir/$base_safe"
  local iconset_dir="$app_dir/$base_safe.iconset"
  local icns_path="$app_dir/$base_safe.icns"
  local final_png="$app_dir/$base_safe.png"

  mkdir -p "$iconset_dir" "$app_dir"
  [[ "$KEEP_PNG" == true ]] && cp "$src_png" "$final_png" 2>/dev/null

  # Generate all icon sizes
  sips -z 16 16   "$src_png" --out "$iconset_dir/icon_16x16.png" >/dev/null 2>&1
  sips -z 32 32   "$src_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null 2>&1
  sips -z 32 32   "$src_png" --out "$iconset_dir/icon_32x32.png" >/dev/null 2>&1
  sips -z 64 64   "$src_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null 2>&1
  sips -z 128 128 "$src_png" --out "$iconset_dir/icon_128x128.png" >/dev/null 2>&1
  sips -z 256 256 "$src_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null 2>&1
  sips -z 256 256 "$src_png" --out "$iconset_dir/icon_256x256.png" >/dev/null 2>&1
  sips -z 512 512 "$src_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null 2>&1
  cp "$src_png" "$iconset_dir/icon_512x512.png" 2>/dev/null
  cp "$src_png" "$iconset_dir/icon_512x512@2x.png" 2>/dev/null

  # Build the .icns bundle
  iconutil -c icns "$iconset_dir" -o "$icns_path" >/dev/null 2>&1 || {
    echo "❌ Failed to create .icns from: $base_safe"
    rm -rf "$iconset_dir"
    return 1
  }

  [[ ! -f "$icns_path" ]] && {
    echo "❌ iconutil did not produce output for: $base_safe"
    return 1
  }

  rm -rf "$iconset_dir"
  [[ -f "$tmp_png" ]] && rm "$tmp_png"

  echo "✅ Created: $base_safe.icns"
  [[ "$KEEP_PNG" == true ]] && echo "   • PNG preserved"
  return 0
}

# === Main loop ===
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "⚠️ No files to process."
  exit 1
fi

errors=0
for file in "${FILES[@]}"; do
  if ! process_file "$file"; then
    ((errors++))
  fi
done

[[ "$errors" -gt 0 ]] && exit 1 || exit 0
