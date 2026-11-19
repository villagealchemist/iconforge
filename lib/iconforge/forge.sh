#!/usr/bin/env bash

forge_help() {
  cat <<'EOF'
Forge macOS .icns files from source images.

Usage:
  iconforge forge <input-image> [output-name] [options]
  iconforge forge <input-image>... [options]
  iconforge forge <directory> -r [options]
  iconforge <input-image> [output-name] [options]

Arguments:
  <input-image>     PNG, JPEG, WebP, TIFF, or GIF source image
  [output-name]     Optional basename for one output; omit the extension
  <directory>       Directory to scan with -r/--recursive

Options:
  -o, --output <dir>  Write outputs to <dir>; overrides the configured default
  -k, --keep-png      Keep the normalized PNG beside each generated .icns
  -r, --recursive     Recursively forge one directory while preserving its tree
  -f, --force         Replace pre-existing regular output files without prompting
  -d, --dry-run       Validate and print the complete plan without writing
  -h, --help          Show this help

Supported input formats:
  png, jpg, jpeg, webp, tiff, tif, gif

Examples:
  iconforge config set default-directory "$HOME/app-icons"
  iconforge forge ./messages.png google-messages -o ./icons
  iconforge forge ./photos --recursive --output ./icons
  iconforge ./logo.png BrandMark -o ./dist --keep-png
EOF
}

FORGE_INPUTS=()
FORGE_STEMS=()
FORGE_ICNS_TARGETS=()
FORGE_PNG_TARGETS=()
FORGE_PNG_NOOPS=()
FORGE_STAGE_ICNS=()
FORGE_STAGE_PNG=()
FORGE_EXISTING_TARGETS=()
FORGE_INTERRUPT_STATUS=0
FORGE_RECOVERY_STAGE=""

forge_reset_manifest() {
  FORGE_INPUTS=()
  FORGE_STEMS=()
  FORGE_ICNS_TARGETS=()
  FORGE_PNG_TARGETS=()
  FORGE_PNG_NOOPS=()
  FORGE_STAGE_ICNS=()
  FORGE_STAGE_PNG=()
  FORGE_EXISTING_TARGETS=()
}

forge_supported_extension() {
  local extension="${1##*.}"
  extension="$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"
  case "$extension" in
    png|jpg|jpeg|webp|tiff|tif|gif) return 0 ;;
    *) return 1 ;;
  esac
}

forge_is_png() {
  local extension="${1##*.}"
  extension="$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"
  [[ "$extension" == "png" ]]
}

