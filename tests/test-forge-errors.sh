#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="comprehensive forge errors"
source tests/test-common.sh
export XDG_CONFIG_HOME="$PWD/$TEST_DIR/config-home"
mkdir -p "$TEST_DIR/input" "$TEST_DIR/output"
printf 'broken first image\n' >"$TEST_DIR/input/first.png"
printf 'broken last image\n' >"$TEST_DIR/input/last.jpg"
cp "$TEST_IMAGE1" "$TEST_DIR/input/same.png"
cp "$TEST_IMAGE2" "$TEST_DIR/input/same.jpg"
ln -s "$PWD/$TEST_IMAGE1" "$TEST_DIR/output/first.icns"

if "$ICONFORGE" forge "$TEST_DIR/input" -r -o "$TEST_DIR/output" -f >"$TEST_DIR/preflight.log" 2>&1; then
  test_fail "Invalid forge manifest unexpectedly succeeded"
  exit 1
fi
for expected in 'Could not decode input image:' '/first.png' '/last.jpg' \
  'Processor diagnostic:' 'Output target is a symlink' 'Two planned outputs map to the same path'; do
  if ! grep -F "$expected" "$TEST_DIR/preflight.log" >/dev/null; then
    test_fail "Preflight omitted independent error: $expected"
    cat "$TEST_DIR/preflight.log"
    exit 1
  fi
done
[[ -L "$TEST_DIR/output/first.icns" && ! -e "$TEST_DIR/output/last.icns" && ! -e "$TEST_DIR/output/same.icns" ]] || {
  test_fail "An invalid manifest changed its output destinations"
  exit 1
}

if ICONFORGE_PROCESSOR="$TEST_DIR/missing-processor" "$ICONFORGE" forge "$TEST_DIR/input" -r \
  -o "$TEST_DIR/output" -f >"$TEST_DIR/missing-processor.log" 2>&1; then
  test_fail "A missing processor unexpectedly succeeded"
  exit 1
fi
for expected in 'iconforge-processor not found' 'Output target is a symlink' 'Two planned outputs map to the same path'; do
  grep -F "$expected" "$TEST_DIR/missing-processor.log" >/dev/null || {
    test_fail "A missing processor suppressed an independent check: $expected"
    exit 1
  }
done

if "$ICONFORGE" forge "$TEST_DIR/missing-one.png" "$TEST_DIR/input/last.jpg" \
  "$TEST_DIR/missing-two.png" -o "$TEST_DIR/missing-output" >"$TEST_DIR/missing.log" 2>&1; then
  test_fail "Missing inputs unexpectedly succeeded"
  exit 1
fi
for expected in 'missing-one.png' 'missing-two.png' 'Could not decode input image:'; do
  grep -F "$expected" "$TEST_DIR/missing.log" >/dev/null || {
    test_fail "Input collection stopped before reporting: $expected"
    exit 1
  }
done
[[ ! -e "$TEST_DIR/missing-output" ]] || { test_fail "Missing inputs allowed publication"; exit 1; }

mkdir -p "$TEST_DIR/staging-input"
for name in first middle last; do
  cp "$TEST_IMAGE1" "$TEST_DIR/staging-input/$name.png"
done
cat >"$TEST_DIR/processor" <<'PROCESSOR'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == resize ]]; then
  case "$2" in
    */first.png|*/last.png)
      printf 'Injected encoder failure: %s\n' "$2" >&2
      exit 1
      ;;
  esac
fi
exec "$ICONFORGE_REAL_PROCESSOR" "$@"
PROCESSOR
chmod +x "$TEST_DIR/processor"
if ICONFORGE_PROCESSOR="$PWD/$TEST_DIR/processor" \
  ICONFORGE_REAL_PROCESSOR="$PWD/iconforge-processor/iconforge-processor" \
  "$ICONFORGE" forge "$TEST_DIR/staging-input" -r -o "$TEST_DIR/staging-output" \
  >"$TEST_DIR/staging.log" 2>&1; then
  test_fail "Failed staging unexpectedly succeeded"
  exit 1
fi
for expected in 'first.png' 'last.png' 'Forging middle' 'No output files were published'; do
  grep -F "$expected" "$TEST_DIR/staging.log" >/dev/null || {
    test_fail "Staging did not finish independent work: $expected"
    cat "$TEST_DIR/staging.log"
    exit 1
  }
