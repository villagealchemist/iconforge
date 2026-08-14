#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="forge contract"
source tests/test-common.sh

test_run "$TEST_NAME"
mkdir -p "$TEST_DIR/input/chat" "$TEST_DIR/input/music" "$TEST_DIR/input/_drafts" \
  "$TEST_DIR/input/.hidden" "$TEST_DIR/input/generated.iconset" "$TEST_DIR/input/out"
cp "$TEST_IMAGE1" "$TEST_DIR/input/chat/Logo ü.png"
cp "$TEST_IMAGE1" "$TEST_DIR/input/music/Logo ü.png"
cp "$TEST_IMAGE1" "$TEST_DIR/input/_drafts/draft.png"
cp "$TEST_IMAGE1" "$TEST_DIR/input/.hidden/skip.png"
cp "$TEST_IMAGE1" "$TEST_DIR/input/chat/.hidden-file.png"
cp "$TEST_IMAGE1" "$TEST_DIR/input/generated.iconset/skip.png"
cp "$TEST_IMAGE1" "$TEST_DIR/input/out/old.png"
ln -s "$PWD/$TEST_IMAGE1" "$TEST_DIR/input/symlink.png"
ln -s output-loop "$TEST_DIR/output-loop"

set +e
"$ICONFORGE" forge >"$TEST_DIR/bare.log" 2>&1
bare_rc=$?
"$ICONFORGE" forge "$TEST_IMAGE1" -q >"$TEST_DIR/removed.log" 2>&1
removed_rc=$?
set -e
[[ "$bare_rc" -eq 2 ]] || { test_fail "Bare forge should exit 2, got $bare_rc"; exit 1; }
[[ "$removed_rc" -eq 2 ]] || { test_fail "Removed option should exit 2, got $removed_rc"; exit 1; }

set +e
ICONFORGE_PROCESSOR="$TEST_DIR/missing-processor" "$ICONFORGE" forge >"$TEST_DIR/bare-missing-processor.log" 2>&1
bare_missing_processor_rc=$?
"$ICONFORGE" forge -o README.md >"$TEST_DIR/output-before-input.log" 2>&1
output_before_input_rc=$?
"$ICONFORGE" forge -o "$TEST_DIR/output-loop" >"$TEST_DIR/loop-output-before-input.log" 2>&1
loop_output_before_input_rc=$?
"$ICONFORGE" forge "$TEST_IMAGE1" no/path -o README.md -d >"$TEST_DIR/custom-name-path.log" 2>&1
custom_name_path_rc=$?
set -e
[[ "$bare_missing_processor_rc" -eq 2 ]] || { test_fail "Bare forge checked its processor before reporting missing input"; exit 1; }
grep -F "forge requires an input image or directory" "$TEST_DIR/bare-missing-processor.log" >/dev/null || {
  test_fail "Bare forge with a missing processor did not report its usage error first"
  exit 1
}
[[ "$output_before_input_rc" -eq 2 ]] || { test_fail "Output-before-input should remain a usage error"; exit 1; }
grep -F "forge requires an input image or directory" "$TEST_DIR/output-before-input.log" >/dev/null || {
  test_fail "Output-before-input did not report the missing input first"
  exit 1
}
[[ "$loop_output_before_input_rc" -eq 2 ]] || {
  test_fail "A malformed output path masked the missing forge input usage error"
  exit 1
}
grep -F "forge requires an input image or directory" "$TEST_DIR/loop-output-before-input.log" >/dev/null || {
  test_fail "Bare forge did not validate its operands before resolving the output path"
  exit 1
}
[[ "$custom_name_path_rc" -eq 2 ]] || { test_fail "A custom output name containing a path separator should exit 2"; exit 1; }
grep -F "Output name must not contain path separators: no/path" "$TEST_DIR/custom-name-path.log" >/dev/null || {
  test_fail "Invalid custom output name was not diagnosed before the output path"
  exit 1
}

