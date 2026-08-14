# Releasing IconForge

An IconForge release coordinates two repositories:

- `villagealchemist/iconforge` owns source, version, tests, documentation, the annotated tag, and the formula template.
- `villagealchemist/homebrew-iconforge` owns the published tap formula.

The release artifact is source. GitHub hosts one source-only release, and Homebrew builds both IconForge-owned helpers
from an exact source commit. Do not publish prebuilt compiled binaries, bottles, disk images, or installer packages.

## Release invariants

- `VERSION` contains `MAJOR.MINOR.PATCH` without a leading `v`.
- The release tag is `v<version>` and points to the reviewed release commit.
- The formula uses the full 40-character source commit archive URL, an explicit public version, and the archive's actual
  SHA-256.
- Go commands run with `-mod=vendor`; the vendored tree and third-party notices are complete.
- README, complete usage documentation, built-in help, changelog, release notes, and formula tests agree.
- Source and Homebrew installations report the same version and produce an ICNS with all ten expected representations.
- Tests involving app mutation use a synthetic bundle or a disposable copy, never a live application.

## Local release gate

Start from the exact candidate tree with the user's unrelated files preserved. Record the current source and tap remote
refs before any history operation, and create unpushed rescue refs for every ref that will change.

Run:

```bash
make clean
make test
make lint
make version
make build-all
bash tests/test-homebrew-formula.sh
git diff --check
git status --short
```

`make lint` reports ShellCheck as skipped when it is unavailable; that is not a complete release gate. `make build-all`
uses a temporary directory and removes its Intel and Apple-silicon outputs.

Confirm the public surface directly:

```bash
./iconforge.sh --version
./iconforge.sh --help
./iconforge.sh forge --help
./iconforge.sh inspect --help
./iconforge.sh apply --help
./iconforge.sh restore --help
./iconforge.sh nuke --help
```

Exercise source installation in an isolated prefix:

```bash
release_prefix="$(mktemp -d "${TMPDIR:-/tmp}/iconforge-install.XXXXXX")"
PREFIX="$release_prefix" make install
"$release_prefix/bin/iconforge" --version
"$release_prefix/bin/iconforge" forge ./assets/iconforge-logo.png --output "$release_prefix/output"
test -f "$release_prefix/output/iconforge-logo.icns"
PREFIX="$release_prefix" ./uninstall.sh
```

Do not use the repository's original untracked artwork as a deletion or cleanup target.

## ICNS acceptance

Forge a release smoke icon, unpack it, and require every representation:

```bash
smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/iconforge-icns.XXXXXX")"
./iconforge.sh forge ./assets/iconforge-logo.png --output "$smoke_dir"
iconutil -c iconset -o "$smoke_dir/iconforge-logo.iconset" "$smoke_dir/iconforge-logo.icns"
for name in \
  icon_16x16.png icon_16x16@2x.png \
  icon_32x32.png icon_32x32@2x.png \
  icon_128x128.png icon_128x128@2x.png \
  icon_256x256.png icon_256x256@2x.png \
  icon_512x512.png icon_512x512@2x.png; do
  test -f "$smoke_dir/iconforge-logo.iconset/$name"
done
```

## Application acceptance

Create a synthetic test bundle or copy a test application into `~/Applications` under a clearly disposable name.

1. Record its bundle identity, signature identity, and content checksum.
2. Test `inspect` and native apply dry-run.
3. Apply a test ICNS natively and require the native helper's read-only test to pass.
4. Confirm the app's `Contents/`, bundle identity, and signature identity did not change.
5. Restore and require the helper's test to report that no Finder custom icon remains.
6. Test internal apply, rollback, and restore only on a synthetic or disposable loose-icon bundle.
7. Never use a live browser or another application the workstation depends on.

## CI gate

The release commit must pass the full workflow on both pinned runners:

- `macos-15` for Apple silicon.
- `macos-15-intel` for Intel.

Require lint, tests, cross-compilation, formula-contract validation, and the final clean-tree check on both jobs. The
runner matrix does not establish a minimum supported macOS version.

## Source commit and archive

After the reviewed source commit and annotated tag exist publicly, resolve and verify them:

```bash
version="$(tr -d '[:space:]' < VERSION)"
test "$(git cat-file -t "v$version")" = tag
source_commit="$(git rev-parse "v$version^{commit}")"
test "$source_commit" = "$(git rev-parse HEAD)"
git tag -v "v$version" 2>/dev/null || git show "v$version" --no-patch
```

Download the exact commit archive—not the tag archive—and calculate its checksum:

```bash
archive="iconforge-$source_commit.tar.gz"
curl -fL --retry 3 \
  -o "$archive" \
  "https://github.com/villagealchemist/iconforge/archive/$source_commit.tar.gz"
source_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
```

Render and inspect the candidate formula:

```bash
formula_path="${TMPDIR:-/tmp}/iconforge.rb"
./scripts/render-homebrew-formula.sh \
  "$version" \
  "$source_commit" \
  "$source_sha256" > "$formula_path"
ruby -c "$formula_path"
```

The renderer rejects abbreviated commits and malformed checksums.

## Homebrew gate

Copy the rendered formula to `Formula/iconforge.rb` in the tap's reviewed candidate tree. The tap release commit must be
one intentional formula commit atop its selected pre-release base.

Review that the formula:

- Pins the exact source commit and explicit public version.
- Builds the Go processor in vendor mode.
- Builds the Objective-C/AppKit helper with AppKit and Foundation.
- Installs the Bash libraries, entry point, version, notices, processor, and helper under the expected runtime layout.
- Runs public version and forge operations.
- Unpacks the forged ICNS and requires all ten representation filenames.

Validate through Homebrew:

```bash
ruby -c Formula/iconforge.rb
brew style Formula/iconforge.rb
brew audit --strict villagealchemist/iconforge/iconforge
brew reinstall --build-from-source villagealchemist/iconforge/iconforge
brew test villagealchemist/iconforge/iconforge
iconforge --version
```

Then perform a clean-cache tap test from the candidate tap and compare installed help and behavior with the source
installation. A version-only check is insufficient because it does not load the processor or native helper.

## 2.0.0 history gate

The corrected public 2.0.0 source history has one commit directly above `v1.0.0`:

```bash
test "$(git rev-list --count v1.0.0..v2.0.0)" -eq 1
test "$(git rev-parse v2.0.0^{commit})" = "$(git rev-parse main)"
test "$(git rev-parse v2.0.0^{commit}^)" = "$(git rev-parse v1.0.0^{commit})"
```

Publish source before changing the tap. Keep the private rescue refs and the previously working public state available
until the new source archive, CI, isolated source install, formula, and clean Homebrew install all pass.

After every gate succeeds:

1. Make `main` and annotated `v2.0.0` identify the same corrected source commit.
2. Verify the public commit archive and checksum.
3. Publish the tested tap formula pinned to that commit.
4. Create one source-only `v2.0.0` GitHub release and mark it latest.
5. Audit public branches, tags, release objects, tap history, formula contents, installed help, and fresh-install behavior.
6. Retain rescue refs until that final audit is complete.

If any public verification fails, stop and restore the recorded refs and release metadata rather than improvising a
partially published state.
