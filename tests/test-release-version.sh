#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="release version consistency"
source tests/test-common.sh

version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { test_fail "VERSION is not MAJOR.MINOR.PATCH"; exit 1; }
[[ -f "docs/releases/v$version.md" ]] || { test_fail "Missing release notes for $version"; exit 1; }
grep -Fx "# IconForge $version" "docs/releases/v$version.md" >/dev/null || { test_fail "Release notes have the wrong version"; exit 1; }
grep -Fx "## $version" CHANGELOG.md >/dev/null || { test_fail "Changelog does not contain $version"; exit 1; }
grep -F "**IconForge $version**" README.md >/dev/null || { test_fail "README has the wrong current version"; exit 1; }
grep -F "IconForge $version" docs/CLI.md >/dev/null || { test_fail "CLI guide has the wrong current version"; exit 1; }
grep -F "IconForge $version" docs/USAGE.md >/dev/null || { test_fail "Usage entry point has the wrong current version"; exit 1; }

test_pass "$TEST_NAME passed"
