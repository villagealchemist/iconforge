<!--suppress CheckImageSize -->
<p align="center">
  <img src="assets/iconforge-logo.png" alt="Icon Forge logo" width="300"/>
</p>
<p align="center">
  <strong>Turn source artwork into a macOS icon, then put it where it belongs.</strong>
  <br/>
  Made with ♡ by <a href="https://github.com/villagealchemist">@villagealchemist</a> · Bash + Go + AppKit
</p>

<p align="center">⋆｡°✩ ⟡ ♡ ⟡ ✩°｡⋆</p>

Icon Forge is a macOS command-line workflow for custom application icons. The `iconforge` command creates `.icns` files,
inspects application bundles, applies a native Finder custom icon by default, restores
previous state, and refreshes the caches that make macOS notice.

Icon Forge carries its own Go image processor and native AppKit helper; the remaining runtime dependencies are macOS
system tools. It does not require `fileicon`, `ffmpeg`, AppleScript, or `iconutil`.

For every flag, resolution rule, configuration key, status, and recovery path, use
the [complete command reference](docs/USAGE.md). User-visible release history lives in the [changelog](CHANGELOG.md),
with upgrade guidance in the [2.0.1 release notes](docs/releases/v2.0.1.md).

## ✦ In essence

- Forge PNG, JPEG, WebP, TIFF, and GIF sources into native `.icns` files.
- Process one image, a batch of images, or a recursive directory tree.
- Inspect how an app declares its icon before changing anything.
- Apply one icon directly or reconcile a directory-based icon library.
- Use native Finder custom icons by default without changing application contents or signatures; retain backed-up
  internal `.icns` replacement as an explicit expert strategy and a fallback when the bundled helper is unavailable.
- Preview forge, apply, restore, and refresh work with `--dry-run`.