mkdir -p "$TEST_DIR/existing-custom-name/out"
touch "$TEST_DIR/existing-custom-name/ExistingName"
(
  cd "$TEST_DIR/existing-custom-name"
  "$PWD/../../../iconforge.sh" forge "$PWD/../../../$TEST_IMAGE1" ExistingName -o out -d
) >"$TEST_DIR/existing-custom-name.log" 2>&1
grep -F "/out/ExistingName.icns" "$TEST_DIR/existing-custom-name.log" >/dev/null || {
  test_fail "An unrelated existing file could not be used as a custom output basename"
  exit 1
}

set +e
"$ICONFORGE" forge "$TEST_IMAGE1" -o -k -d >"$TEST_DIR/missing-output-value.log" 2>&1
missing_output_rc=$?
set -e
[[ "$missing_output_rc" -eq 2 ]] || { test_fail "Flag-like output value should exit 2"; exit 1; }

"$ICONFORGE" forge "$TEST_DIR/input" -r -o "$TEST_DIR/input/out"
assert_file_exists "$TEST_DIR/input/out/chat/Logo ü.icns"
assert_file_exists "$TEST_DIR/input/out/music/Logo ü.icns"
assert_file_exists "$TEST_DIR/input/out/_drafts/draft.icns"
[[ ! -e "$TEST_DIR/input/out/.hidden/skip.icns" ]] || { test_fail "Hidden input was forged"; exit 1; }
[[ ! -e "$TEST_DIR/input/out/chat/.hidden-file.icns" ]] || { test_fail "Hidden file was forged"; exit 1; }
[[ ! -e "$TEST_DIR/input/out/generated.iconset/skip.icns" ]] || { test_fail "Iconset input was forged"; exit 1; }
[[ ! -e "$TEST_DIR/input/out/out/old.icns" ]] || { test_fail "Output subtree was re-ingested"; exit 1; }
[[ ! -e "$TEST_DIR/input/out/symlink.icns" ]] || { test_fail "Symlink input was forged"; exit 1; }

existing="$TEST_DIR/input/out/chat/Logo ü.icns"
before_hash="$(shasum -a 256 "$existing" | awk '{print $1}')"
set +e
"$ICONFORGE" forge "$TEST_DIR/input" -r -o "$TEST_DIR/input/out" >"$TEST_DIR/collision.log" 2>&1
collision_rc=$?
set -e
after_hash="$(shasum -a 256 "$existing" | awk '{print $1}')"
[[ "$collision_rc" -eq 1 ]] || { test_fail "Noninteractive collision should exit 1"; exit 1; }
[[ "$before_hash" == "$after_hash" ]] || { test_fail "Collision changed an existing output"; exit 1; }
grep -q -- '-f/--force' "$TEST_DIR/collision.log" || { test_fail "Collision omitted force guidance"; exit 1; }

"$ICONFORGE" forge "$TEST_DIR/input" -r -o "$TEST_DIR/input/out" -f

mkdir -p "$TEST_DIR/duplicates/a" "$TEST_DIR/duplicates/b"
cp "$TEST_IMAGE1" "$TEST_DIR/duplicates/a/same.png"
cp "$TEST_IMAGE2" "$TEST_DIR/duplicates/b/same.jpg"
set +e
"$ICONFORGE" forge "$TEST_DIR/duplicates/a/same.png" "$TEST_DIR/duplicates/b/same.jpg" \
  -o "$TEST_DIR/duplicate-out" >"$TEST_DIR/duplicate.log" 2>&1
duplicate_rc=$?
set -e
[[ "$duplicate_rc" -eq 1 ]] || { test_fail "Planned duplicate should exit 1"; exit 1; }
[[ ! -e "$TEST_DIR/duplicate-out" ]] || { test_fail "Planned duplicate wrote output"; exit 1; }

composed='é'
decomposed="$(printf 'e\314\201')"
mkdir -p "$TEST_DIR/unicode-collision/a" "$TEST_DIR/unicode-collision/b"
cp "$TEST_IMAGE1" "$TEST_DIR/unicode-collision/a/$composed.png"
cp "$TEST_IMAGE2" "$TEST_DIR/unicode-collision/b/$decomposed.jpg"
set +e
"$ICONFORGE" forge "$TEST_DIR/unicode-collision/a/$composed.png" \
  "$TEST_DIR/unicode-collision/b/$decomposed.jpg" -o "$TEST_DIR/unicode-output" \
  >"$TEST_DIR/unicode-collision.log" 2>&1
