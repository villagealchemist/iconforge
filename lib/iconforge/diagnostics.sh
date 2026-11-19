#!/usr/bin/env bash

ICONFORGE_REPORT_DIRECTORY=""
ICONFORGE_REPORT_FILE=""
ICONFORGE_REPORT_STDOUT_PID=""
ICONFORGE_REPORT_STDERR_PID=""

diagnostics_start() {
  local candidate
  local report_root
  ICONFORGE_STDERR_IS_TTY=false
  # shellcheck disable=SC2034 # Read by match.sh after stderr is redirected.
  [[ ! -t 2 ]] || ICONFORGE_STDERR_IS_TTY=true
  for candidate in "${TMPDIR:-/tmp}" /tmp; do
    [[ -d "$candidate" && -w "$candidate" ]] || continue
    report_root="${candidate%/}"
    ICONFORGE_REPORT_DIRECTORY="$(umask 077; mktemp -d "$report_root/iconforge-report.XXXXXX" 2>/dev/null)" || continue
    break
  done
  if [[ -z "$ICONFORGE_REPORT_DIRECTORY" ]]; then
    warn "Could not create a diagnostic report in the temporary directory or /tmp. Errors will still be printed."
    return 0
  fi
  ICONFORGE_REPORT_FILE="$ICONFORGE_REPORT_DIRECTORY/report.log"
  if ! (umask 077
    {
      printf 'IconForge %s diagnostic report\n' "$ICONFORGE_VERSION"
      printf 'Started: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      printf 'System: %s\n' "$(/usr/bin/uname -smr)"
      printf 'Runtime: %s\n' "$ICONFORGE_ROOT"
      printf 'Command: iconforge %s\n' "$(format_cmd "$@")"
      printf 'Working directory: %s\n\n' "$PWD"
    } >"$ICONFORGE_REPORT_FILE" || exit 1
    mkfifo "$ICONFORGE_REPORT_DIRECTORY/stdout" "$ICONFORGE_REPORT_DIRECTORY/stderr"
  ); then
    warn "Could not initialize the diagnostic report. Errors will still be printed."
    /bin/rm -rf "$ICONFORGE_REPORT_DIRECTORY"
    ICONFORGE_REPORT_DIRECTORY=""
    ICONFORGE_REPORT_FILE=""
    return 0
  fi

  exec 3>&1 4>&2
  (trap '' HUP INT TERM; exec /usr/bin/tee -a "$ICONFORGE_REPORT_FILE") <"$ICONFORGE_REPORT_DIRECTORY/stdout" >&3 2>&4 &
  ICONFORGE_REPORT_STDOUT_PID=$!
  (trap '' HUP INT TERM; exec /usr/bin/tee -a "$ICONFORGE_REPORT_FILE") <"$ICONFORGE_REPORT_DIRECTORY/stderr" >&4 2>&4 &
  ICONFORGE_REPORT_STDERR_PID=$!
  exec >"$ICONFORGE_REPORT_DIRECTORY/stdout" 2>"$ICONFORGE_REPORT_DIRECTORY/stderr"
  export ICONFORGE_DIAGNOSTIC_CAPTURE=1
  trap 'diagnostics_finish "$?"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

diagnostics_finish() {
  local status="$1"
  local capture_failed=false
  local cleanup_warning
  trap - EXIT
  trap '' HUP INT TERM
  set +e
  exec 1>&3 2>&4 3>&- 4>&-
  wait "$ICONFORGE_REPORT_STDOUT_PID" || capture_failed=true
  wait "$ICONFORGE_REPORT_STDERR_PID" || capture_failed=true
  /bin/rm -f "$ICONFORGE_REPORT_DIRECTORY/stdout" "$ICONFORGE_REPORT_DIRECTORY/stderr"
  if ! /bin/rm -f -- "$ICONFORGE_REPORT_DIRECTORY"/iconforge-inputs.* \
      "$ICONFORGE_REPORT_DIRECTORY"/iconforge-library.*; then
    cleanup_warning="Could not remove temporary scan manifests from $ICONFORGE_REPORT_DIRECTORY."
    warn "$cleanup_warning"
    printf 'Warning: %s\n' "$cleanup_warning" >>"$ICONFORGE_REPORT_FILE" || capture_failed=true
  fi

  if [[ "$status" -ne 0 || "$capture_failed" == true ]] ||
      /usr/bin/grep -Eq '^(Warning:|Error:|Remedy:)' "$ICONFORGE_REPORT_FILE"; then
    if ! {
      printf '\nExit status: %s\n' "$status"
      [[ "$capture_failed" != true ]] || printf 'Warning: output capture failed; this report may be incomplete.\n'
    } >>"$ICONFORGE_REPORT_FILE"; then
      capture_failed=true
    fi
    if [[ "$status" -ne 0 ]]; then
      if [[ "$status" -eq 2 ]]; then
        note "Remedy: correct the reported arguments; use iconforge help for command syntax."
      else
        note "Review the errors and remedies above. Completed and skipped work remain listed in the report."
      fi
    fi
    [[ "$capture_failed" != true ]] || warn "Output capture failed; the report may be incomplete."
    note "Full diagnostic report: $ICONFORGE_REPORT_FILE"
  else
    /bin/rm -rf "$ICONFORGE_REPORT_DIRECTORY"
  fi
  exit "$status"
}
