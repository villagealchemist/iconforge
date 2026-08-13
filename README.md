<div align="center">
<img src="assets/iconforge-logo.png" alt="iconforge" width="269">

<h3>
  Made with ᥫ᭡ by <a href="https://github.com/villagealchemist">@villagealchemist</a> 
</h3>

<p>
  <a href="https://github.com/villagealchemist/iconforge/actions/workflows/ci.yml"><img src="https://github.com/villagealchemist/iconforge/actions/workflows/ci.yml/badge.svg" alt="CI status"></a> ⋆˙⟡ 
  <a href="https://github.com/villagealchemist/iconforge/releases/latest"><img src="https://img.shields.io/github/v/release/villagealchemist/iconforge?label=release" alt="latest release"></a> ⟡︎˙⋆
  <a href="LICENSE"><img src="https://img.shields.io/github/license/villagealchemist/iconforge" alt="MIT license"></a>
</p>
<p><sub>macOS only · Bash + Go + AppKit</sub><br>༝༚༝༚</p>
</div>

macOS icons are more than image files. The artwork, application bundle, signature, Finder metadata, and caches all have
to agree. **iconforge handles the whole ritual.**

Forge PNG, JPEG, WebP, TIFF, and GIF artwork into real `.icns` files. Inspect how an app carries its icon, choose the
safest route in, and apply it to one application or reconcile an entire icon library.

Preview the work with a dry run. Let the sparks fly when the plan looks right.

> **No runtime dependency on `fileicon`, `ffmpeg`, AppleScript, or `iconutil`.**

---

## ✦ What it does

- Forge one image, a batch, or a recursive directory tree.
- Inspect an app’s icon metadata without changing it.
- Apply an icon using the safest available strategy.
- Manage a directory-based library of custom app icons.
- Restore supported changes and refresh macOS icon caches.
- Preview forge, apply, restore, and refresh work with `--dry-run`.

The original image-first syntax remains available:

```bash
iconforge ./logo.png BrandMark --output ./icons
```

For every option, matching rule, configuration key, status, and recovery path, visit
the [complete command reference](docs/USAGE.md).

## ♡ Install

### Homebrew

```bash
brew install villagealchemist/iconforge/iconforge
```

Confirm the installation:

```bash
iconforge --version
```

### Current source

```bash
git clone https://github.com/villagealchemist/iconforge.git
cd iconforge
make install
export PATH="$HOME/.local/bin:$PATH"
```

