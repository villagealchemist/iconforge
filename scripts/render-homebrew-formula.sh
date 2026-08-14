#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <version> <source-commit> <source-tarball-sha256>" >&2
  exit 1
fi

version="$1"
source_commit="$2"
sha256="$3"
template="$(cd "$(dirname "$0")/.." && pwd)/packaging/homebrew/iconforge.rb.tmpl"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must use MAJOR.MINOR.PATCH form" >&2
  exit 1
fi

if [[ ! "$source_commit" =~ ^[a-fA-F0-9]{40}$ ]]; then
  echo "Error: source-commit must be a full 40-character hexadecimal Git commit" >&2
  exit 1
fi

if [[ ! "$sha256" =~ ^[a-fA-F0-9]{64}$ ]]; then
  echo "Error: source-tarball-sha256 must be a 64-character hexadecimal SHA-256" >&2
  exit 1
fi

sed \
  -e "s/__VERSION__/$version/g" \
  -e "s/__SOURCE_COMMIT__/$source_commit/g" \
  -e "s/__SHA256__/$sha256/g" \
  "$template"