Icon Forge is macOS-only. The `forge` command does not target application bundles; `apply` and `restore` do.
Read [Safety](#safety) before changing an app you care about.

## ♡ Installation

### Build the current source

A source build needs macOS, the Go version accepted by `iconforge-processor/go.mod` (currently Go 1.24.6), and Xcode
Command Line Tools.

```bash
git clone https://github.com/villagealchemist/iconforge.git
cd iconforge
make install
export PATH="$HOME/.local/bin:$PATH"
```

By default, `make install` uses the user-writable prefix `~/.local`. Add its `bin` directory to your shell's `PATH`
permanently if it is not already there.

For a system-wide `/usr/local` installation, build without elevation and run only the installer with `sudo`:

```bash
make build
sudo env PREFIX=/usr/local ./install.sh
```

`make install` builds the Go processor and native helper before installing the runtime. To remove that installation
later, run `make uninstall`. Use the same explicit `PREFIX` when uninstalling a nondefault installation.

### Install a published Homebrew release

```bash
brew install villagealchemist/iconforge/iconforge
```

The separate tap tracks published releases and can lag the current development branch. The 2.x behavior documented here
requires a 2.x build; check what was installed with:

```bash
iconforge --version
```

## ▶▶ Quick start

This representative workflow forges artwork, inspects an app, previews the change, applies it, and restores it later.

Choose source artwork and an installed application:

```bash
artwork="$HOME/Desktop/discord.png"
app="/Applications/Discord.app"
icon_dir="/path/to/icon-library/discord"
```

> Optional safety preflight: before the first apply, copy the app into `~/Applications`, give the copy a distinct name,
> and point `app` at that copy. This keeps an experimental bundle mutation away from the installed app.

Forge the icon:

```bash
iconforge forge "$artwork" discord --output "$icon_dir"
```

Inspect the target without modifying it:

```bash
iconforge inspect "$app"
```

Preview the selected strategy and planned writes:

```bash
iconforge apply "$app" --icon "$icon_dir/discord.icns" --dry-run
```

Apply the icon and refresh macOS icon caches:

```bash
iconforge apply "$app" --icon "$icon_dir/discord.icns" --refresh-caches
```

Restore the internal backup or remove the Finder custom icon:

```bash
iconforge restore "$app" --refresh-caches
```

Application updates, signing policy, permissions, and macOS protection can all affect the result.

## ⏾ Command map

| Command             | Purpose                                                           |
|---------------------|-------------------------------------------------------------------|
| `iconforge forge`   | Convert supported source images into `.icns` files                |
| `iconforge inspect` | Report the icon metadata and loose assets in an app bundle        |
| `iconforge apply`   | Apply one `.icns` or reconcile a managed icon library             |
| `iconforge restore` | Restore an internal backup and/or remove a Finder custom icon     |
| `iconforge refresh` | Refresh user-level icon caches, optionally touching one app first |
| `iconforge nuke`    | Compatibility alias for `refresh`                                 |

The image-first v1 spelling remains available and routes to `forge`:

```bash
iconforge ./logo.png BrandMark --output ./icons
```

Help is available at the root, through the `help` command, and on each command:

```bash
iconforge --help
iconforge help apply
iconforge forge --help
iconforge inspect --help
iconforge apply --help
iconforge restore --help
iconforge refresh --help
```

## ✿ Forge an icon

A basic forge writes one `.icns` to the chosen output directory:

```bash
iconforge forge ./artwork.png BrandMark --output ./dist
```

Keep the normalized PNG as well:

```bash
iconforge forge ./artwork.webp BrandMark --output ./dist --keep-png
```

Or process a directory tree:

```bash
iconforge forge ./artwork --recursive --output ./dist --no-warnings
```

Icon Forge accepts `.png`, `.jpg`, `.jpeg`, `.webp`, `.tiff`, `.tif`, and `.gif`. GIF input uses the first decoded
frame. Every source is scaled to the ten standard and Retina icon representations from 16 through 1024 pixels; prepare square artwork if
preserving its proportions matters.

Sources with either dimension below 512 pixels produce a quality warning and, unless `--no-warnings` is present, a
confirmation prompt. See [`forge`](docs/USAGE.md#forge) for batch naming, output sanitization, interactive mode,
collision behavior, and failure handling.

## ⊹ Application strategies

`iconforge apply` defaults to `auto`:

- When the bundled helper is available, every application selects `native`. AppKit sets a Finder-level custom icon
  without replacing bundle contents or changing the app's signature.
- A protected or otherwise nonwritable bundle still selects `native`; Icon Forge reports that administrator
  authorization is needed before attempting a write and never invokes `sudo` itself.
- When the helper is unavailable, only a writable, unsigned loose-icon bundle may fall back to `internal-icns`.
- `--strategy internal-icns` remains an explicit expert override. It preserves the first `*_ugly.icns` backup before
  replacement and ad hoc re-signing.

`fileicon` remains accepted as a compatibility strategy name, but it resolves to `native` and never invokes a `fileicon`
executable. The exact classification heuristic, overrides, signing controls, and asset-catalog safeguards are
in [Apply strategies](docs/USAGE.md#strategy-selection-and-behavior).

## ❧ Managed icon libraries

A managed library maps top-level directory keys to custom icons:

```text
<icon-root>/
├── discord/
│   └── discord.icns
├── google-chrome/
│   └── google-chrome.icns
└── visual-studio-code/
    └── visual-studio-code.icns
```

Preview the configured library with per-entry statuses:

```bash
iconforge apply --all --dry-run --verbose
```

Reconcile it:

```bash
iconforge apply --all --verbose
```

Each directory name is a managed key. Icon Forge resolves one `.icns`, discovers applications under `~/Applications` and
`/Applications`, matches the key, applies a strategy, and refreshes caches once if anything changed. PNG-only entries
are reported as `needs-forge`; managed mode does not forge them automatically.

Icon Forge deliberately has no built-in icon-library location. Supply the root with `--icon-root`, set
`ICONFORGE_ICON_ROOT`, or configure `icon_root` in `~/.config/iconforge/config.plist`.
See [Managed icon libraries](docs/USAGE.md#managed-icon-libraries) for the directory contract, matching precedence,
exclusions, per-app strategy configuration, statuses, and exit behavior.

## ⟳ Restore and refresh

Restoration depends on how the icon was applied.

```bash
iconforge restore "/Applications/Discord.app"
iconforge refresh "/Applications/Discord.app"
iconforge refresh
```

For internal replacement, `restore` copies the preserved backup over the loose `.icns`, touches the bundle, and re-signs
it. It also removes a current Finder custom icon when one is present, so legacy mixed states are restored at both
layers. Without a selectable internal backup, it asks the native helper to remove the Finder custom icon only.

`refresh` removes user-accessible iconservices and Dock cache files, restarts Finder, Dock, and `iconservicesagent`, and
refreshes Quick Look when available. It cannot reconstruct icon data lost in an application update.

<a id="safety"></a>

## ☾︎ Safety

- `--dry-run` previews supported forge, apply, restore, and refresh work. Use it before bulk reconciliation or a forced
  strategy.
- `internal-icns` changes the signed contents of an app. Its default re-sign is `codesign --force --deep --sign -`. Icon
  Forge verifies the resulting signature across all architectures before reporting success and restores the preserved
  icon if signing or verification fails.
- `native` overwrites any existing Finder custom icon without preserving it. A later `restore` removes that custom icon;
  it cannot recover an older Finder custom icon.
- If no internal backup can be selected, `restore` removes the current Finder custom icon even when Icon Forge did not
  create it.
- App updates may overwrite internal replacements, backups, or Finder custom-icon metadata.
- If v2.0.0 internally modified a vendor application, reinstall that application from its trusted source before
  applying with v2.0.1. Copying the icon backup back cannot recover the original vendor signature.
- Cache refresh restarts user interface services. It does not use privileged system-wide cache deletion.
- System Integrity Protection, ownership, MDM policy, filesystem permissions, or signature enforcement may block
  changes. For a root-owned bundle, use only the scoped native-helper command printed by Icon Forge; never run a
  permanent root shell or change ownership of `/Applications`. Do not weaken macOS security to force a result.

The full operational guidance is in [Safety, updates, and recovery](docs/USAGE.md#safety-updates-and-recovery).

## ⁺˚ Development

Run from a checkout after building both bundled binaries:

```bash
make build
./iconforge.sh --help
./iconforge.sh forge ./artwork.png --output ./icons
```

The principal development targets are:

| Target              | Purpose                                                               |
|---------------------|-----------------------------------------------------------------------|
| `make build`        | Build the Go processor and native AppKit helper                       |
| `make build-all`    | Build release binaries for Intel and Apple silicon macOS              |
| `make test`         | Build, run Go tests, and run the shell integration suite              |
| `make test-verbose` | Run shell tests inline after building                                 |
| `make test-go`      | Run the Go tests only                                                 |
| `make lint`         | Run ShellCheck when installed, then `go vet` and verify Go formatting |
| `make clean`        | Remove generated binaries and test artifacts                          |
| `make version`      | Print the version embedded in the public command                      |

`make lint` checks Go formatting without rewriting source. A release lint is incomplete when ShellCheck is unavailable.

Repository map:

```text
iconforge.sh                 public command dispatcher
lib/iconforge/               Bash parsing, discovery, matching, and strategies
iconforge-processor/         Go decoding, scaling, conversion, and ICNS assembly
iconforge-native-icon/       Objective-C/AppKit Finder custom-icon helper
tests/                       shell integration and regression tests
packaging/homebrew/          versioned Homebrew formula template
docs/USAGE.md                complete user command reference
RELEASING.md                 maintainer release procedure
```

## ✎ Documentation

- [Complete command reference](docs/USAGE.md)
- [Release procedure](RELEASING.md)
- `iconforge help <command>` for installed help

## ♡ License

Icon Forge is released under the [MIT License](LICENSE). Copyright
© [villagealchemist](https://github.com/villagealchemist).

<p align="center">✦ ˚｡⋆ Good artwork deserves a proper icon. Heat the forge. ⋆｡˚ ✦</p>