done
[[ ! -e "$TEST_DIR/staging-output" ]] || { test_fail "Failed staging published partial outputs"; exit 1; }

(
  source ./lib/iconforge/common.sh
  source ./lib/iconforge/forge.sh
  stage_root="$(mktemp -d "$(iconforge_temp_root)/iconforge-forge.XXXXXX")"
  trap 'rm -rf "$stage_root"' EXIT
  output_root="$PWD/$TEST_DIR/recovery-output"
  mkdir -p "$output_root"
  printf 'original output\n' >"$output_root/first.icns"
  printf 'new output\n' >"$stage_root/first.icns"
  printf 'new output\n' >"$stage_root/last.icns"
  FORGE_INPUTS=(first last)
  FORGE_ICNS_TARGETS=("$output_root/first.icns" "$output_root/last.icns")
  FORGE_STAGE_ICNS=("$stage_root/first.icns" "$stage_root/last.icns")
  FORGE_EXISTING_TARGETS=("$output_root/first.icns")
  forge_atomic_copy() {
    [[ "$1" != "$stage_root/backup-0" ]] || return 1
    cp "$1" "$2"
  }
  forge_atomic_copy_no_clobber() { return 1; }
  if forge_publish_all "$stage_root" "$output_root" false >"$TEST_DIR/recovery.log" 2>&1; then
    test_fail "Injected publication and rollback failures unexpectedly succeeded"
    exit 1
  fi
  forge_cleanup_stage_dir "$stage_root"
  [[ -d "$stage_root" ]] || { test_fail "Failed rollback deleted its recovery files"; exit 1; }
  grep -F 'original output' "$stage_root/backup-0" >/dev/null || {
    test_fail "Failed rollback lost the original output backup"
    exit 1
  }
  grep -F "$output_root/first.icns" "$TEST_DIR/recovery.log" >/dev/null || {
    test_fail "Failed rollback did not identify the affected destination"
    exit 1
  }
  grep -F "$stage_root/backup-0" "$TEST_DIR/recovery.log" >/dev/null || {
    test_fail "Failed rollback did not identify the recovery copy"
    exit 1
  }
)

(
  source ./lib/iconforge/common.sh
  source ./lib/iconforge/forge.sh
  source ./lib/iconforge/strategy-native-icon.sh
  root="$PWD/$TEST_DIR/input"
  find() {
    printf '%s\0' "$root/first.png"
    printf 'Injected source traversal failure\n' >&2
    return 1
  }
  forge_reset_manifest
  if forge_collect_inputs true "$PWD/$TEST_DIR/incomplete-output" "$root" >"$TEST_DIR/incomplete.log" 2>&1; then
    test_fail "An incomplete source traversal unexpectedly succeeded"
    exit 1
  fi
  [[ "${#FORGE_INPUTS[@]}" -eq 1 && "${#FORGE_STEMS[@]}" -eq 1 ]] || {
    test_fail "An incomplete source traversal did not preserve independent inputs for diagnosis"
    exit 1
  }
  grep -F 'Injected source traversal failure' "$TEST_DIR/incomplete.log" >/dev/null || {
    test_fail "Forge scan discarded its underlying traversal error"
    exit 1
  }
)

cat >"$TEST_DIR/confirm-overwrites.sh" <<'CONFIRM'
#!/usr/bin/env bash
set -euo pipefail
source ./lib/iconforge/common.sh
source ./lib/iconforge/diagnostics.sh
source ./lib/iconforge/forge.sh
diagnostics_start forge-overwrite-prompt
FORGE_EXISTING_TARGETS=(example.icns)
# The real PTY establishes terminal state; supply consent without timing input delivery.
read() { response=y; }
forge_confirm_overwrites false false
printf 'Confirmed overwrite from terminal\n'
CONFIRM
/usr/bin/script -q "$TEST_DIR/confirm-overwrites.log" \
  bash "$TEST_DIR/confirm-overwrites.sh" </dev/null >"$TEST_DIR/confirm-overwrites.stdout" 2>"$TEST_DIR/confirm-overwrites.stderr"
for expected in 'Overwrite all listed files?' 'Confirmed overwrite from terminal'; do
  grep -F "$expected" "$TEST_DIR/confirm-overwrites.log" >/dev/null || {
    test_fail "Diagnostic capture broke interactive overwrite confirmation: $expected"
    cat "$TEST_DIR/confirm-overwrites.log"
    exit 1
  }
done

test_pass "$TEST_NAME passed"
