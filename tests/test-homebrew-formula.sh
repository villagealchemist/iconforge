#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="Homebrew formula runtime layout"
source tests/test-common.sh

FORMULA="$TEST_DIR/iconforge.rb"
VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
FAKE_SHA="$(printf '0%.0s' {1..64})"

mkdir -p "$TEST_DIR"
./scripts/render-homebrew-formula.sh "$VERSION_VALUE" "$FAKE_SHA" >"$FORMULA"
ruby -c "$FORMULA" >/dev/null

grep -Fq '(libexec/"iconforge-processor").install "iconforge-processor/iconforge-processor"' "$FORMULA" || {
  echo "❌ Formula does not preserve the nested processor runtime layout"
  exit 1
}

if grep -Fq 'libexec.install "iconforge-processor/iconforge-processor" => "iconforge-processor"' "$FORMULA"; then
  echo "❌ Formula still flattens the processor runtime layout"
  exit 1
fi

grep -Fq 'system bin/"iconforge", "forge"' "$FORMULA" || {
  echo "❌ Formula test does not exercise forge through the public launcher"
  exit 1
}

grep -Fq 'assert_path_exists icns' "$FORMULA" || {
  echo "❌ Formula test does not assert the forged ICNS output"
  exit 1
}

grep -Fq 'system "iconutil", "-c", "iconset"' "$FORMULA" || {
  echo "❌ Formula test does not unpack the forged ICNS"
  exit 1
}

grep -Fq 'icon_512x512.png icon_512x512@2x.png' "$FORMULA" || {
  echo "❌ Formula test does not require the complete iconset representation list"
  exit 1
}

echo "🎉 $TEST_NAME passed"
