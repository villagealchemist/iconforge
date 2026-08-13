# Changelog

All notable user-facing changes to Icon Forge are recorded here.

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
