#!/usr/bin/env bash

forge_help() {
  cat <<EOF
Usage:
  iconforge forge <input_image(s)> [output_name] [options]
  iconforge <input_image(s)> [output_name] [options]

Options:
  -o, --output PATH     Set output directory
  -k, --keep-png        Preserve the converted PNG alongside the .icns
  -r, --recursive       Recursively process supported images in a directory
      --no-warnings     Skip the small-image confirmation prompt
      --dry-run         Print planned work without writing files
  -h, --help            Show forge help

Supported input formats:
  png, jpg, jpeg, webp, tiff, tif, gif
EOF
}

forge_interactive_prompt() {
  local resp
  local od
  local kp
  local rc
  local sw

  stderr "Interactive forge mode"
  printf 'Input file(s) or directory: ' >&2
  read -r resp
  [[ -n "$resp" ]] || { fail "No input provided" || return 1; }
  # shellcheck disable=SC2206
  POSITIONAL=($resp)

  printf 'Output directory [%s]: ' "${CUSTOM_OUTPUT:-$(pwd)}" >&2
  read -r od
  [[ -n "$od" ]] && CUSTOM_OUTPUT="$od"

  printf 'Keep converted PNG? (y/N): ' >&2
  read -r kp
  [[ "$kp" =~ ^[Yy] ]] && KEEP_PNG=true

  printf 'Recursive scan for directories? (y/N): ' >&2
  read -r rc
  [[ "$rc" =~ ^[Yy] ]] && RECURSIVE=true

  printf 'Suppress quality warnings? (y/N): ' >&2
  read -r sw
  [[ "$sw" =~ ^[Yy] ]] && SUPPRESS_WARNINGS=true
}

generate_icon_size() {
  local width="$1"
  local height="$2"
  local icon_name="$3"
  local src_png="$4"
  local target_dir="$5"
  local error_counter_ref="$6"
  local output_path="$target_dir/$icon_name"

  if [[ "$width" == "copy" ]]; then
    run_cmd cp "$src_png" "$output_path" || {
      eval "$error_counter_ref=\$((\$$error_counter_ref + 1))"
      warn "Failed to create $icon_name"
      return 1
    }
  else
    if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
      run_cmd "$ICONFORGE_PROCESSOR" resize "$src_png" "$width" "$height" "$output_path"
    else
      "$ICONFORGE_PROCESSOR" resize "$src_png" "$width" "$height" "$output_path" || {
        eval "$error_counter_ref=\$((\$$error_counter_ref + 1))"
        warn "Failed to create $icon_name"
        return 1
      }
    fi
  fi

  return 0
}

