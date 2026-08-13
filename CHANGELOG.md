# Changelog

All notable user-facing changes to Icon Forge are recorded here.

## 2.0.1

### Fixed

- Automatic application icon changes now prefer the bundled native Finder custom-icon route for every app, avoiding
  internal bundle mutation, ad hoc re-signing, and macOS-added presentation plates seen with apps such as VS Code.
- Mixed-state restore now restores a selectable internal backup and removes a current Finder custom icon in one run.
- Forged ICNS files now contain all ten standard and Retina representations and round-trip through `iconutil` as a
  complete iconset.

### Compatibility and recovery

- Explicit `internal-icns` remains available as an expert option. With no native helper, automatic selection may use it
  only for a writable unsigned loose-icon bundle; asset-catalog and vendor-signed apps fail safely.
- `fileicon` remains a native compatibility alias and never requires a third-party executable.
- Native apply warns when a legacy internal backup remains. If v2.0.0 internally modified a vendor app, reinstall that
  app from its trusted source to recover the original signature before applying again.
- App updates can still remove Finder custom-icon data. Icon Forge can reapply or remove it but cannot make an updater
  preserve it.

### Development

- Active shell and Go test output now uses always-colored text status glyphs and readable labels: `✓ [PASS]`,
  `✗ [FAIL]`, `▸ [RUN]`, `○ [SKIP]`, and `ⓘ [INFO]`. ANSI colors intentionally remain in redirected logs and CI.

## 2.0.0

Icon Forge 2 is a macOS icon workflow rather than only an image converter.

### Added

- `forge`, `inspect`, `apply`, `restore`, and `refresh` command families with complete command-specific help.
- A bundled Objective-C/AppKit helper for setting, testing, and removing Finder custom icons.
- Managed icon libraries with app discovery, aliases, bundle-ID matching, exclusions, dry runs, verbose statuses, and a
  single cache refresh after reconciliation.
- Native decoding and resizing for PNG, JPEG, WebP, TIFF, and GIF sources through the bundled Go processor.
- User-local source installation under `~/.local` by default and a generated Homebrew formula for published releases.

### Changed

- `auto` uses Finder custom icons for asset catalogs, vendor-signed apps, existing Finder-level customizations, and
  nonwritable app bundles.
- Writable loose-icon bundles without a vendor Team ID retain the internal `.icns` backup, replacement, touch, and ad
  hoc re-sign workflow.
- Internal signing is strictly verified across every architecture before apply reports success.
- A failed internal touch, sign, or verification step restores the preserved icon backup and attempts to verify the
  rolled-back bundle before returning failure.
- Protected bundles are reported as `needs-authorization` before mutation; Icon Forge never invokes `sudo` itself.
- The v1 image-first command remains supported and routes to `forge`.
- `fileicon` remains accepted only as a compatibility strategy name and resolves to the bundled native helper. No
  `fileicon` executable or other third-party runtime tool is required.

### Recovery and update caveats

- Application updates can replace internal icons, delete internal backups, or remove Finder custom-icon metadata.
- `refresh` rebuilds caches from the icon data that still exists; it cannot restore icon data removed by an updater.
- `restore` uses a selectable `*_ugly.icns` backup when available and otherwise removes the current Finder custom icon.