unicode_collision_rc=$?
set -e
[[ "$unicode_collision_rc" -eq 1 ]] || { test_fail "Unicode-equivalent outputs should collide"; exit 1; }
[[ ! -e "$TEST_DIR/unicode-output" ]] || { test_fail "Unicode collision wrote output"; exit 1; }

mkdir -p "$TEST_DIR/hardlink-alias/output"
cp "$TEST_IMAGE1" "$TEST_DIR/hardlink-alias/source.png"
ln "$TEST_DIR/hardlink-alias/source.png" "$TEST_DIR/hardlink-alias/output/custom.icns"
hardlink_before="$(shasum -a 256 "$TEST_DIR/hardlink-alias/source.png" | awk '{print $1}')"
set +e
"$ICONFORGE" forge "$TEST_DIR/hardlink-alias/source.png" custom \
  -o "$TEST_DIR/hardlink-alias/output" -f >"$TEST_DIR/hardlink-alias.log" 2>&1
hardlink_rc=$?
set -e
[[ "$hardlink_rc" -eq 1 ]] || { test_fail "Hard-linked output/input alias should fail"; exit 1; }
[[ "$(shasum -a 256 "$TEST_DIR/hardlink-alias/source.png" | awk '{print $1}')" == "$hardlink_before" ]] || {
  test_fail "Hard-linked output/input alias changed the input"
  exit 1
}

mkdir -p "$TEST_DIR/same-root"
cp "$TEST_IMAGE1" "$TEST_DIR/same-root/source.png"
source_before="$(shasum -a 256 "$TEST_DIR/same-root/source.png" | awk '{print $1}')"
"$ICONFORGE" forge "$TEST_DIR/same-root" -r -k -o "$TEST_DIR/same-root"
source_after="$(shasum -a 256 "$TEST_DIR/same-root/source.png" | awk '{print $1}')"
[[ "$source_before" == "$source_after" ]] || { test_fail "Keep-PNG rewrote its selected source"; exit 1; }
assert_file_exists "$TEST_DIR/same-root/source.icns"

mkdir -p "$TEST_DIR/dry"
"$ICONFORGE" forge "$TEST_IMAGE1" -o "$TEST_DIR/dry" -d >"$TEST_DIR/dry.log"
[[ ! -e "$TEST_DIR/dry/i-just-wanna-be-an-icon.icns" ]] || { test_fail "Dry-run wrote output"; exit 1; }
grep -q 'Would forge:' "$TEST_DIR/dry.log" || { test_fail "Dry-run omitted plan"; exit 1; }

"$PWD/iconforge-processor/iconforge-processor" resize "$TEST_IMAGE1" 256 600 "$TEST_DIR/low.png"
"$ICONFORGE" forge "$TEST_DIR/low.png" -d >"$TEST_DIR/low.log" 2>&1
grep -q 'Warning: Source image is 256x600' "$TEST_DIR/low.log" || {
  test_fail "Low-resolution input did not warn and continue"
  exit 1
}
[[ ! -e "$TEST_DIR/low.icns" ]] || { test_fail "Low-resolution dry-run wrote output"; exit 1; }

mkdir -p "$TEST_DIR/rollback/input/a" "$TEST_DIR/rollback/input/b" \
  "$TEST_DIR/rollback/output/a" "$TEST_DIR/rollback/output/b"