forge_lexical_absolute_path() {
  local raw_path="$1"
  local absolute_path
  local component
  local -a source_parts=()
  local -a normalized_parts=()

  if [[ "$raw_path" == /* ]]; then
    absolute_path="$raw_path"
  else
    absolute_path="$PWD/$raw_path"
  fi

  IFS='/' read -r -a source_parts <<< "$absolute_path"
  for component in "${source_parts[@]+"${source_parts[@]}"}"; do
    case "$component" in
      ''|.) ;;
      ..)
        if [[ "${#normalized_parts[@]}" -gt 0 ]]; then
          unset 'normalized_parts[${#normalized_parts[@]}-1]'
        fi
        ;;
      *) normalized_parts+=("$component") ;;
    esac
  done

  if [[ "${#normalized_parts[@]}" -eq 0 ]]; then
    printf '/\n'
  else
    printf '/%s\n' "$(join_by '/' "${normalized_parts[@]}")"
  fi
}

forge_canonical_destination() {
  local path
  local existing_prefix
  local remainder=""
  local leaf

  path="$(forge_lexical_absolute_path "$1")"
  existing_prefix="$path"
  while [[ ! -e "$existing_prefix" && ! -L "$existing_prefix" ]]; do
    leaf="$(basename "$existing_prefix")"
    if [[ -n "$remainder" ]]; then
      remainder="$leaf/$remainder"
    else
      remainder="$leaf"
    fi
    [[ "$existing_prefix" != "/" ]] || break
    existing_prefix="$(dirname "$existing_prefix")"
  done

  if [[ -e "$existing_prefix" || -L "$existing_prefix" ]]; then
    existing_prefix="$(realpath -- "$existing_prefix")" || return 1
  fi

  if [[ -n "$remainder" ]]; then
    printf '%s/%s\n' "${existing_prefix%/}" "$remainder"
  else
    printf '%s\n' "$existing_prefix"
  fi
}

forge_case_key() {
  require_native_icon_helper || return 1
  "$ICONFORGE_NATIVE_ICON" path-key "$1" || {
    fail "Could not normalize an output path for collision analysis: $1" || return 1
  }
}

forge_array_contains() {
  local needle="$1"
  shift || true
  local value
  for value in "$@"; do
    [[ "$value" == "$needle" ]] && return 0
  done
  return 1
}

forge_collect_recursive_inputs() {
  local root="$1"
  local output_root="$2"
  local output_prune=""
  local candidate
  local canonical_candidate
  local scan_file
  local scan_status=0

  if [[ "$output_root" == "$root"/* ]]; then
    output_prune="$output_root"
  fi
  scan_file="$(mktemp "${ICONFORGE_REPORT_DIRECTORY:-$(iconforge_temp_root)}/iconforge-inputs.XXXXXX")" || {
    fail "Could not create an input scan manifest. Check available disk space and access to the temporary directory." || return 1
  }

  if [[ -n "$output_prune" ]]; then
    find "$root" \
      \( -mindepth 1 -type d -name '.*' -o -type d -iname '*.iconset' -o -path "$output_prune" \) -prune -o \
      -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
        -o -iname '*.tiff' -o -iname '*.tif' -o -iname '*.gif' \) ! -name '.*' -print0 >"$scan_file" || scan_status=1
  else
    find "$root" \
      \( -mindepth 1 -type d -name '.*' -o -type d -iname '*.iconset' \) -prune -o \
      -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
        -o -iname '*.tiff' -o -iname '*.tif' -o -iname '*.gif' \) ! -name '.*' -print0 >"$scan_file" || scan_status=1
  fi
  if [[ "$scan_status" -ne 0 ]]; then
    fail "Could not scan every source directory under $root. Resolve the traversal errors above, or select the readable images explicitly. No outputs will be written." || true
  fi
  if ! sort -z "$scan_file" -o "$scan_file"; then
    rm -f "$scan_file"
    fail "Could not sort the input manifest. Check temporary disk space and retry." || return 1
  fi
  while IFS= read -r -d '' candidate; do
    if canonical_candidate="$(realpath -- "$candidate")"; then
      FORGE_INPUTS+=("$canonical_candidate")
    else
      fail "Could not resolve source image: $candidate. Check that it still exists and is readable." || true
      scan_status=1
    fi
  done <"$scan_file"
  rm -f "$scan_file"

  if [[ "${#FORGE_INPUTS[@]}" -eq 0 && "$scan_status" -eq 0 ]]; then
    fail "No supported images found under $root. Supply PNG, JPEG, WebP, TIFF, or GIF source images." || true
    scan_status=1
  fi
  return "$scan_status"
}

forge_validate_output_name() {
  local output_name="$1"
  [[ -n "$output_name" ]] || { usage_fail "Output name must not be empty"; return 2; }
  [[ "$output_name" != "." && "$output_name" != ".." ]] || {
    usage_fail "Output name must be a basename" || return 2
  }
  [[ "$output_name" != */* ]] || {
    usage_fail "Output name must not contain path separators: $output_name" || return 2
  }
}

forge_validate_operand_shape() {
  local recursive="$1"
  shift
  local -a operands=("$@")
  local first="${operands[0]:-}"
  local input
  local output_name

  [[ "${#operands[@]}" -gt 0 ]] || {
    forge_help >&2
    usage_fail "forge requires an input image or directory" || return 2
  }
  for input in "${operands[@]}"; do
    [[ -n "$input" ]] || { usage_fail "Forge operands must not be empty"; return 2; }
  done

  if [[ -d "$first" ]]; then
    [[ "$recursive" == true ]] || {
      usage_fail "Directory input requires -r/--recursive: $first" || return 2
    }
    [[ "${#operands[@]}" -eq 1 ]] || {
      usage_fail "Recursive forge accepts exactly one directory" || return 2
    }
    return 0
  fi

  [[ "$recursive" != true ]] || {
    usage_fail "-r/--recursive requires exactly one directory input" || return 2
  }

  if [[ "${#operands[@]}" -eq 2 && -f "$first" && ! -L "$first" ]] &&
     ! { [[ -f "${operands[1]}" && ! -L "${operands[1]}" ]] && forge_supported_extension "${operands[1]}"; }; then
    output_name="${operands[1]}"
    forge_validate_output_name "$output_name" || return $?
    case "$(printf '%s' "$output_name" | tr '[:upper:]' '[:lower:]')" in
      *.icns) output_name="${output_name%.*}" ;;
    esac
    forge_validate_output_name "$output_name" || return $?
  fi
}

