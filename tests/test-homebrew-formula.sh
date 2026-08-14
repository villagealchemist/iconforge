#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="Homebrew formula runtime layout"
source tests/test-common.sh

FORMULA="$TEST_DIR/iconforge.rb"
VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
FAKE_SHA="$(printf '0%.0s' {1..64})"
FAKE_COMMIT="$(printf '1%.0s' {1..40})"

mkdir -p "$TEST_DIR"
./scripts/render-homebrew-formula.sh "$VERSION_VALUE" "$FAKE_COMMIT" "$FAKE_SHA" >"$FORMULA"
ruby -c "$FORMULA" >/dev/null

if grep -Eq '__[A-Z0-9_]+__' "$FORMULA"; then
  test_fail "Rendered formula still contains an unresolved placeholder"
  exit 1
fi

if ./scripts/render-homebrew-formula.sh "$VERSION_VALUE" "${FAKE_COMMIT:0:12}" "$FAKE_SHA" >/dev/null 2>&1; then
  test_fail "Formula renderer accepted an abbreviated source commit"
  exit 1
fi

if ./scripts/render-homebrew-formula.sh "$VERSION_VALUE" "$FAKE_COMMIT" "${FAKE_SHA:0:32}" >/dev/null 2>&1; then
  test_fail "Formula renderer accepted an abbreviated source checksum"
  exit 1
fi

grep -Fq "archive/$FAKE_COMMIT.tar.gz" "$FORMULA" || {
  test_fail "Formula does not pin the immutable source commit archive"
  exit 1
}

grep -Fq "version \"$VERSION_VALUE\"" "$FORMULA" || {
  test_fail "Formula does not declare the public release version explicitly"
  exit 1
}

grep -Fq 'system "go", "build", "-mod=vendor"' "$FORMULA" || {
  test_fail "Formula does not force the vendored Go dependency graph"
  exit 1
}

grep -Fq 'iconforge-native-icon/main.m' "$FORMULA" || {
  test_fail "Formula does not build the native AppKit helper from source"
  exit 1
}

grep -Fq 'libexec.install "THIRD_PARTY_NOTICES.md"' "$FORMULA" || {
  test_fail "Formula does not install the third-party notices"
  exit 1
}

grep -Fq 'libexec.install "LICENSE"' "$FORMULA" || {
  test_fail "Formula does not install the project license"
  exit 1
}

grep -Fq '(libexec/"iconforge-processor").install "iconforge-processor/iconforge-processor"' "$FORMULA" || {
  test_fail "Formula does not preserve the nested processor runtime layout"
  exit 1
}

grep -Fq 'bin.write_exec_script libexec/"iconforge"' "$FORMULA" || {
  test_fail "Formula does not create the public launcher from the installed runtime"
  exit 1
}

if grep -Fq 'libexec.install "iconforge-processor/iconforge-processor" => "iconforge-processor"' "$FORMULA"; then
  test_fail "Formula still flattens the processor runtime layout"
  exit 1
fi

grep -Fq 'system bin/"iconforge", "forge"' "$FORMULA" || {
  test_fail "Formula test does not exercise forge through the public launcher"
  exit 1
}

grep -Fq 'assert_path_exists icns' "$FORMULA" || {
  test_fail "Formula test does not assert the forged ICNS output"
  exit 1
}

grep -Fq 'system native_helper, "validate", icns' "$FORMULA" || {
  test_fail "Formula test does not validate the ICNS with the native helper"
  exit 1
}

grep -Fq 'system "iconutil", "-c", "iconset"' "$FORMULA" || {
  test_fail "Formula test does not unpack the forged ICNS"
  exit 1
}

for representation in \
  icon_16x16.png icon_16x16@2x.png \
  icon_32x32.png icon_32x32@2x.png \
  icon_128x128.png icon_128x128@2x.png \
  icon_256x256.png icon_256x256@2x.png \
  icon_512x512.png icon_512x512@2x.png; do
  grep -Fq "$representation" "$FORMULA" || {
    test_fail "Formula test does not require iconset representation: $representation"
    exit 1
  }
done

if grep -Fq -- '--no-warnings' "$FORMULA"; then
  test_fail "Formula test uses a removed warning-suppression option"
  exit 1
fi

test_pass "$TEST_NAME passed"