cp "$TEST_IMAGE1" "$TEST_DIR/rollback/input/a/one.png"
cp "$TEST_IMAGE2" "$TEST_DIR/rollback/input/b/two.jpg"
printf 'preserve this output\n' >"$TEST_DIR/rollback/output/a/one.icns"
rollback_before="$(shasum -a 256 "$TEST_DIR/rollback/output/a/one.icns" | awk '{print $1}')"
chmod 640 "$TEST_DIR/rollback/output/a/one.icns"
rollback_mode_before="$(stat -f '%Lp' "$TEST_DIR/rollback/output/a/one.icns")"
chmod 500 "$TEST_DIR/rollback/output/b"
set +e
"$ICONFORGE" forge "$TEST_DIR/rollback/input" -r -o "$TEST_DIR/rollback/output" -f \
  >"$TEST_DIR/rollback.log" 2>&1
rollback_rc=$?
set -e
chmod 700 "$TEST_DIR/rollback/output/b"
rollback_after="$(shasum -a 256 "$TEST_DIR/rollback/output/a/one.icns" | awk '{print $1}')"
rollback_mode_after="$(stat -f '%Lp' "$TEST_DIR/rollback/output/a/one.icns")"
[[ "$rollback_rc" -eq 1 ]] || { test_fail "Publication fault should exit 1"; exit 1; }
[[ "$rollback_before" == "$rollback_after" ]] || { test_fail "Publication fault did not restore the first output"; exit 1; }
[[ "$rollback_mode_before" == "$rollback_mode_after" ]] || { test_fail "Publication rollback changed output permissions"; exit 1; }
[[ ! -e "$TEST_DIR/rollback/output/b/two.icns" ]] || { test_fail "Publication fault left a partial output"; exit 1; }
if find "$TEST_DIR/rollback/output" -name '.iconforge-publish.*' -print -quit | grep -q .; then
  test_fail "Publication fault left a temporary publish file"
  exit 1
fi

mkdir -p "$TEST_DIR/mode-output"
(umask 022; "$ICONFORGE" forge "$TEST_IMAGE1" -o "$TEST_DIR/mode-output")
[[ "$(stat -f '%Lp' "$TEST_DIR/mode-output/i-just-wanna-be-an-icon.icns")" == 644 ]] || {
  test_fail "A new output did not receive the staged file's normal mode"
  exit 1
}

mkdir -p "$TEST_DIR/signal/fakebin" "$TEST_DIR/signal/output" "$TEST_DIR/signal/temp"
cat >"$TEST_DIR/signal/fakebin/native-helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
"$ICONFORGE_REAL_HELPER" "$@"
if [[ "$1" == rename-exact && ! -e "$ICONFORGE_TEST_SIGNAL_MARKER" ]]; then
  : >"$ICONFORGE_TEST_SIGNAL_MARKER"
  kill -TERM "$PPID"
fi
EOF
chmod +x "$TEST_DIR/signal/fakebin/native-helper"
printf 'pre-signal output\n' >"$TEST_DIR/signal/output/i-just-wanna-be-an-icon.icns"
signal_before="$(shasum -a 256 "$TEST_DIR/signal/output/i-just-wanna-be-an-icon.icns" | awk '{print $1}')"
set +e
TMPDIR="$PWD/$TEST_DIR/signal/temp" \
  ICONFORGE_REAL_HELPER="$PWD/iconforge-native-icon/iconforge-native-icon" \
  ICONFORGE_NATIVE_ICON="$PWD/$TEST_DIR/signal/fakebin/native-helper" \
  ICONFORGE_TEST_SIGNAL_MARKER="$PWD/$TEST_DIR/signal-fired" \
  "$ICONFORGE" forge "$TEST_IMAGE1" -o "$TEST_DIR/signal/output" -f \
  >"$TEST_DIR/signal.log" 2>&1
signal_rc=$?
set -e
signal_after="$(shasum -a 256 "$TEST_DIR/signal/output/i-just-wanna-be-an-icon.icns" | awk '{print $1}')"
[[ "$signal_rc" -ne 0 ]] || { test_fail "TERM during final publication reported success"; exit 1; }
[[ "$signal_before" == "$signal_after" ]] || { test_fail "TERM during final publication did not roll back"; exit 1; }
if find "$TEST_DIR/signal/temp" -mindepth 1 -print -quit | grep -q .; then
  test_fail "TERM during publication left staging files"
  exit 1
fi

test_pass "$TEST_NAME passed"