forge_collect_inputs() {
  local recursive="$1"
  local output_root="$2"
  shift 2
  local -a operands=("$@")
  local first="${operands[0]:-}"
  local output_name=""
  local input
  local input_abs
  local root_abs=""
  local relative_path
  local stem
  local index
  local collection_status=0

  [[ "${#operands[@]}" -gt 0 ]] || {
    forge_help >&2
    usage_fail "forge requires an input image or directory" || return 2
  }
  for input in "${operands[@]}"; do
    [[ -n "$input" ]] || { usage_fail "Forge operands must not be empty"; return 2; }
  done

  if [[ -d "$first" ]]; then
    [[ "$recursive" == true ]] || {
      usage_fail "Directory input requires -r/--recursive: $first" || return 2
    }
    [[ "${#operands[@]}" -eq 1 ]] || {
      usage_fail "Recursive forge accepts exactly one directory" || return 2
    }
    root_abs="$(realpath -- "$first")" || return 1
    forge_collect_recursive_inputs "$root_abs" "$output_root" || collection_status=1
  else
    [[ "$recursive" != true ]] || {
      usage_fail "-r/--recursive requires exactly one directory input" || return 2
    }

    if [[ "${#operands[@]}" -eq 2 && -f "$first" && ! -L "$first" ]] &&
       ! { [[ -f "${operands[1]}" && ! -L "${operands[1]}" ]] && forge_supported_extension "${operands[1]}"; }; then
      output_name="${operands[1]}"
      forge_validate_output_name "$output_name" || return $?
      if input_abs="$(realpath -- "$first")"; then
        FORGE_INPUTS+=("$input_abs")
      else
        fail "Could not resolve input image: $first. Check that it still exists and is readable." || true
        collection_status=1
      fi
    else
      for input in "${operands[@]}"; do
        if [[ ! -f "$input" || -L "$input" ]]; then
          fail "Input image not found or not a regular file: $input. Supply an existing regular image file, not a symlink." || true
          collection_status=1
          continue
        fi
        if ! forge_supported_extension "$input"; then
          fail "Unsupported input image: $input. Supply PNG, JPEG, WebP, TIFF, or GIF source images." || true
          collection_status=1
          continue
        fi
        if input_abs="$(realpath -- "$input")"; then
          FORGE_INPUTS+=("$input_abs")
        else
          fail "Could not resolve input image: $input. Check that it still exists and is readable." || true
          collection_status=1
        fi
      done
    fi
  fi

  for input_abs in "${FORGE_INPUTS[@]+"${FORGE_INPUTS[@]}"}"; do
    if ! forge_supported_extension "$input_abs"; then
      fail "Unsupported input image: $input_abs. Supply PNG, JPEG, WebP, TIFF, or GIF source images." || true
      collection_status=1
    fi

    if [[ -n "$root_abs" ]]; then
      relative_path="${input_abs#"$root_abs"/}"
      stem="${relative_path%.*}"
    elif [[ -n "$output_name" ]]; then
      stem="$output_name"
      case "$(printf '%s' "$stem" | tr '[:upper:]' '[:lower:]')" in
        *.icns) stem="${stem%.*}" ;;
      esac
      forge_validate_output_name "$stem" || return $?
    else
      stem="$(basename "$input_abs")"
      stem="${stem%.*}"
    fi

    if [[ -z "${stem##*/}" ]]; then
      fail "Could not derive an output name for $input_abs. Rename the source to include a basename before its extension." || true
      collection_status=1
    fi
    FORGE_STEMS+=("$stem")
    FORGE_ICNS_TARGETS+=("$output_root/$stem.icns")
    FORGE_PNG_TARGETS+=("$output_root/$stem.png")
    FORGE_PNG_NOOPS+=(false)
  done

  if [[ -z "$root_abs" && "${#FORGE_INPUTS[@]}" -gt 1 ]]; then
    local -a sorted_records=()
    local record
    while IFS= read -r -d '' record; do
      sorted_records+=("$record")
    done < <(
      for ((index = 0; index < ${#FORGE_INPUTS[@]}; index++)); do
        printf '%s\t%s\t%s\t%s\0' \
          "${FORGE_INPUTS[$index]}" "${FORGE_STEMS[$index]}" \
          "${FORGE_ICNS_TARGETS[$index]}" "${FORGE_PNG_TARGETS[$index]}"
      done | sort -z
    )
    FORGE_INPUTS=()
    FORGE_STEMS=()
    FORGE_ICNS_TARGETS=()
    FORGE_PNG_TARGETS=()
    FORGE_PNG_NOOPS=()
    for record in "${sorted_records[@]}"; do
      FORGE_INPUTS+=("${record%%$'\t'*}")
      record="${record#*$'\t'}"
      FORGE_STEMS+=("${record%%$'\t'*}")
      record="${record#*$'\t'}"
      FORGE_ICNS_TARGETS+=("${record%%$'\t'*}")
      FORGE_PNG_TARGETS+=("${record#*$'\t'}")
      FORGE_PNG_NOOPS+=(false)
    done
  fi
  return "$collection_status"
}

forge_validate_target() {
  local target="$1"
  local canonical_target
  local canonical_input
  local target_key
  local input_key
  local ancestor

  canonical_target="$(forge_canonical_destination "$target")" || {
    fail "Could not resolve output destination: $target. Check its parent directories and symlinks." || return 1
  }
  target_key="$(forge_case_key "$canonical_target")" || return 1

  for canonical_input in "${FORGE_INPUTS[@]}"; do
    if [[ -e "$target" && "$target" -ef "$canonical_input" ]]; then
      return 10
    fi
    input_key="$(forge_case_key "$canonical_input")" || return 1
    if [[ "$target_key" == "$input_key" ]]; then
      return 10
    fi
  done

  if [[ -L "$target" ]]; then
    fail "Output target is a symlink and cannot be replaced: $target. Choose another output directory or remove the symlink yourself." || return 1
  fi
  if [[ -e "$target" && ! -f "$target" ]]; then
    fail "Output target is not a regular file: $target. Choose another output name or directory." || return 1
  fi
  ancestor="$(dirname "$target")"
  while [[ ! -e "$ancestor" && ! -L "$ancestor" && "$ancestor" != / ]]; do
    ancestor="$(dirname "$ancestor")"
  done
  if [[ ! -d "$ancestor" ]]; then
    fail "Output ancestor is not a directory: $ancestor. Choose an output directory with valid directory ancestors." || return 1
  fi
  if [[ ! -w "$ancestor" || ! -x "$ancestor" ]]; then
    fail "Output directory is not writable or searchable: $ancestor. Choose a writable output directory or correct its access permissions." || return 1
  fi
  return 0
}

forge_preflight_manifest() {
  local keep_png="$1"
  local index
  local input
  local target
  local canonical_target
  local key
  local target_status
  local dimensions
  local width
  local height
  local preflight_status=0
  local processor_ready=true
  local target_kind
  local -a planned_keys=()
  local -a target_kinds=(icns)

  [[ "$keep_png" != true ]] || target_kinds+=(png)
  if ! require_processor; then
    processor_ready=false
    preflight_status=1
  fi
  FORGE_EXISTING_TARGETS=()
  for ((index = 0; index < ${#FORGE_INPUTS[@]}; index++)); do
    input="${FORGE_INPUTS[$index]}"
    if [[ "$processor_ready" == false ]]; then
      :
    elif ! dimensions="$("$ICONFORGE_PROCESSOR" info "$input" 2>&1)"; then
      fail "Could not decode input image: $input. Re-export it as a supported image and verify that the complete file is readable." || true
      [[ -z "$dimensions" ]] || stderr "Processor diagnostic: $dimensions"
      preflight_status=1
    elif [[ ! "$dimensions" =~ ^[0-9]+x[0-9]+$ ]]; then
      fail "Processor returned invalid dimensions for $input: $dimensions. Reinstall IconForge if a freshly exported image produces the same result." || true
      preflight_status=1
    else
      width="${dimensions%x*}"
      height="${dimensions#*x}"
      if [[ "$width" -eq 0 || "$height" -eq 0 ]]; then
        fail "Source image has an empty dimension: $input ($dimensions). Re-export it with nonzero width and height." || true
        preflight_status=1
      elif [[ "$width" -lt 512 || "$height" -lt 512 ]]; then
        warn "Source image is ${width}x${height}; macOS icons look best at 512x512 or larger: $input"
      fi
    fi

    for target_kind in "${target_kinds[@]}"; do
      if [[ "$target_kind" == icns ]]; then
        target="${FORGE_ICNS_TARGETS[$index]}"
      else
        target="${FORGE_PNG_TARGETS[$index]}"
      fi
      if ! canonical_target="$(forge_canonical_destination "$target")"; then
        fail "Could not resolve output destination: $target. Check its parent directories and symlinks." || true
        preflight_status=1
        continue
      fi
      if ! key="$(forge_case_key "$canonical_target")"; then
        preflight_status=1
        continue
      fi
      if forge_array_contains "$key" "${planned_keys[@]+"${planned_keys[@]}"}"; then
        fail "Two planned outputs map to the same path: $target. Rename the colliding inputs or use recursive mode to preserve their directories." || true
        preflight_status=1
      fi
      planned_keys+=("$key")

      target_status=0
      forge_validate_target "$target" || target_status=$?
      case "$target_status" in
        0) [[ ! -e "$target" ]] || FORGE_EXISTING_TARGETS+=("$target") ;;
        10)
          if [[ "$target_kind" == png ]] && forge_is_png "$input" && [[ "$input" == "$canonical_target" ]]; then
            FORGE_PNG_NOOPS[index]=true
          else
            fail "Planned output would overwrite a selected input: $target. Choose another output name or directory." || true
            preflight_status=1
          fi
          ;;
        *) preflight_status=1 ;;
      esac
    done
  done
  if [[ "$preflight_status" -ne 0 ]]; then
    note "Forge preflight found errors. No output files were written; resolve all reported input and destination problems before retrying."
  fi
  return "$preflight_status"
}

forge_confirm_overwrites() {
  local force="$1"
  local dry_run="$2"
  local response
  local target

  [[ "${#FORGE_EXISTING_TARGETS[@]}" -gt 0 ]] || return 0

  if [[ "$dry_run" == true ]]; then
    for target in "${FORGE_EXISTING_TARGETS[@]}"; do
      printf 'Would overwrite: %s\n' "$target"
    done
    return 0
  fi
  [[ "$force" == true ]] && return 0

  stderr "Existing output files:"
  for target in "${FORGE_EXISTING_TARGETS[@]}"; do
    stderr "  $target"
  done

  if [[ ! -t 0 || ( "${ICONFORGE_STDERR_IS_TTY:-false}" != true && ! -t 2 ) ]]; then
    fail "Existing outputs require -f/--force in noninteractive mode" || return 1
  fi

  printf 'Overwrite all listed files? (y/N): ' >&2
  read -r response
  [[ "$response" =~ ^[Yy]$ ]] || {
    fail "No files were written. Rerun with -f/--force to replace them." || return 1
  }
}

forge_generate_one() {
  local input="$1"
  local work_dir="$2"
  local keep_png="$3"
  local png_noop="$4"
  local source_png="$input"
  local output_icns="$work_dir/output.icns"
  local output_png="$work_dir/output.png"
  local iconset_dir="$work_dir/iconset"
  local -a icon_specs=(
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
  local spec_width
  local spec_height
  local spec_name

  mkdir -p "$iconset_dir" || return 1
  if ! forge_is_png "$input"; then
    source_png="$work_dir/source.png"
    "$ICONFORGE_PROCESSOR" convert "$input" "$source_png" || return 1
  fi

  if [[ "$keep_png" == true && "$png_noop" != true ]]; then
    cp "$source_png" "$output_png" || return 1
  fi

  for spec in "${icon_specs[@]}"; do
    read -r spec_width spec_height spec_name <<< "$spec"
    "$ICONFORGE_PROCESSOR" resize "$source_png" "$spec_width" "$spec_height" "$iconset_dir/$spec_name" || return 1
  done

  "$ICONFORGE_PROCESSOR" icns "$output_icns" \
    "$iconset_dir/icon_16x16.png" \
    "$iconset_dir/icon_32x32.png" \
    "$iconset_dir/icon_32x32@2x.png" \
    "$iconset_dir/icon_128x128.png" \
    "$iconset_dir/icon_256x256.png" \
    "$iconset_dir/icon_512x512.png" \
    "$iconset_dir/icon_512x512@2x.png" >/dev/null || return 1
}

forge_stage_all() {
  local stage_root="$1"
  local keep_png="$2"
  local index
  local item_dir
  local stage_status=0

  FORGE_STAGE_ICNS=()
  FORGE_STAGE_PNG=()
  for ((index = 0; index < ${#FORGE_INPUTS[@]}; index++)); do
    [[ "${FORGE_INTERRUPT_STATUS:-0}" -eq 0 ]] || return 1
    item_dir="$stage_root/item-$index"
    if ! mkdir -p "$item_dir"; then
      fail "Could not create a staging directory for ${FORGE_INPUTS[$index]}. Check temporary disk space and directory access." || true
      stage_status=1
      continue
    fi
    note "Forging ${FORGE_STEMS[$index]} ($((index + 1))/${#FORGE_INPUTS[@]})"
    if ! forge_generate_one "${FORGE_INPUTS[$index]}" "$item_dir" "$keep_png" "${FORGE_PNG_NOOPS[$index]}"; then
      fail "Failed to forge ${FORGE_INPUTS[$index]}. Review the processor diagnostic above; check source readability and available temporary disk space." || true
      stage_status=1
      continue
    fi
    [[ "${FORGE_INTERRUPT_STATUS:-0}" -eq 0 ]] || return 1
    FORGE_STAGE_ICNS[index]="$item_dir/output.icns"
    if [[ "$keep_png" == true && "${FORGE_PNG_NOOPS[$index]}" != true ]]; then
      FORGE_STAGE_PNG[index]="$item_dir/output.png"
    else
      FORGE_STAGE_PNG[index]=""
    fi
  done
  if [[ "$stage_status" -ne 0 ]]; then
    note "Forge generation found errors. No output files were published; the remaining independent inputs were checked."
  fi
  return "$stage_status"
}

forge_collect_missing_directories() {
  local output_root="$1"
  shift
  local target
  local directory
  local -a reverse=()
  local -a collected=()

  for target in "$@"; do
    directory="$(dirname "$target")"
    reverse=()
    while [[ ! -d "$directory" ]]; do
      if [[ -e "$directory" || -L "$directory" ]]; then
        fail "Output ancestor is not a directory: $directory" || return 1
      fi
      reverse+=("$directory")
      [[ "$directory" != "/" ]] || break
      directory="$(dirname "$directory")"
    done
    [[ -d "$directory" ]] || {
      fail "Output ancestor is not a directory: $directory" || return 1
    }
    while [[ "${#reverse[@]}" -gt 0 ]]; do
      directory="${reverse[${#reverse[@]}-1]}"
      unset 'reverse[${#reverse[@]}-1]'
      if ! forge_array_contains "$directory" "${collected[@]+"${collected[@]}"}"; then
        collected+=("$directory")
      fi
    done
  done

  : "$output_root"
  printf '%s\0' "${collected[@]+"${collected[@]}"}"
}

forge_atomic_copy() {
  local source="$1"
  local target="$2"
  local target_dir
  local temporary

  target_dir="$(dirname "$target")"
  temporary="$(mktemp "$target_dir/.iconforge-publish.XXXXXX")" || return 1
  if ! cp -p "$source" "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  if ! "$ICONFORGE_NATIVE_ICON" rename-exact "$temporary" "$target" >/dev/null; then
    rm -f "$temporary"
    return 1
  fi
}

forge_atomic_copy_no_clobber() {
  local source="$1"
  local target="$2"
  local target_dir
  local temporary

  target_dir="$(dirname "$target")"
  temporary="$(mktemp "$target_dir/.iconforge-publish.XXXXXX")" || return 1
  if ! cp -p "$source" "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  if ! "$ICONFORGE_NATIVE_ICON" link-exclusive "$temporary" "$target" >/dev/null; then
    rm -f "$temporary"
    return 1
  fi
  rm -f "$temporary"
}

forge_cleanup_stage_dir() {
  local stage_dir="${1:-}"
  local stage_parent
  local temporary_root

  [[ -n "$stage_dir" && -d "$stage_dir" ]] || return 0
  [[ "$stage_dir" != "${FORGE_RECOVERY_STAGE:-}" ]] || return 0
  [[ "$(basename "$stage_dir")" == iconforge-forge.* ]] || return 0
  stage_parent="$(realpath -- "$(dirname "$stage_dir")")" || return 0
  temporary_root="$(realpath -- "$(iconforge_temp_root)")" || return 0
  [[ "$stage_parent" == "$temporary_root" ]] || return 0
  rm -rf -- "$stage_dir"
}

forge_restore_saved_trap() {
  local saved_trap="$1"
  local signal_name="$2"
  if [[ -n "$saved_trap" ]]; then
    eval "$saved_trap"
  else
    trap - "$signal_name"
  fi
}

forge_restore_cleanup_traps() {
  forge_restore_saved_trap "$1" EXIT
  forge_restore_saved_trap "$2" HUP
  forge_restore_saved_trap "$3" INT
  forge_restore_saved_trap "$4" TERM
}

forge_publish_all() {
  local stage_root="$1"
  local output_root="$2"
  local keep_png="$3"
  local index
  local target
  local source
  local backup
  local directory
  local rollback_failed=false
  local -a publish_sources=()
  local -a publish_targets=()
  local -a published_targets=()
  local -a backups=()
  local -a planned_directories=()
  local -a created_directories=()

  for ((index = 0; index < ${#FORGE_INPUTS[@]}; index++)); do
    publish_sources+=("${FORGE_STAGE_ICNS[$index]}")
    publish_targets+=("${FORGE_ICNS_TARGETS[$index]}")
    if [[ "$keep_png" == true && "${FORGE_PNG_NOOPS[$index]}" != true ]]; then
      publish_sources+=("${FORGE_STAGE_PNG[$index]}")
      publish_targets+=("${FORGE_PNG_TARGETS[$index]}")
    fi
  done

  if ! forge_collect_missing_directories "$output_root" "${publish_targets[@]}" >"$stage_root/directories"; then
    return 1
  fi
  while IFS= read -r -d '' directory; do
    [[ -z "$directory" ]] || planned_directories+=("$directory")
  done <"$stage_root/directories"

  for directory in "${planned_directories[@]+"${planned_directories[@]}"}"; do
    mkdir "$directory" || {
      fail "Could not create output directory: $directory" || true
      for ((index = ${#created_directories[@]} - 1; index >= 0; index--)); do
        rmdir "${created_directories[$index]}" 2>/dev/null || true
      done
      return 1
    }
    created_directories+=("$directory")
  done

  for ((index = 0; index < ${#publish_targets[@]}; index++)); do
    if [[ "${FORGE_INTERRUPT_STATUS:-0}" -ne 0 ]]; then
      fail "Forge was interrupted before publication completed" || true
      break
    fi
    target="${publish_targets[$index]}"
    backup=""
    if forge_array_contains "$target" "${FORGE_EXISTING_TARGETS[@]+"${FORGE_EXISTING_TARGETS[@]}"}"; then
      [[ -f "$target" && ! -L "$target" ]] || {
        fail "An existing output changed after preflight: $target" || true
        break
      }
      backup="$stage_root/backup-$index"
      cp -p "$target" "$backup" || {
        fail "Could not preserve existing output before replacement: $target" || true
        break
      }
    fi
    backups+=("$backup")
    source="${publish_sources[$index]}"
    if [[ -n "$backup" ]]; then
      if ! forge_atomic_copy "$source" "$target"; then
        fail "Could not publish output: $target" || true
        break
      fi
    else
      if ! forge_atomic_copy_no_clobber "$source" "$target"; then
        fail "Could not publish new output: $target. The destination may have appeared after preflight, or directory access or disk space may have changed. Rolling back outputs from this run." || true
        break
      fi
    fi
    published_targets+=("$target")
    if [[ "${FORGE_INTERRUPT_STATUS:-0}" -ne 0 ]]; then
      fail "Forge was interrupted during publication; rolling back" || true
      break
    fi
  done

  if [[ "${#published_targets[@]}" -ne "${#publish_targets[@]}" || "${FORGE_INTERRUPT_STATUS:-0}" -ne 0 ]]; then
    for ((index = ${#published_targets[@]} - 1; index >= 0; index--)); do
      target="${published_targets[$index]}"
      backup="${backups[$index]:-}"
      if [[ -n "$backup" ]]; then
        if ! forge_atomic_copy "$backup" "$target"; then
          fail "Could not restore original output: $target. Its recovery copy is $backup. Restore it after correcting destination access or disk space." || true
          rollback_failed=true
        fi
      else
        if ! rm -f "$target"; then
          fail "Could not remove new output during rollback: $target. Remove this incomplete-run output after correcting directory access." || true
          rollback_failed=true
        fi
      fi
    done
    for ((index = ${#created_directories[@]} - 1; index >= 0; index--)); do
      rmdir "${created_directories[$index]}" 2>/dev/null || true
    done
    if [[ "$rollback_failed" == true ]]; then
      FORGE_RECOVERY_STAGE="$stage_root"
      warn "Output rollback was incomplete. Recovery files are preserved at $stage_root; do not remove them until every reported destination is restored."
    fi
    return 1
  fi

  for ((index = 0; index < ${#FORGE_INPUTS[@]}; index++)); do
    printf 'Created: %s\n' "${FORGE_ICNS_TARGETS[$index]}"
    if [[ "$keep_png" == true ]]; then
      printf 'PNG kept: %s\n' "${FORGE_PNG_TARGETS[$index]}"
    fi
  done
  return 0
}

forge_print_dry_run() {
  local keep_png="$1"
  local index
  for ((index = 0; index < ${#FORGE_INPUTS[@]}; index++)); do
    printf 'Would forge: %s -> %s\n' "${FORGE_INPUTS[$index]}" "${FORGE_ICNS_TARGETS[$index]}"
    if [[ "$keep_png" == true ]]; then
      if [[ "${FORGE_PNG_NOOPS[$index]}" == true ]]; then
        printf 'PNG already kept: %s\n' "${FORGE_PNG_TARGETS[$index]}"
      else
        printf 'Would keep PNG: %s\n' "${FORGE_PNG_TARGETS[$index]}"
      fi
    fi
  done
  return 0
}

cmd_forge() {
  local output_dir=""
  local output_root
  local keep_png=false
  local recursive=false
  local force=false
  local dry_run=false
  local parse_options=true
  local stage_root=""
  local saved_exit_trap
  local saved_hup_trap
  local saved_int_trap
  local saved_term_trap
  local preflight_status=0
  local collection_status=0
  local -a operands=()

  forge_reset_manifest
  FORGE_INTERRUPT_STATUS=0
  FORGE_RECOVERY_STAGE=""

  while [[ $# -gt 0 ]]; do
    if [[ "$parse_options" == true ]]; then
      case "$1" in
        -o|--output)
          [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { usage_fail "$1 requires an output directory"; return 2; }
          output_dir="$2"
          shift 2
          continue
          ;;
        -k|--keep-png) keep_png=true; shift; continue ;;
        -r|--recursive) recursive=true; shift; continue ;;
        -f|--force) force=true; shift; continue ;;
        -d|--dry-run) dry_run=true; shift; continue ;;
        -h|--help) forge_help; return 0 ;;
        --) parse_options=false; shift; continue ;;
        --*=*) usage_fail "Option values must be separate tokens: $1"; return 2 ;;
        -*) usage_fail "Unknown forge option: $1"; return 2 ;;
      esac
    fi
    operands+=("$1")
    shift
  done

  forge_validate_operand_shape "$recursive" ${operands[@]+"${operands[@]}"} || return $?
  if [[ -z "$output_dir" ]]; then
    load_iconforge_config || return 1
    if [[ "$ICONFORGE_HAS_DEFAULT_DIRECTORY" == true ]]; then
      output_dir="$ICONFORGE_DEFAULT_DIRECTORY"
    else
      output_dir="$PWD"
    fi
  fi
  output_root="$(forge_canonical_destination "$output_dir")" || {
    fail "Could not resolve output directory: $output_dir" || return 1
  }
  forge_collect_inputs "$recursive" "$output_root" ${operands[@]+"${operands[@]}"} || collection_status=$?
  [[ "$collection_status" -ne 2 ]] || return 2
  [[ "$collection_status" -eq 0 ]] || preflight_status=1
  if [[ -e "$output_root" && ! -d "$output_root" ]]; then
    fail "Output path is not a directory: $output_root. Choose a directory for --output." || true
    preflight_status=1
  fi
  forge_preflight_manifest "$keep_png" || preflight_status=1
  if [[ "$preflight_status" -ne 0 ]]; then
    note "No output files were written. Resolve all reported errors and retry the forge command."
    return 1
  fi
  forge_confirm_overwrites "$force" "$dry_run" || return 1

  if [[ "$dry_run" == true ]]; then
    forge_print_dry_run "$keep_png"
    return 0
  fi

  stage_root="$(mktemp -d "$(iconforge_temp_root)/iconforge-forge.XXXXXX")" || {
    fail "Could not create a private forge staging directory" || return 1
  }

  saved_exit_trap="$(trap -p EXIT)"
  saved_hup_trap="$(trap -p HUP)"
  saved_int_trap="$(trap -p INT)"
  saved_term_trap="$(trap -p TERM)"
  trap 'forge_cleanup_stage_dir "$stage_root"' EXIT
  trap 'FORGE_INTERRUPT_STATUS=129' HUP
  trap 'FORGE_INTERRUPT_STATUS=130' INT
  trap 'FORGE_INTERRUPT_STATUS=143' TERM

  if ! forge_stage_all "$stage_root" "$keep_png"; then
    forge_cleanup_stage_dir "$stage_root"
    stage_root=""
    forge_restore_cleanup_traps "$saved_exit_trap" "$saved_hup_trap" "$saved_int_trap" "$saved_term_trap"
    if [[ "$FORGE_INTERRUPT_STATUS" -ne 0 ]]; then
      return "$FORGE_INTERRUPT_STATUS"
    fi
    return 1
  fi
  if ! forge_publish_all "$stage_root" "$output_root" "$keep_png"; then
    forge_cleanup_stage_dir "$stage_root"
    stage_root=""
    forge_restore_cleanup_traps "$saved_exit_trap" "$saved_hup_trap" "$saved_int_trap" "$saved_term_trap"
    if [[ "$FORGE_INTERRUPT_STATUS" -ne 0 ]]; then
      return "$FORGE_INTERRUPT_STATUS"
    fi
    return 1
  fi
  if [[ "$FORGE_INTERRUPT_STATUS" -ne 0 ]]; then
    forge_cleanup_stage_dir "$stage_root"
    stage_root=""
    forge_restore_cleanup_traps "$saved_exit_trap" "$saved_hup_trap" "$saved_int_trap" "$saved_term_trap"
    return "$FORGE_INTERRUPT_STATUS"
  fi
  forge_cleanup_stage_dir "$stage_root"
  stage_root=""
  forge_restore_cleanup_traps "$saved_exit_trap" "$saved_hup_trap" "$saved_int_trap" "$saved_term_trap"
  return 0
}
