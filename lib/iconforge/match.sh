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

match_find_by_explicit_path() {
  local expected_path="$1"
  local record

  for record in "${DISCOVERED_APP_RECORDS[@]+"${DISCOVERED_APP_RECORDS[@]}"}"; do
    [[ "$(discovered_app_path "$record")" == "$expected_path" ]] || continue
    MATCH_RECORD="$record"
    MATCH_STATUS="matched-explicit-path"
    return 0
  done

  MATCH_STATUS="missing-explicit-path"
  MATCH_MESSAGE="Configured application path was not found"
  return 1
}

match_find_by_bundle_id() {
  local bundle_id="$1"
  local record

  for record in "${DISCOVERED_APP_RECORDS[@]+"${DISCOVERED_APP_RECORDS[@]}"}"; do
    [[ "$(discovered_app_bundle_id "$record")" == "$bundle_id" ]] || continue
    MATCH_RECORD="$record"
    MATCH_STATUS="matched-bundle-id"
    return 0
  done

  return 1
}

record_matches_normalized_token_exact() {
  local record="$1"
  local token="$2"
  local values=(
    "$(discovered_app_display_name "$record")"
    "$(discovered_app_bundle_name "$record")"
    "$(discovered_app_file_name "$record")"
  )
  local value

  for value in "${values[@]+"${values[@]}"}"; do
    [[ -n "$value" ]] || continue
    [[ "$(normalize_match_token "$value")" == "$token" ]] && return 0
  done

  return 1
}

record_matches_normalized_token_partial() {
  local record="$1"
  local token="$2"
  local values=(
    "$(discovered_app_display_name "$record")"
    "$(discovered_app_bundle_name "$record")"
    "$(discovered_app_file_name "$record")"
  )
  local normalized_value
  local value

  for value in "${values[@]+"${values[@]}"}"; do
    [[ -n "$value" ]] || continue
    normalized_value="$(normalize_match_token "$value")"
    [[ "$normalized_value" == *"$token"* ]] && return 0
  done

  return 1
}

match_find_by_names() {
  local exact_tokens=("$@")
  local partial_token=""
  local token
  local record

  for token in "${exact_tokens[@]+"${exact_tokens[@]}"}"; do
    [[ -n "$token" ]] || continue
    partial_token="$token"
    for record in "${DISCOVERED_APP_RECORDS[@]+"${DISCOVERED_APP_RECORDS[@]}"}"; do
      record_matches_normalized_token_exact "$record" "$token" || continue
      match_add_candidate "$record"
    done
  done

  if [[ "${#MATCH_CANDIDATES[@]}" -eq 1 ]]; then
    MATCH_RECORD="${MATCH_CANDIDATES[0]}"
    MATCH_STATUS="matched-name"
    return 0
  fi

  if [[ "${#MATCH_CANDIDATES[@]}" -gt 1 ]]; then
    MATCH_STATUS="ambiguous-name"
    MATCH_MESSAGE="Multiple applications matched an exact alias or name"
    return 1
  fi

  if [[ -n "$partial_token" ]]; then
    for record in "${DISCOVERED_APP_RECORDS[@]+"${DISCOVERED_APP_RECORDS[@]}"}"; do
      record_matches_normalized_token_partial "$record" "$partial_token" || continue
      match_add_candidate "$record"
    done
  fi

  if [[ "${#MATCH_CANDIDATES[@]}" -eq 1 ]]; then
    MATCH_RECORD="${MATCH_CANDIDATES[0]}"
    MATCH_STATUS="matched-partial"
    return 0
  fi

  if [[ "${#MATCH_CANDIDATES[@]}" -gt 1 ]]; then
    MATCH_STATUS="ambiguous-partial"
    MATCH_MESSAGE="Multiple applications matched a partial alias or name"
    return 1
  fi

  return 1
}

match_configured_application() {
  local key="$1"
  local explicit_path=""
  local bundle_id=""
  local tokens=()
  local alias_value

  match_reset

  if config_is_excluded "$key"; then
    MATCH_STATUS="excluded"
    MATCH_MESSAGE="Application key is excluded by configuration"
    return 1
  fi

  explicit_path="$(config_lookup_value "$key" ICONFORGE_CONFIG_APP_PATHS || true)"
  if [[ -n "$explicit_path" ]]; then
    if match_find_by_explicit_path "$explicit_path"; then
      return 0
    fi
    return 1
  fi

  bundle_id="$(config_lookup_value "$key" ICONFORGE_CONFIG_APP_BUNDLE_IDS || true)"
  if [[ -n "$bundle_id" ]] && match_find_by_bundle_id "$bundle_id"; then
    return 0
  fi

  tokens+=("$(normalize_match_token "$key")")
  while IFS= read -r alias_value; do
    [[ -n "$alias_value" ]] || continue
    tokens+=("$(normalize_match_token "$alias_value")")
  done < <(config_get_aliases "$key")

  if match_find_by_names "${tokens[@]}"; then
    return 0
  fi

  if [[ -z "$MATCH_STATUS" ]]; then
    MATCH_STATUS="missing"
    MATCH_MESSAGE="No installed application matched this managed key"
  fi
  return 1
}
