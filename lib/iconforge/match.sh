#!/usr/bin/env bash

MATCH_STATUS=""
MATCH_MESSAGE=""
MATCH_RECORD=""
MATCH_CANDIDATES=()

match_reset() {
  MATCH_STATUS=""
  MATCH_MESSAGE=""
  MATCH_RECORD=""
  MATCH_CANDIDATES=()
}

match_add_candidate() {
  local record="$1"
  local existing
  for existing in "${MATCH_CANDIDATES[@]+"${MATCH_CANDIDATES[@]}"}"; do
    [[ "$existing" == "$record" ]] && return 0
  done
  MATCH_CANDIDATES+=("$record")
}

match_expand_duplicate_bundle_id() {
  local bundle_id=""
  local index
  [[ "${#MATCH_CANDIDATES[@]}" -eq 1 ]] || return 0
  for ((index = 0; index < ${#DISCOVERED_APP_RECORDS[@]}; index++)); do
    [[ "${DISCOVERED_APP_RECORDS[$index]}" == "${MATCH_CANDIDATES[0]}" ]] || continue
    bundle_id="${DISCOVERED_APP_BUNDLE_IDS[$index]}"
    break
  done
  [[ -n "$bundle_id" ]] || return 0
  for ((index = 0; index < ${#DISCOVERED_APP_RECORDS[@]}; index++)); do
    [[ "${DISCOVERED_APP_BUNDLE_IDS[$index]}" == "$bundle_id" ]] || continue
    match_add_candidate "${DISCOVERED_APP_RECORDS[$index]}"
  done
}

record_matches_normalized_token_exact() {
  local index="$1" token="$2"
  [[ "${DISCOVERED_APP_FILE_KEYS[$index]}" == "$token" ||
     "${DISCOVERED_APP_DISPLAY_KEYS[$index]}" == "$token" ||
     "${DISCOVERED_APP_BUNDLE_KEYS[$index]}" == "$token" ]]
}

record_matches_normalized_token_partial() {
  local index="$1" token="$2"
  [[ "${DISCOVERED_APP_FILE_KEYS[$index]}" == *"$token"* ||
     "${DISCOVERED_APP_DISPLAY_KEYS[$index]}" == *"$token"* ||
     "${DISCOVERED_APP_BUNDLE_KEYS[$index]}" == *"$token"* ]]
}

match_application_name() {
  local requested="$1"
  local token
  local index

  match_reset
  token="$(normalize_match_token "$requested")"
  if [[ -z "$token" ]]; then
    MATCH_STATUS="missing"
    MATCH_MESSAGE="Application name is empty after normalization"
    return 1
  fi

  for ((index = 0; index < ${#DISCOVERED_APP_RECORDS[@]}; index++)); do
    record_matches_normalized_token_exact "$index" "$token" || continue
    match_add_candidate "${DISCOVERED_APP_RECORDS[$index]}"
  done
  match_expand_duplicate_bundle_id

  case "${#MATCH_CANDIDATES[@]}" in
    1)
      MATCH_RECORD="${MATCH_CANDIDATES[0]}"
      MATCH_STATUS="matched-exact"
      return 0
      ;;
    0) ;;
    *)
      MATCH_STATUS="ambiguous-exact"
      MATCH_MESSAGE="Multiple installed applications share this exact match or bundle identifier"
      return 1
      ;;
  esac

  for ((index = 0; index < ${#DISCOVERED_APP_RECORDS[@]}; index++)); do
    record_matches_normalized_token_partial "$index" "$token" || continue
    match_add_candidate "${DISCOVERED_APP_RECORDS[$index]}"
  done
  match_expand_duplicate_bundle_id

  case "${#MATCH_CANDIDATES[@]}" in
    1)
      MATCH_RECORD="${MATCH_CANDIDATES[0]}"
      MATCH_STATUS="matched-partial"
      return 0
      ;;
    0)
      MATCH_STATUS="missing"
      MATCH_MESSAGE="No installed application matched this name"
      ;;
    *)
      MATCH_STATUS="ambiguous-partial"
      MATCH_MESSAGE="Multiple installed applications share this partial match or bundle identifier"
      ;;
  esac
  return 1
}

print_match_candidates() {
  local record
  for record in "${MATCH_CANDIDATES[@]+"${MATCH_CANDIDATES[@]}"}"; do
    printf '  %s\n' "$(discovered_app_path "$record")" >&2
  done
}

iconforge_input_is_tty() {
  [[ -t 0 && ( "${ICONFORGE_STDERR_IS_TTY:-false}" == true || -t 2 ) ]]
}

confirm_app_suggestion() {
  local requested="$1"
  local record="$2"
  local answer=""
  local suggestion
  suggestion="$(discovered_app_path "$record")"

  if ! iconforge_input_is_tty; then
    fail "No exact application match for '$requested'. Retry with the exact app path: $(printf '%q' "$suggestion")" || return 1
  fi

  printf "Did you mean '%s'? [y/N] " "$suggestion" >&2
  IFS= read -r answer || answer=""
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
  esac
  fail "Application selection declined. Retry with the exact path: $suggestion" || return 1
}

RESOLVED_APP_PATH=""

resolve_app_path() {
  local input="${1:-}"
  local record

  RESOLVED_APP_PATH=""
  require_nonempty_path "App" "$input" || return 1

  case "$input" in
    */*|.*)
      if [[ -d "$input" && -f "$input/Contents/Info.plist" ]]; then
        RESOLVED_APP_PATH="$(realpath -- "$input")"
        printf '%s\n' "$RESOLVED_APP_PATH"
        return 0
      fi
      fail "App bundle not found or invalid: $input" || return 1
      ;;
  esac

  discover_applications || return 1
  if match_application_name "$input"; then
    record="$MATCH_RECORD"
    if [[ "$MATCH_STATUS" == "matched-partial" ]]; then
      confirm_app_suggestion "$input" "$record" || return 1
    fi
    RESOLVED_APP_PATH="$(discovered_app_path "$record")"
    printf '%s\n' "$RESOLVED_APP_PATH"
    return 0
  fi

  stderr "Error: Could not resolve app bundle: $input"
  [[ -n "$MATCH_MESSAGE" ]] && stderr "$MATCH_MESSAGE"
  if [[ "${#MATCH_CANDIDATES[@]}" -gt 0 ]]; then
    stderr "Matches:"
    print_match_candidates
  fi
  return 1
}