Source builds require macOS, Go, and Xcode Command Line Tools. Installation details, alternate prefixes, runtime layout,
and removal are covered in the [installation reference](docs/USAGE.md#installation-and-runtime-layout).

## ▶ Quick start

Choose some artwork and an application:

```bash
artwork="$HOME/Desktop/discord.png"
app="/Applications/Discord.app"
icon_dir="$HOME/Desktop/discord-icon"
```

Forge the icon:

```bash
iconforge forge "$artwork" discord --output "$icon_dir"
```

Inspect the app:

```bash
iconforge inspect "$app"
```

Preview the change:

```bash
iconforge apply "$app" \
  --icon "$icon_dir/discord.icns" \
  --dry-run
```

Apply it and refresh macOS icon caches:

```bash
iconforge apply "$app" \
  --icon "$icon_dir/discord.icns" \
  --refresh-caches
```

Restore it later:

```bash
iconforge restore "$app" --refresh-caches
```

If you are testing an unfamiliar or forced strategy, start with a disposable copy of the app under `~/Applications`.

## ⏾ Command map

| Command             | Purpose                                                   |
|---------------------|-----------------------------------------------------------|
| `iconforge forge`   | Turn supported artwork into `.icns` files                 |
| `iconforge inspect` | Explain how an application provides its icon              |
| `iconforge apply`   | Apply one icon or reconcile a managed icon library        |
| `iconforge restore` | Restore an internal backup or remove a Finder custom icon |
| `iconforge refresh` | Refresh user-level macOS icon caches                      |
| `iconforge nuke`    | Compatibility alias for `refresh`                         |

Help is built in:

```bash
iconforge --help
iconforge help apply
iconforge forge --help
```

## ⊹ Application strategies

By default, `iconforge apply` chooses a strategy automatically. When the bundled native helper is available, every app
uses the native route.

### Native

The native route sets a Finder custom icon through the bundled AppKit helper. AppKit stores Finder metadata and an
`Icon\r` payload at the `.app` root, while leaving `Contents/` and the application’s code signature unchanged.

### Internal `.icns`

For writable apps with a traditional loose `.icns`, iconforge can preserve the original as `*_ugly.icns`, install the
replacement, and ad hoc re-sign the bundle.

This route is never selected automatically while the bundled helper is available. Use the explicit `internal-icns`
strategy only when you understand the signing and updater consequences.

The compatibility strategy name `fileicon` still resolves to the native helper. No external `fileicon` executable is
used.

Read [Strategy selection and behavior](docs/USAGE.md#strategy-selection-and-behavior) before overriding the automatic
choice.

## ❖ Managed icon libraries

A managed library uses one top-level directory per application:

```text
<icon-root>/
├── discord/
│   └── discord.icns
├── spotify/
│   └── spotify.icns
└── visual-studio-code/
    └── visual-studio-code.icns
```

Preview the library:

```bash
iconforge apply \
  --all \
  --icon-root /path/to/icon-library \
  --dry-run \
  --verbose
```

Reconcile it:

```bash
iconforge apply \
  --all \
  --icon-root /path/to/icon-library \
  --verbose
```

iconforge discovers installed applications, matches each directory key, selects a strategy, reports the result, and
refreshes caches once after completed changes.

Directory rules, aliases, bundle-ID matching, exclusions, configuration, statuses, and icon-root precedence live
in [Managed icon libraries](docs/USAGE.md#managed-icon-libraries).

## ☾ Before changing an app

- Start with `inspect` and `--dry-run`.
- Native apply overwrites any existing Finder custom icon without preserving it.
- Internal replacement modifies signed application contents.
- Application updates can remove custom icons and internal backups.
- `restore` may remove the current Finder custom icon when no internal backup can be selected.
- Protected apps may require one narrowly scoped native-helper operation with administrator authorization.
- Do not disable macOS security, change ownership under `/Applications`, or run an entire reconciliation as root.

The complete safety and recovery guide is in [Safety, updates, and recovery](docs/USAGE.md#safety-updates-and-recovery).

## ⁺˚ Development

```bash
make build
make test
make test-verbose
make lint
```

Test output uses always-colored, text-rendering status glyphs: green `✓ [PASS]`, red `✗ [FAIL]`, cyan `▸ [RUN]`, yellow
`○ [SKIP]`, and bright-magenta `ⓘ [INFO]`. The labels and ANSI colors remain present in redirected logs and CI output.

The repository is divided into a Bash command layer, a Go image processor, and a native Objective-C/AppKit helper:

```text
iconforge.sh                 public command dispatcher
lib/iconforge/               parsing, discovery, matching, and strategies
iconforge-processor/         decoding, scaling, and ICNS assembly
iconforge-native-icon/       Finder custom-icon helper
tests/                       integration and regression tests
docs/USAGE.md                complete command reference
```

See [RELEASING.md](RELEASING.md) for release builds and Homebrew publication.

## ✎ Documentation

- [Complete command reference](docs/USAGE.md)
- [Changelog](CHANGELOG.md)
- [Release procedure](RELEASING.md)
- [Homebrew tap](https://github.com/villagealchemist/homebrew-iconforge)

## ♡ License

iconforge is released under the [MIT License](LICENSE).

Copyright © [villagealchemist](https://github.com/villagealchemist).

<p style="text-align: center;">✦ ˚｡⋆ Good artwork deserves a proper icon, and the forge is LIT. ⋆｡˚ ✦</p>