collect_forge_inputs() {
  FILES=()
  override_name=""

  if [[ "${#POSITIONAL[@]}" -eq 0 ]]; then
    forge_interactive_prompt || return 1
  fi

  if [[ "$RECURSIVE" == true && -d "${POSITIONAL[0]:-}" ]]; then
    while IFS= read -r -d '' file; do
      FILES+=("$file")
    done < <(find "${POSITIONAL[0]}" -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
         -o -iname '*.tiff' -o -iname '*.tif' -o -iname '*.gif' \) -print0)
  elif [[ ${#POSITIONAL[@]} -eq 2 && -f "${POSITIONAL[0]}" && ! -f "${POSITIONAL[1]}" ]]; then
    override_name="${POSITIONAL[1]}"
    FILES=("${POSITIONAL[0]}")
  else
    FILES=("${POSITIONAL[@]}")
  fi

  if [[ "${#FILES[@]}" -eq 0 ]]; then
    fail "No files to process" || return 1
  fi

  local base_names=()
  local file
  local base
  for file in "${FILES[@]}"; do
    [[ -f "$file" ]] || continue
    base="$(basename "$file")"
    base="${base%.*}"
    if [[ "${base_names[0]+set}" == set ]] && printf '%s\n' "${base_names[@]}" | grep -qx "$base" 2>/dev/null; then
      fail "File name conflict: '$base' appears more than once after stripping extensions" || return 1
    fi
    base_names+=("$base")
  done
}

process_forge_file() {
  local input="$1"
  local file_index="$2"
  local total_files="$3"
  local ext="${input##*.}"
  local ext_lc
  local base
  local base_safe
  local abs_input
  local tmp_png=""
  local src_png
  local dimensions=""
  local width=0
  local height=0
  local out_dir
  local iconset_dir
  local icns_path
  local final_png
  local size_errors=0
  local response
  local icon_specs=(
    "16 16 icon_16x16.png"
    "32 32 icon_16x16@2x.png"
    "32 32 icon_32x32.png"
    "64 64 icon_32x32@2x.png"
    "128 128 icon_128x128.png"
    "256 256 icon_128x128@2x.png"
    "256 256 icon_256x256.png"
    "512 512 icon_256x256@2x.png"
    "512 512 icon_512x512.png"
    "1024 1024 icon_512x512@2x.png"
  )
  local spec
  local spec_w
  local spec_h
  local spec_name

  ext_lc="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  case "$ext_lc" in
    png|jpg|jpeg|webp|tiff|tif|gif) ;;
    *)
      warn "Skipping unsupported file: $input"
      return 1
      ;;
  esac

  [[ -f "$input" ]] || { warn "Skipping missing file: $input"; return 1; }

  base="${override_name:-$(basename "$input")}"
  base="${base%.*}"
  [[ -n "$base" ]] || base="icon"
  base_safe="$(printf '%s' "$base" | tr -cd '[:alnum:]_-')"
  [[ -n "$base_safe" ]] || base_safe="icon"

  if [[ "$total_files" -gt 1 ]]; then
    note "Forging $base_safe ($file_index/$total_files)"
  else
    note "Forging $base_safe"
  fi

  abs_input="$(realpath "$input")"
  if [[ "$ext_lc" != "png" ]]; then
    tmp_png="${ICONFORGE_TMP_DIR:-/tmp}/iconforge_${base_safe}.png"
    if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
      run_cmd "$ICONFORGE_PROCESSOR" convert "$abs_input" "$tmp_png"
    else
      "$ICONFORGE_PROCESSOR" convert "$abs_input" "$tmp_png" || {
        warn "Failed to convert $input to PNG"
        return 1
      }
    fi
    src_png="$tmp_png"
  else
    src_png="$abs_input"
  fi

  if [[ "$ICONFORGE_DRY_RUN" != true ]]; then
    dimensions=$("$ICONFORGE_PROCESSOR" info "$src_png" 2>/dev/null || true)
  fi

  if [[ "$dimensions" =~ ^[0-9]+x[0-9]+$ ]]; then
    width="${dimensions%x*}"
    height="${dimensions#*x}"
  fi

  if [[ "$width" -gt 0 && "$height" -gt 0 && ( "$width" -lt 512 || "$height" -lt 512 ) ]]; then
    warn "Source image is ${width}x${height}. Apple icons look best at 512x512 or larger."
    if [[ "$SUPPRESS_WARNINGS" != true ]]; then
      printf 'Proceed anyway? (y/N): ' >&2
      read -r response
      [[ "$response" =~ ^[Yy] ]] || return 1
    fi
  fi

  out_dir="${CUSTOM_OUTPUT:-$(pwd)}"
  iconset_dir="$out_dir/$base_safe.iconset"
  icns_path="$out_dir/$base_safe.icns"
  final_png="$out_dir/$base_safe.png"

  run_cmd mkdir -p "$out_dir" "$iconset_dir" || return 1
  [[ "$KEEP_PNG" == true ]] && run_cmd cp "$src_png" "$final_png"

  for spec in "${icon_specs[@]}"; do
    # shellcheck disable=SC2086
    read -r spec_w spec_h spec_name <<< "$spec"
    generate_icon_size "$spec_w" "$spec_h" "$spec_name" "$src_png" "$iconset_dir" size_errors
  done

  [[ "$size_errors" -gt 0 ]] && warn "$size_errors icon sizes failed to generate for $base_safe"

  if [[ "$ICONFORGE_DRY_RUN" == true ]]; then
    run_cmd "$ICONUTIL_BIN" -c icns "$iconset_dir" -o "$icns_path"
  else
    "$ICONUTIL_BIN" -c icns "$iconset_dir" -o "$icns_path" >/dev/null 2>&1 || {
      warn "iconutil failed for $base_safe"
      rm -rf "$iconset_dir"
      [[ -n "$tmp_png" && -f "$tmp_png" ]] && rm -f "$tmp_png"
      return 1
    }
  fi

  if [[ "$ICONFORGE_DRY_RUN" != true ]]; then
    rm -rf "$iconset_dir"
    [[ -n "$tmp_png" && -f "$tmp_png" ]] && rm -f "$tmp_png"
  fi

  printf 'Created: %s\n' "$icns_path"
  [[ "$KEEP_PNG" == true ]] && printf 'PNG kept: %s\n' "$final_png"
  return 0
}

cmd_forge() {
  POSITIONAL=()
  KEEP_PNG="${KEEP_PNG:-false}"
  RECURSIVE="${RECURSIVE:-false}"
  SUPPRESS_WARNINGS="${SUPPRESS_WARNINGS:-false}"
  ICONFORGE_DRY_RUN=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o|--output)
        CUSTOM_OUTPUT="$2"
        shift 2
        ;;
      -k|--keep-png)
        KEEP_PNG=true
        shift
        ;;
      -r|--recursive)
        RECURSIVE=true
        shift
        ;;
      --no-warnings)
        SUPPRESS_WARNINGS=true
        shift
        ;;
      --dry-run)
        ICONFORGE_DRY_RUN=true
        shift
        ;;
      -h|--help)
        forge_help
        return 0
        ;;
      --version)
        printf 'iconforge v%s\n' "$ICONFORGE_VERSION"
        return 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          POSITIONAL+=("$1")
          shift
        done
        ;;
      -*)
        fail "Unknown forge flag: $1" || return 1
        ;;
      *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
  done

  require_processor || return 1
  require_tool "$ICONUTIL_BIN" "Missing required tool: iconutil"
  collect_forge_inputs || return 1

  local errors=0
  local current=1
  local file
  for file in "${FILES[@]}"; do
    process_forge_file "$file" "$current" "${#FILES[@]}" || errors=$((errors + 1))
    current=$((current + 1))
  done

  [[ "$errors" -eq 0 ]]
}
