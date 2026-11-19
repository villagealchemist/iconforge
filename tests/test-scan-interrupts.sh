#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="interrupted discovery cleanup"
source tests/test-common.sh
export XDG_CONFIG_HOME="$PWD/$TEST_DIR/config-home"

ABS_TEST_DIR="$PWD/$TEST_DIR"
TEMP_ROOT="$ABS_TEST_DIR/temp"
FAKE_BIN="$ABS_TEST_DIR/fakebin"
mkdir -p "$TEMP_ROOT" "$FAKE_BIN" "$ABS_TEST_DIR/images" "$ABS_TEST_DIR/library"
cp "$TEST_IMAGE1" "$ABS_TEST_DIR/images/source.png"
printf 'scan should be interrupted before validation\n' >"$ABS_TEST_DIR/library/example.icns"

cat >"$FAKE_BIN/find" <<'FIND'
#!/usr/bin/env bash
set -euo pipefail
printf 'Injected interruption during directory scan\n' >&2
kill -TERM "$PPID"
FIND
chmod +x "$FAKE_BIN/find"

for scenario in forge library; do
  status=0
  if [[ "$scenario" == forge ]]; then
    PATH="$FAKE_BIN:$PATH" TMPDIR="$TEMP_ROOT" "$ICONFORGE" forge "$ABS_TEST_DIR/images" \
      -r -o "$ABS_TEST_DIR/output" >"$ABS_TEST_DIR/$scenario.log" 2>&1 || status=$?
  else
    PATH="$FAKE_BIN:$PATH" TMPDIR="$TEMP_ROOT" "$ICONFORGE" apply --all "$ABS_TEST_DIR/library" \
      --dry-run >"$ABS_TEST_DIR/$scenario.log" 2>&1 || status=$?
  fi
  [[ "$status" -eq 143 ]] || {
    test_fail "Interrupted $scenario scan lost its signal status: $status"
    cat "$ABS_TEST_DIR/$scenario.log"
    exit 1
  }
  report="$(sed -n 's/^Full diagnostic report: //p' "$ABS_TEST_DIR/$scenario.log")"
  [[ -f "$report" && ! -L "$report" ]] || {
    test_fail "Interrupted $scenario scan did not retain its diagnostic report"
    exit 1
  }
  grep -Fx 'Exit status: 143' "$report" >/dev/null || {
    test_fail "Interrupted $scenario scan report did not finish"
    exit 1
  }
  grep -F 'Injected interruption during directory scan' "$report" >/dev/null || {
    test_fail "Interrupted $scenario scan lost its final diagnostic"
    exit 1
  }
  if find "${report%/report.log}" -mindepth 1 ! -name report.log -print -quit | grep -q .; then
    test_fail "Interrupted $scenario scan retained a manifest or capture pipe"
    exit 1
  fi
done

[[ ! -e "$ABS_TEST_DIR/output" ]] || {
  test_fail "Interrupted forge scan created output files"
  exit 1
}
if find "$TEMP_ROOT" -mindepth 1 -maxdepth 1 ! -name 'iconforge-report.*' -print -quit | grep -q .; then
  test_fail "Interrupted scans left temporary manifests outside their reports"
  exit 1
fi

test_pass "$TEST_NAME passed"
