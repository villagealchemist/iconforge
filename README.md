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

macOS icons are more than image files. The artwork, application bundle, signature, Finder metadata, and user caches all
have to agree. **iconforge handles the whole ritual.**

Forge PNG, JPEG, WebP, TIFF, and GIF artwork into complete `.icns` files. Inspect how an app carries its icon, apply a
Finder custom icon without rewriting the app, or make an explicit expert-level internal replacement when you truly
need one.

IconForge is deliberately stateless: each command names its input, output, application, or icon directory. It never
loads shell configuration or remembers a default directory.

## ✦ What it does

- Forge one image, several images, or an explicitly requested recursive tree.
- Preserve relative paths, spaces, and Unicode names during recursive work.
- Inspect an app without changing it.
- Apply one `.icns` file or match a directory of `.icns` files to installed apps.
- Restore supported changes and reset current-user icon caches on request.
- Preview forge, apply, restore, and Nuke operations with `-d/--dry-run`.

The original image-first syntax remains first-class:

```bash
iconforge ./logo.png
```

For every option, matching rule, status, and recovery path, visit the
[complete command reference](docs/USAGE.md).

## ♡ Install

### Homebrew

```bash
brew install villagealchemist/iconforge/iconforge
iconforge --version
```

The formula builds IconForge's Go processor and Objective-C/AppKit helper from source.

### Source

```bash
git clone https://github.com/villagealchemist/iconforge.git
cd iconforge
make install
export PATH="$HOME/.local/bin:$PATH"
```

Source builds require macOS, Go, and Xcode Command Line Tools. Go image packages required by the processor are vendored
in the repository, so a release build does not download them. Alternate prefixes, runtime layout, and removal are
covered in the [installation reference](docs/USAGE.md#installation-and-runtime-layout).

## ▶ Quick start

Forge artwork into the current directory:

```bash
iconforge forge "$HOME/Desktop/discord.png"
```

Or choose a destination and keep the normalized PNG:

```bash
iconforge forge "$HOME/Desktop/discord.png" \
  --output "$HOME/Desktop/discord-icon" \
  --keep-png
```

Inspect an application:

```bash
iconforge inspect "/Applications/Discord.app"
```

Preview and then apply the icon:

```bash
iconforge apply "/Applications/Discord.app" \
  --icon "$HOME/Desktop/discord-icon/discord.icns" \
  --dry-run

iconforge apply "/Applications/Discord.app" \
  --icon "$HOME/Desktop/discord-icon/discord.icns" \
  --nuke
```

Restore the supported IconForge change later:

```bash
iconforge restore "/Applications/Discord.app" --nuke
```

Use a disposable copied application for any first test of internal bundle mutation.

## ⏾ Command map

| Command             | Purpose                                                        |
|---------------------|----------------------------------------------------------------|
| `iconforge forge`   | Turn supported artwork into `.icns` files                      |
| `iconforge inspect` | Explain how an application provides its icon                   |
| `iconforge apply`   | Apply one icon or match an explicit icon directory             |
| `iconforge restore` | Remove a Finder custom icon and restore one internal backup     |
| `iconforge nuke`    | Reset current-user icon caches, optionally after touching an app |
| `iconforge help`    | Show the root overview or help for one command                  |

Root `-v/--version` prints the version. Inside `apply`, `-v/--verbose` expands status output. The position is
intentional.

Help is built in:

```bash
iconforge --help
iconforge help apply
iconforge forge --help
iconforge apply --help
```

Every command supports `--` as the end-of-options marker. Short options are never clustered, and values use a separate
argument rather than `--option=value`.

## ⊹ Application strategies

### Native — the default

Direct and bulk apply use IconForge's bundled AppKit helper. It asks macOS to set a Finder custom icon at the `.app`
root while leaving `Contents/` and the application's code signature untouched. If that helper is absent, the
installation is broken and IconForge fails closed.

### Internal `.icns` — explicit expert mode

For a writable app with one traditional loose `.icns` file, direct apply can preserve the original, install a
replacement, touch the bundle, and ad hoc re-sign it:

```bash
iconforge apply "/path/to/Disposable.app" \
  --icon ./replacement.icns \
  --strategy internal-icns
```

This strategy is never automatic and is never available in bulk mode. It rejects asset-catalog apps and rolls back if
copying, signing, or strict signature verification fails. Read
[Strategy behavior](docs/USAGE.md#direct-apply) before using it.

## ❖ Apply an icon directory

Bulk mode is an explicit one-run operation. Point it at a directory containing `.icns` files anywhere below it:

```text
icons/
├── Discord.icns
├── Music/
│   └── Spotify.icns
└── Work/
    └── Visual Studio Code.icns
```

Preview exact matches:

```bash
iconforge apply --all ./icons --dry-run --verbose
```

Apply them and run Nuke once afterward:

```bash
iconforge apply --all ./icons --nuke --verbose
```

The filename stem is the app key. Exact normalized matches are automatic. One unique partial match can be confirmed for
that run; it is never saved. Unmatched or ambiguous entries are skipped and summarized. Duplicate keys, malformed
icons, and two icons targeting one app fail preflight before anything is changed.

## ☾ Before changing an app

- Start with `inspect` and `--dry-run`.
- Native apply replaces any existing Finder custom icon; it does not preserve that prior customization.
- Internal replacement modifies signed application contents and substitutes an ad hoc signature.
- Application updates can remove Finder custom icons or internal backups.
- Protected apps may need one narrowly scoped helper operation with administrator authorization.
- Never run the whole CLI as root. Nuke explicitly refuses to do so.
- Test bundle mutation on a disposable copy, never a live application you depend on.

The complete safety and recovery guide is in [Safety and recovery](docs/USAGE.md#safety-and-recovery).

## ⁺˚ Development

```bash
make build
make test
make test-verbose
make lint
make build-all
```

`make build-all` is a cross-compilation check. It creates temporary Intel and Apple-silicon artifacts and removes them;
the repository does not ship prebuilt compiled binaries.

The source tree is divided into a Bash command layer, a Go image processor, and an Objective-C/AppKit helper:

```text
iconforge.sh                 public command dispatcher
lib/iconforge/               parsing, discovery, matching, and strategies
iconforge-processor/         decoding, scaling, and ICNS assembly
iconforge-native-icon/       Finder custom-icon helper
tests/                       integration and regression tests
docs/USAGE.md                complete command reference
```

See [RELEASING.md](RELEASING.md) for the verification and source/Homebrew publication sequence.

## ✎ Documentation

- [Complete command reference](docs/USAGE.md)
- [Changelog](CHANGELOG.md)
- [2.0.0 release notes](docs/releases/v2.0.0.md)
- [Release procedure](RELEASING.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Homebrew tap](https://github.com/villagealchemist/homebrew-iconforge)

## ♡ License

IconForge is released under the [MIT License](LICENSE).

Copyright © [villagealchemist](https://github.com/villagealchemist).

<p style="text-align: center;">✦ ˚｡⋆ Good artwork deserves a proper icon, and the forge is LIT. ⋆｡˚ ✦</p>
