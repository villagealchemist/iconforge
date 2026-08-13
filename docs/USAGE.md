# Icon Forge command reference

This is the complete user-facing reference for Icon Forge 2.x. It follows the current Bash dispatcher, Go processor,
AppKit helper, tests, installer, and package layout.

For installation plus one guided workflow, start with the [README](../README.md).

## Contents

- [Command model](#command-model)
- [Global options, help, and version](#global-options-help-and-version)
- [`forge`](#forge)
- [`inspect`](#inspect)
- [`apply`](#apply)
- [Managed icon libraries](#managed-icon-libraries)
- [`restore`](#restore)
- [`refresh` and `nuke`](#refresh-and-nuke)
- [Application resolution and icon inspection](#application-resolution-and-icon-inspection)
- [Configuration plist](#configuration-plist)
- [Environment and shell configuration](#environment-and-shell-configuration)
- [Installation and runtime layout](#installation-and-runtime-layout)
- [Compatibility reference](#compatibility-reference)
- [Exit behavior](#exit-behavior)
- [Safety, updates, and recovery](#safety-updates-and-recovery)

## Command model

The public entry point is `iconforge`. A repository checkout uses the same dispatcher as `./iconforge.sh`.

| Command   | Purpose                                                        |
|-----------|----------------------------------------------------------------|
| `forge`   | Build one or more `.icns` files from supported images          |
| `inspect` | Report how an application bundle declares and stores its icon  |
| `apply`   | Apply one `.icns` directly or reconcile a managed icon library |
| `restore` | Restore an internal backup or remove a Finder custom icon      |
| `refresh` | Refresh user-level macOS icon caches                           |
| `nuke`    | Compatibility alias for `refresh`                              |
| `help`    | Show root help or help for one known command                   |

General syntax:

```bash
iconforge <command> [arguments] [options]
```

The original image-first syntax remains supported:

```bash
iconforge ./logo.png BrandMark --output ./icons
```

It is equivalent to:

```bash
iconforge forge ./logo.png BrandMark --output ./icons
```

This compatibility dispatch has one consequence: an unknown first word is treated as a forge input, not rejected as an
unknown command.

With no arguments:

- In an interactive terminal, Icon Forge opens the forge prompts.
- With noninteractive standard input or output, it prints root help and returns success.

### Parser conventions

- Short options are separate tokens. Combined spellings such as `-nq` are not accepted.
- Value options use a following token. Spellings such as `--output=./icons` are not accepted.
- Command options can generally appear before or after positional arguments because each command scans its full argument
  list.
- Root `-h/--help` and `-V/--version` must appear before a command.
- `forge` accepts `--` to end option parsing. Every later token is positional.
- `apply`, `restore`, and `refresh` do not implement an end-of-options marker.

## Global options, help, and version

| Short | Long        | Description                           |
|-------|-------------|---------------------------------------|
| `-h`  | `--help`    | Show the root command overview        |
| `-V`  | `--version` | Print `iconforge v<version>` and exit |

Help forms:

```bash
iconforge --help
iconforge help
iconforge help forge
iconforge help inspect
iconforge help apply
iconforge help restore
iconforge help refresh
iconforge help nuke
iconforge apply --help
iconforge apply -h
```

An unknown `help` topic returns nonzero. `forge` also accepts `-V/--version` after the command. The other commands do
not have a command-level version flag.

## `forge`

Create macOS `.icns` files from source images.

### Synopsis

```bash
iconforge forge <input-image> [output-name] [options]
iconforge forge <input-image>... [options]
iconforge forge <directory> --recursive [options]
iconforge <input-image> [output-name] [options]
```

### Positional interpretation

After options are removed, forge inputs are interpreted in this order:

1. If `-r/--recursive` is active and the first positional value is a directory, that directory becomes the recursive
   scan root.
2. Otherwise, exactly two positional values mean `<input-image> <output-name>` when the first is a regular file and the
   second is not an existing regular file.
3. Otherwise, every positional value is treated as an input file.

The output-name override is therefore available only for one input. In a two-item batch, both paths must already exist
as regular files or the second value is interpreted as the first file's output name.

In recursive mode, only the first positional directory is used as the scan root. Do not combine a recursive directory
with additional positional inputs.

### Options

| Short | Long            | Value   | Description                                                                                                    |
|-------|-----------------|---------|----------------------------------------------------------------------------------------------------------------|
| `-o`  | `--output`      | `<dir>` | Output directory. Default: current working directory or `CUSTOM_OUTPUT`                                        |
| `-k`  | `--keep-png`    | none    | Keep a PNG beside each generated `.icns`                                                                       |
| `-r`  | `--recursive`   | none    | Recursively find supported images below the first directory argument                                           |
| `-q`  | `--no-warnings` | none    | Skip the confirmation prompt for a source with either dimension below 512 pixels; the warning is still printed |
| `-n`  | `--dry-run`     | none    | Print planned filesystem and processor commands without creating output                                        |
| `-V`  | `--version`     | none    | Print the Icon Forge version                                                                                   |
| `-h`  | `--help`        | none    | Show complete forge help                                                                                       |
| none  | `--`            | none    | Stop option parsing and treat remaining tokens as positional values                                            |

`KEEP_PNG`, `RECURSIVE`, and `SUPPRESS_WARNINGS` can set command defaults. Passing the corresponding flag always enables
the feature; there is no CLI flag that disables a `true` default.

### Supported source formats

Extensions are checked case-insensitively.

| Format | Extensions      | Decoder behavior                                      |
|--------|-----------------|-------------------------------------------------------|
| PNG    | `.png`          | Used directly as the source image                     |
| JPEG   | `.jpg`, `.jpeg` | Decoded and converted to temporary PNG                |
| WebP   | `.webp`         | Decoded and converted to temporary PNG                |
| TIFF   | `.tiff`, `.tif` | Decoded and converted to temporary PNG                |
| GIF    | `.gif`          | The first decoded frame is converted to temporary PNG |

Files with other extensions are skipped as unsupported, even if their contents use a decodable format.

### Image processing

For each accepted input, Icon Forge:

1. Uses the PNG directly or decodes another supported format to a uniquely named temporary PNG under
   `ICONFORGE_TMP_DIR` or `/tmp`.
2. Reads the decoded dimensions.
3. Warns when either dimension is below 512 pixels and prompts unless `-q/--no-warnings` is active.
4. Uses Catmull-Rom scaling to create square representations.
5. Assembles PNG chunks for 16, 32, 64, 128, 256, 512, and 1024 pixels into one `.icns`.
6. Removes the temporary `.iconset` after successful assembly and removes the converted temporary PNG whenever that
   file's operation finishes.

Scaling fills each square target exactly. It does not preserve a rectangular source's aspect ratio or add padding.
Prepare square artwork before forging when proportions matter.

Alpha-capable sources remain alpha-capable through RGBA scaling. Icon Forge does not add a display backplate; any extra
treatment applied while showing the icon belongs to macOS.

### Output names and files

The starting basename is the explicit output name, or the input filename without its final extension. Icon Forge then
removes every character except letters, numbers, `_`, and `-`. If nothing remains, the basename becomes `icon`.

For this command:

```bash
iconforge forge ./messages.png google-messages --output ./icons
```

the primary output is:

```text
./icons/google-messages.icns
```

With `--keep-png`, the additional output is:

```text
./icons/google-messages.png
```

For a PNG source, the kept PNG is a copy of the input. For another supported format, it is the decoded PNG conversion
used by the forge.

Existing `.icns`, kept PNG, and same-named temporary `.iconset` contents can be overwritten without confirmation.

### Batch behavior and collisions

Batch mode processes every selected input and returns nonzero if any one fails. An unsupported or missing item does not
stop later items from being attempted.

Before processing existing file inputs, Icon Forge rejects duplicate basenames after only the extension is removed. It
does not perform a second collision check after output-name sanitization. Names such as `my icon.png` and `myicon.jpg`
can therefore collapse to the same output path. Keep sanitized batch basenames unique.

Recursive discovery includes supported files at any depth below the scan root. The first directory's own name does not
become part of output naming, so same-named files from different subdirectories conflict or overwrite at the shared
output root.

### Interactive mode

Running `iconforge` with no arguments in an interactive terminal prompts for:

1. Input files or a directory
2. Output directory
3. Whether to keep PNGs
4. Whether directory scanning is recursive
5. Whether to skip small-image confirmation prompts

The input response is split on whitespace. Quoted paths are not reparsed as shell quoting, so use the normal command
line for paths containing spaces.

### Forge examples

Use the input basename:

```bash
iconforge forge ./messages.png
```

Choose the output basename and directory:

```bash
iconforge forge ./messages.png google-messages -o /path/to/icon-library/google-messages
```

Keep the decoded PNG:

```bash
iconforge forge ./messages.webp google-messages -o ./icons -k
```

Recursively convert a directory and skip small-image prompts:

```bash
iconforge forge ./artwork -r -o ./icons -q
```

Preview planned commands:

```bash
iconforge forge ./messages.png google-messages -o ./icons -n
```

Pass a dash-prefixed filename after the end-of-options marker:

```bash
iconforge forge -- ./-alternate.png
```

## `inspect`

Inspect icon-related metadata without changing the application.

### Synopsis

```bash
iconforge inspect <app>
```

`<app>` may be a valid bundle path or an app bundle filename with or without `.app`. Direct application lookup uses
bundle directory names, not display names or bundle identifiers.
See [Direct application resolution](#direct-application-resolution).

### Options

| Short | Long     | Description                                                |
|-------|----------|------------------------------------------------------------|
| `-h`  | `--help` | Show complete inspect help when used as the first argument |

### Reported fields

`inspect` prints:

- Resolved app, `Contents/Info.plist`, and `Contents/Resources` paths
- Icon source classification: `asset catalog backed`, `loose .icns`, or `unresolved`
- `CFBundleIconFile`
- `CFBundleIconName`
- Primary icon name and files under `CFBundleIcons`
- Top-level `.car` files in `Contents/Resources`
- Resolved loose `.icns`, if one can be selected
- The raw `CFBundleIcons` value, when present
- A plain-language summary of the classification

The summary explains the observed metadata. It does not print the result of strategy selection, although `auto` later
uses the same inspection state.

Examples:

```bash
iconforge inspect "Google Chrome"
iconforge inspect "/Applications/Spotify.app"
iconforge inspect "$HOME/Applications/My Standalone App.app"
```

## `apply`

`apply` has two modes, selected by the presence of `-i/--icon`:

1. Direct apply pairs one app with one existing `.icns`.
2. Managed reconciliation scans a directory-based icon library and matches its keys to discovered apps.

### Synopses

Direct mode:

```bash
iconforge apply <app> --icon <file.icns> [options]
iconforge apply <app> -i <file.icns> [options]
```

Managed mode:

```bash
iconforge apply <managed-key> [managed-options]
iconforge apply --all [managed-options]
iconforge apply -a [managed-options]
iconforge apply
```

With no app and no `--icon`, `apply` reconciles every directory in the resolved icon root. `--all` is the explicit
spelling of the same no-key behavior.

### Apply options

| Short | Long               | Value         | Intended mode     | Description                                                                  |
|-------|--------------------|---------------|-------------------|------------------------------------------------------------------------------|
| `-i`  | `--icon`           | `<file.icns>` | Direct            | Select direct mode and provide the replacement icon                          |
| `-s`  | `--strategy`       | `<name>`      | Both              | Request `auto`, `native`, `internal-icns`, or compatibility value `fileicon` |
| `-a`  | `--all`            | none          | Managed           | Explicitly request all entries when no key is supplied                       |
| `-r`  | `--icon-root`      | `<dir>`       | Managed           | Set the managed icon root                                                    |
| `-c`  | `--refresh-caches` | none          | Direct            | Refresh caches after applying the icon                                       |
| none  | `--nuke`           | none          | Direct            | Compatibility alias for `--refresh-caches`                                   |
| `-f`  | `--force-asset`    | none          | Internal strategy | Permit explicit internal replacement on a classified asset-catalog app       |
| `-S`  | `--no-resign`      | none          | Internal strategy | Skip ad hoc signing after internal bundle mutation                           |
| `-n`  | `--dry-run`        | none          | Both              | Resolve and validate the operation but do not modify apps or caches          |
| `-v`  | `--verbose`        | none          | Managed           | Print one status line per selected library entry                             |
| `-h`  | `--help`           | none          | Both              | Show complete apply help                                                     |

The parser accepts options in either order around the single positional app or key. A second positional value is
rejected.

`--all` cannot be combined with `--icon`. In managed mode, supplying both a key and `--all` currently processes only
that key. Managed mode parses `-c/--refresh-caches/--nuke` but does not use it; managed cache refresh is automatic and
described below.

### Direct apply

Direct mode performs these steps:

1. Require one app argument and a nonempty `--icon` value.
2. Resolve and inspect the app using direct lookup.
3. Select the requested strategy.
4. Require an existing icon path whose filename ends in lowercase `.icns`.
5. Apply the strategy.
6. Refresh caches only when `-c/--refresh-caches/--nuke` is present.

The managed plist is not loaded in direct mode. Per-app aliases, bundle IDs, exclusions, and configured strategies
therefore do not affect a direct apply.

`--dry-run` still requires the app, inspected icon metadata, replacement file, selected strategy, and required helper to
be valid. It suppresses the copy, AppKit, touch, signing, and cache mutations.

Direct internal apply computes checksums and reports when the target already matches, but it still runs the backup,
copy, touch, and signing path. Only managed reconciliation can return `already-correct` and skip an internal apply.

### Strategy selection and behavior

`auto` is the default. Selection is exact:

1. An app with a usable existing Finder custom icon selects `native`, preserving the same application route.
2. Otherwise, a classified asset-catalog app selects `native`. If the helper is unavailable, selection fails rather
   than falling back to a loose icon that may not control the visible application icon.
3. Otherwise, an app whose code signature reports a real `TeamIdentifier` selects `native`. Icon Forge does not
   internally mutate a vendor-signed bundle during automatic selection.
4. Otherwise, an existing resolved loose `.icns` selects `internal-icns` only when the app directory, resources,
   target icon, Info.plist, and any existing backup are writable.
5. Otherwise, the bundled native helper selects `native`.
6. Selection fails only when no writable internal route exists and the native helper is unavailable.

An explicit `native` request works for any resolvable app when the helper is available. An explicit `internal-icns`
request still requires a resolved existing loose `.icns`.

#### `native`

The `native` strategy:

1. Calls the bundled Objective-C/AppKit helper with `set <app> <icon>`.
2. Uses `NSWorkspace` to set a Finder custom icon on the `.app` directory.
3. Verifies the Finder custom-icon flag and the `Icon\r` custom-icon payload.
4. Runs a second helper `test` from the Bash strategy after a real apply.

It does not replace app-bundle contents, touch the app, create an internal backup, or re-sign the bundle. It overwrites
any existing Finder custom icon without preserving that previous custom icon.

Creating or removing the Finder custom icon still requires write access to the `.app` directory. For a protected or
root-owned bundle, direct apply fails before invoking AppKit and prints a narrowly scoped `sudo <helper> set ...`
command. Managed reconciliation reports `needs-authorization` instead of collapsing this case into `failed`. Icon
Forge never prompts for a password or invokes `sudo` itself.

Managed reconciliation cannot checksum a native Finder custom icon against the library `.icns`, so native entries are
applied again on every real reconciliation and count as changed.

#### `internal-icns`

The `internal-icns` strategy:

1. Resolves a loose icon under `Contents/Resources`.
2. Computes SHA-256 checksums for the replacement and target.
3. Creates `<target-basename>_ugly.icns` beside the target only when that backup does not already exist.
4. Copies the replacement over the target.
5. Touches the app directory and `Contents/Info.plist`.
6. Runs `codesign --force --deep --sign - <app>` unless `-S/--no-resign` is present.
7. After signing, verifies the complete bundle strictly across every architecture before reporting success.

If touching, signing, or verification fails after replacement, Icon Forge copies the preserved backup back over the
target and attempts the touch/sign/verify sequence again on that restored state. If the rollback cannot itself be fully
verified, the command fails with instructions to reinstall the app from its official source before launch.

The first existing backup is preserved across later applies. Icon Forge does not verify that a preexisting `*_ugly.icns`
was created by Icon Forge or that it contains the current app's original icon.

A classified asset-catalog app refuses an explicit internal apply unless `-f/--force-asset` is present. The flag removes
that refusal only. It does not create a missing loose target or make an unused `.icns` visible to macOS.

Automatic selection also keeps vendor-signed loose-icon apps on the native route. An explicit `internal-icns` request
remains an expert override and replaces the vendor signature with an ad hoc signature; this can interfere with launch,
updaters, entitlements, or policy enforcement even when strict verification succeeds.

#### `fileicon`

`fileicon` is accepted as a CLI or plist strategy value for compatibility. Strategy selection normalizes it to `native`.
Icon Forge does not locate, require, or execute a `fileicon` binary.

### Direct-apply examples

Use automatic selection and refresh caches:

```bash
iconforge apply "$HOME/Applications/Google Messages.app" \
  -i /path/to/icon-library/google-messages/google-messages.icns -c
```

Preview a direct apply:

```bash
iconforge apply "/Applications/Spotify.app" \
  --icon /path/to/icon-library/spotify/spotify.icns --dry-run
```

Request a Finder custom icon explicitly:

```bash
iconforge apply "My App" -i ./MyApp.icns -s native -c
```

Request internal replacement without automatic re-signing:

```bash
iconforge apply "Visual Studio Code" \
  -i ./visual-studio-code.icns -s internal-icns -S
```

## Managed icon libraries

A managed icon library uses one top-level directory per application key. The directories, not the plist's `applications`
dictionary, define the set of entries reconciled.

### Managed invocations

Reconcile the resolved root:

```bash
iconforge apply
```

Spell the same all-entry operation explicitly:

```bash
iconforge apply --all
```

Reconcile one key:

```bash
iconforge apply visual-studio-code
```

### Directory contract

```text
<icon-root>/
├── google-chrome/
│   └── google-chrome.icns
├── spotify/
│   └── spotify.icns
└── visual-studio-code/
    └── visual-studio-code.icns
```

Only directories directly below the icon root become keys. Files at the root are ignored. Only files directly inside a
key directory participate in icon resolution; nested assets are ignored.

### Managed icon resolution

For key `spotify`, resolution uses this precedence:

1. `spotify/spotify.icns`, even when other `.icns` files are present.
2. Exactly one top-level `.icns` with any filename.
3. Multiple non-preferred `.icns` files produce `ambiguous-icns` and a failed entry.
4. If no `.icns` exists, `spotify/spotify.png` produces `needs-forge`, even when other PNGs are present.
5. If no preferred PNG exists, exactly one top-level `.png` produces `needs-forge`.
6. Multiple non-preferred PNGs produce `ambiguous-png` and a failed entry.
7. No usable `.icns` or PNG produces `missing-icon` and a failed entry.

Managed resolution recognizes PNG only as an un-forged source marker. JPEG, WebP, TIFF, and GIF files in a managed
directory are ignored. Reconciliation never calls `forge` automatically.

### Icon-root precedence

Highest priority wins:

1. `-r/--icon-root <dir>`
2. `ICONFORGE_ICON_ROOT`
3. `icon_root` in `~/.config/iconforge/config.plist`

`~` and `~/...` are expanded for CLI, environment, and plist roots. Other shell expansions are not performed.

Icon Forge has no built-in icon-library path. If none of the three sources above provides a root, managed apply stops
with an error. A missing root, a root that is not a directory, or an empty root with no key directories likewise stops
reconciliation before an entry summary.

### Managed application discovery

Managed mode searches these roots in order:

1. `~/Applications`, or `ICONFORGE_USER_APPLICATIONS_DIR` when set
2. `/Applications`, or `ICONFORGE_SYSTEM_APPLICATIONS_DIR` when set

It discovers `.app` directories one or two levels below each root and sorts paths within each root. An app must contain
`Contents/Info.plist`.

Managed discovery does not include the current directory or `/System/Applications`. This differs from direct application
lookup.

For every discovered app, Icon Forge records:

- Full path
- `CFBundleIdentifier`
- `CFBundleDisplayName`
- `CFBundleName`
- Bundle directory filename

### Matching normalization

Managed keys, aliases, display names, bundle names, and filenames are normalized by:

1. Lowercasing
2. Removing a final `.app`
3. Replacing non-alphanumeric runs with one space
4. Trimming and collapsing spaces

For example, `visual-studio-code`, `Visual Studio Code`, and `Visual_Studio_Code.app` normalize to the same token.

### Managed matching precedence

For each key, matching is:

1. Exclusion check. An exact, case-sensitive key in `exclusions` becomes `skipped`.
2. Configured `app_path`. It must exactly equal a discovered path after `~` expansion. If configured but missing,
   matching stops with `missing-explicit-path`; there is no fallback.
3. Configured `bundle_id`. The first discovered app with that exact identifier wins. If none matches, name matching
   continues.
4. Exact normalized name matching. The key and every configured alias are compared with each app's display name, bundle
   name, and filename. One candidate wins; multiple candidates are `ambiguous-name`.
5. Partial normalized name matching. A substring match is attempted with the final token in the key-plus-alias sequence.
   With aliases, that is the final configured alias; without aliases, it is the key. One candidate wins; multiple
   candidates are `ambiguous-partial`.
6. No candidate becomes `missing`.

The bundle-ID step does not detect duplicate installed copies with the same identifier. Because discovery is user-root
first and sorted within each root, the first record wins. Use `app_path` when stable, beta, copied, or
duplicate-bundle-ID apps coexist.

### Managed strategy precedence

For each matched app:

1. Start with the CLI `-s/--strategy` value, defaulting to `auto`.
2. When that value is `auto`, use a configured per-key `strategy` when present.
3. Run normal strategy selection on the resulting value.

Explicit CLI `native`, `internal-icns`, or `fileicon` therefore overrides plist strategies for every selected entry.
Explicit CLI `auto` still permits each plist strategy to take effect.

### Reconciliation statuses

Per-entry statuses appear only with `-v/--verbose`.

| Status            | Meaning                                                                |
|-------------------|------------------------------------------------------------------------|
| `applied`         | A real apply completed                                                 |
| `would-apply`     | Dry-run validation reached an apply that was not executed              |
| `already-correct` | An internal loose icon already has the library icon's SHA-256 checksum |
| `missing-app`     | App matching ended in `missing` or `missing-explicit-path`             |
| `ambiguous`       | Exact or partial name matching found multiple candidates               |
| `needs-forge`     | A deterministic PNG exists but no `.icns` exists                       |
| `needs-authorization` | The selected native write needs scoped administrator authorization |
| `failed`          | Library resolution, inspection, strategy selection, or apply failed    |
| `skipped`         | Configuration excluded the exact key                                   |

The summary reports applied or would-apply, already correct, missing applications, ambiguous matches, needs forge,
needs authorization, and failed counts. Skipped entries are omitted from the summary count and visible only in verbose
output.

`failed` and `needs-authorization` entry counts make a completed reconciliation return nonzero because requested work
remains incomplete. Missing apps, ambiguous name matches, needs-forge entries, and exclusions do not by themselves make
the final status nonzero.

Configuration or root setup can fail before entry processing and return nonzero without a reconciliation summary.

### Managed cache behavior

After a real reconciliation, Icon Forge calls `refresh` once when at least one entry reached `applied`. It does this
after every selected entry has been processed, including a run that also contains failures.

It does not refresh when all entries are already correct, skipped, missing, ambiguous, need forging, need authorization,
or failed. It does not refresh during `--dry-run`.

Because native entries cannot be checksum-compared, a successful native entry is reapplied and triggers the one final
refresh on every real run.

### Managed examples

Preview all entries from a configured root with statuses:

```bash
iconforge apply -a -n -v
```

Reconcile an explicit root:

```bash
iconforge apply --all --icon-root /path/to/icon-library --verbose
```

Reconcile only one key:

```bash
iconforge apply spotify -r /path/to/icon-library -v
```

Force every selected entry through the native strategy:

```bash
iconforge apply -a -r /path/to/icon-library -s native -v
```

## `restore`

Restore an internal icon backup or remove a Finder custom icon from one app.

### Synopsis

```bash
iconforge restore <app> [options]
```

### Options

| Short | Long               | Description                                             |
|-------|--------------------|---------------------------------------------------------|
| `-c`  | `--refresh-caches` | Refresh caches after restoring                          |
| none  | `--nuke`           | Compatibility alias for `--refresh-caches`              |
| `-S`  | `--no-resign`      | Skip ad hoc signing after an internal restore           |
| `-n`  | `--dry-run`        | Resolve and validate without changing the app or caches |
| `-h`  | `--help`           | Show complete restore help                              |

`restore` accepts exactly one app argument and has no strategy option.

### Restore selection and precedence

After resolving and inspecting the app, Icon Forge selects one operation:

1. If the resolved loose target's expected `*_ugly.icns` exists, use it.
2. Otherwise, scan top-level `Contents/Resources` for `*_ugly.icns`. If exactly one exists, use it.
3. If zero or multiple backups are found, use the native helper to remove the app directory's Finder custom icon.
4. If no backup is selectable and the helper is unavailable, fail.

An internal restore copies the backup over the resolved target. If inspection did not resolve a target, the target path
is derived by removing `_ugly` from the selected backup filename. The app and `Info.plist` are touched and the bundle is
ad hoc re-signed unless `--no-resign` is present.

The backup is not deleted after restoration.

Only one branch runs. When a backup is selected, `restore` does not also remove a Finder custom icon. When no backup is
selected, native removal does not know whether Icon Forge created the current Finder custom icon. It removes any custom
icon at that level and cannot recover a previous one.

Multiple internal backups are not treated as an explicit ambiguity error. They fall through to native removal. Inspect
and resolve such bundles manually before restoring.

### Restore examples

Restore and refresh:

```bash
iconforge restore "$HOME/Applications/Google Messages.app" -c
```

Preview restore selection:

```bash
iconforge restore "Visual Studio Code" --dry-run
```

Restore an internal backup without automatic signing:

```bash
iconforge restore "/Applications/MyApp.app" --no-resign --refresh-caches
```

## `refresh` and `nuke`

Refresh user-level macOS icon caches. `refresh` is the preferred command; `nuke` is a compatibility alias with identical
behavior.

### Synopsis

```bash
iconforge refresh [app] [options]
iconforge nuke [app] [options]
```

### Options

| Short | Long        | Description                                                                  |
|-------|-------------|------------------------------------------------------------------------------|
| `-n`  | `--dry-run` | Print planned touches, removals, and service restarts without executing them |
| `-h`  | `--help`    | Show complete refresh help                                                   |

At most one app argument is accepted. When present, direct application resolution runs first, then Icon Forge touches
the app directory and `Contents/Info.plist`.

### Cache targets and service refresh

Icon Forge considers these user-level targets:

- `~/Library/Caches/com.apple.iconservices.store`
- `~/Library/Caches/com.apple.iconservices`
- `com.apple.dock.iconcache` inside `getconf DARWIN_USER_CACHE_DIR`, when present
- Entries matching `com.apple.iconservices*` in that Darwin user cache directory

Existing targets are removed recursively. In dry-run mode, the fixed targets are printed even when they do not exist.

Icon Forge then makes best-effort, quiet calls to restart:

1. Finder
2. Dock
3. `iconservicesagent`

When `qlmanage` is on `PATH`, it also runs `qlmanage -r cache`. Failures from these restart and Quick Look calls are
ignored.

Refresh does not delete privileged system-wide caches. It prints `Icon caches refreshed` after the best-effort work;
that message does not prove that every macOS process accepted the restart request.

### Refresh examples

Refresh caches:

```bash
iconforge refresh
```

Touch one app before refreshing:

```bash
iconforge refresh "/Applications/Spotify.app"
```

Preview through the compatibility alias:

```bash
iconforge nuke --dry-run
```

## Application resolution and icon inspection

Direct commands and managed reconciliation use different application discovery systems.

| Behavior                         | Direct `inspect`, `apply -i`, `restore`, app-specific `refresh` | Managed `apply`                    |
|----------------------------------|-----------------------------------------------------------------|------------------------------------|
| Accepts an explicit bundle path  | yes                                                             | only through configured `app_path` |
| Searches current directory       | yes                                                             | no                                 |
| Searches `~/Applications`        | yes                                                             | yes                                |
| Searches `/Applications`         | yes                                                             | yes                                |
| Searches `/System/Applications`  | yes                                                             | no                                 |
| Uses display name or bundle name | no                                                              | yes                                |
| Uses bundle ID                   | no                                                              | configured matching only           |
| Uses configured aliases          | no                                                              | yes                                |

### Direct application resolution

If the argument is an existing directory containing `Contents/Info.plist`, Icon Forge returns its real path immediately.

Otherwise, it appends `.app` when absent and searches for that bundle directory filename in this order:

1. Current working directory
2. `~/Applications`
3. `/Applications`
4. `/System/Applications`

It checks each root directly, then searches one or two directory levels below every root with a case-insensitive
filename match. Canonically identical paths are deduplicated.

Zero results are an error. One result wins. Multiple distinct results are an ambiguity error and are printed. Resolution
does not inspect `CFBundleDisplayName`, `CFBundleName`, or `CFBundleIdentifier`.

Use an explicit path when stable, beta, dev, or copied apps share a bundle directory name.

### Icon metadata inspection

For the resolved app, inspection reads top-level icon metadata and resources.

Loose `.icns` candidate precedence is:

1. `CFBundleIconFile`
2. `CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName`
3. `CFBundleIconName`
4. Values in `CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles`
5. Exactly one top-level `.icns` under `Contents/Resources`, excluding `*_ugly.icns`

Candidate names are tried as written and with `.icns` appended when needed. The first existing file wins. If metadata
does not resolve a file and more than one loose `.icns` exists, no target is selected.

An app is classified as asset-catalog backed only when both conditions hold:

- At least one top-level `.car` exists under `Contents/Resources`.
- `CFBundleIconName` or the primary `CFBundleIconName` is nonempty.

This is a conservative heuristic, not a complete parser for asset catalogs. An app can contain `Assets.car` and still
remain unclassified when the expected icon-name keys are absent.

## Configuration plist

Managed reconciliation reads one optional plist:

```text
~/.config/iconforge/config.plist
```

There is no CLI flag or environment variable for another plist path.

### Top-level keys

| Key            | Type             | Purpose                                        |
|----------------|------------------|------------------------------------------------|
| `icon_root`    | string           | Managed icon root used when CLI/env omit it    |
| `exclusions`   | array of strings | Exact, case-sensitive managed keys to skip     |
| `applications` | dictionary       | Per-key aliases, path, bundle ID, and strategy |

Unknown keys are ignored. Application entries do not create managed work by themselves; a same-named directory must
exist in the selected icon root.

### Per-application keys

| Key         | Type             | Purpose                                                                       |
|-------------|------------------|-------------------------------------------------------------------------------|
| `aliases`   | array of strings | Additional normalized names for exact matching and the final partial fallback |
| `app_path`  | string           | Exact discovered app path; `~` and `~/...` are expanded                       |
| `bundle_id` | string           | Exact `CFBundleIdentifier` match when no `app_path` is configured             |
| `strategy`  | string           | `auto`, `native`, `internal-icns`, or compatibility value `fileicon`          |

An `app_path` entry is fail-closed. If the exact path is not in managed discovery, matching does not try bundle ID or
names.

### Complete example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>icon_root</key>
        <string>~/path/to/icon-library</string>

        <key>exclusions</key>
        <array>
            <string>_icon_graveyard</string>
        </array>

        <key>applications</key>
        <dict>
            <key>google-messages</key>
            <dict>
                <key>app_path</key>
                <string>~/Applications/Google Messages.app</string>
                <key>strategy</key>
                <string>native</string>
            </dict>

            <key>visual-studio-code</key>
            <dict>
                <key>aliases</key>
                <array>
                    <string>Visual Studio Code</string>
                    <string>Code</string>
                </array>
                <key>bundle_id</key>
                <string>com.microsoft.VSCode</string>
                <key>strategy</key>
                <string>internal-icns</string>
            </dict>
        </dict>
    </dict>
</plist>
```

The file must be a regular plist accepted by `plutil -lint`. `icon_root` must not be empty when present, and every
configured strategy must be one of the accepted values.

Invalid plist data makes managed reconciliation return nonzero before scanning entries. The parser records a diagnostic
internally, but the current public reconciliation path does not print that recorded configuration error.

## Environment and shell configuration

### Startup shell files

For compatibility, every public invocation sources these shell files when they exist, in this order:

1. `<runtime-root>/.iconforge.env`
2. `<runtime-root>/.iconforge.local.env`
3. `~/.iconforgerc`

Later files override earlier values, and sourced assignments can override exported environment values. These files
execute as Bash code, not as a restricted data format. Use only files you trust.

The plist is separate and is loaded only for managed reconciliation.

### User-facing variables

| Variable              | Purpose                                                                       |
|-----------------------|-------------------------------------------------------------------------------|
| `ICONFORGE_ICON_ROOT` | Managed icon root below the CLI override and above the plist                  |
| `CUSTOM_OUTPUT`       | Default forge output directory                                                |
| `KEEP_PNG`            | Exact value `true` enables PNG preservation by default                        |
| `RECURSIVE`           | Exact value `true` enables recursive forge mode by default                    |
| `SUPPRESS_WARNINGS`   | Exact value `true` skips small-image confirmation prompts by default          |
| `PREFIX`              | Install or uninstall prefix; default `~/.local`; not used by runtime commands |

### Runtime, packaging, and test overrides

| Variable                            | Purpose                                                    |
|-------------------------------------|------------------------------------------------------------|
| `ICONFORGE_PROCESSOR`               | Path to the bundled Go processor                           |
| `ICONFORGE_NATIVE_ICON`             | Path to the native AppKit helper                           |
| `ICONFORGE_PLIST_BUDDY_BIN`         | PlistBuddy command path                                    |
| `ICONFORGE_PLUTIL_BIN`              | `plutil` command path                                      |
| `ICONFORGE_CODESIGN_BIN`            | `codesign` command path                                    |
| `ICONFORGE_TOUCH_BIN`               | `touch` command path                                       |
| `ICONFORGE_KILLALL_BIN`             | `killall` command path                                     |
| `ICONFORGE_RM_BIN`                  | `rm` command path                                          |
| `ICONFORGE_CP_BIN`                  | `cp` command path                                          |
| `ICONFORGE_TMP_DIR`                 | Directory for temporary non-PNG forge conversions          |
| `ICONFORGE_USER_APPLICATIONS_DIR`   | Replacement for `~/Applications` in managed discovery only |
| `ICONFORGE_SYSTEM_APPLICATIONS_DIR` | Replacement for `/Applications` in managed discovery only  |

`ICONFORGE_DRY_RUN` is reset by the dispatcher and is not a supported environment default. Use each command's
`-n/--dry-run` flag.

## Installation and runtime layout

### Requirements

Building the current source requires:

- macOS
- The Go toolchain version accepted by `iconforge-processor/go.mod`, currently Go 1.24.6
- Xcode Command Line Tools, including `xcrun clang`
- Network access when Go modules are not already cached

The installed runtime does not need Go. Internal icon mutation uses the macOS `codesign` command at runtime; native
Finder icons use AppKit through the bundled helper.

### Source build and install

Build both binaries:

```bash
make build
```

Run from the checkout:

```bash
./iconforge.sh --version
./iconforge.sh forge ./artwork.png --output ./icons
```

Install for the current user under `~/.local`:

```bash
make install
export PATH="$HOME/.local/bin:$PATH"
```

Install to another user-writable prefix:

```bash
PREFIX="$HOME/Applications/iconforge-runtime" make install
```

For a system-wide `/usr/local` installation, build as the current user and elevate only the installer:

```bash
make build
sudo env PREFIX=/usr/local ./install.sh
```

The installer rejects `PREFIX=/`, replaces the existing `$PREFIX/lib/iconforge` runtime, and creates
`$PREFIX/bin/iconforge`.

Installed source layout:

```text
<prefix>/bin/iconforge
<prefix>/lib/iconforge/iconforge
<prefix>/lib/iconforge/VERSION
<prefix>/lib/iconforge/lib/iconforge/*.sh
<prefix>/lib/iconforge/iconforge-processor/iconforge-processor
<prefix>/lib/iconforge/iconforge-native-icon/iconforge-native-icon
```

The prefix must be writable by the invoking user or command.

### Uninstall

```bash
make uninstall
```

For a nondefault prefix:

```bash
PREFIX="$HOME/Applications/iconforge-runtime" ./uninstall.sh
```

Uninstall removes only the launcher and runtime paths under the selected prefix. It returns nonzero when neither exists.
It does not remove forged icons, managed libraries, configuration files, app backups, or Finder custom icons.

### Homebrew

The v2 formula template builds the Go processor, compiles the AppKit helper, installs the Bash runtime under Homebrew
`libexec`, and exposes `bin/iconforge`.

```bash
brew install villagealchemist/iconforge/iconforge
```

The separate tap is release-driven and may lag this branch. Verify the installed version before relying on this 2.x
reference:

```bash
iconforge --version
```

Maintainers should use [RELEASING.md](../RELEASING.md) to update the source tag and tap formula together.

## Compatibility reference

| Compatibility surface                                      | Current behavior                                                      |
|------------------------------------------------------------|-----------------------------------------------------------------------|
| `iconforge <image> ...`                                    | Routes to `iconforge forge <image> ...`                               |
| `iconforge nuke`                                           | Alias for `iconforge refresh`                                         |
| `apply --nuke`                                             | Alias for direct `apply --refresh-caches`                             |
| `restore --nuke`                                           | Alias for `restore --refresh-caches`                                  |
| Strategy `fileicon`                                        | Accepted, then normalized to `native`; no external executable is used |
| `forge -V/--version`                                       | Command-level version form retained alongside root `-V/--version`     |
| `.iconforge.env`, `.iconforge.local.env`, `~/.iconforgerc` | Trusted shell configuration retained for compatibility                |

Compatibility names do not preserve obsolete runtime dependencies. In particular, there is no `fileicon`, `ffmpeg`,
`iconutil`, or AppleScript requirement in the current runtime.

## Exit behavior

The public command uses `0` for successful requested work and nonzero for invalid arguments, missing required files or
tools, setup failure, or operation failure. It does not assign a stable documented numeric code to each public failure
class.

Command-specific details:

- `forge` continues a batch after per-file failures and returns nonzero if any selected item fails.
- `inspect` with no app prints inspect help and returns nonzero.
- `apply` with no arguments starts all-entry managed reconciliation; it is not a usage error.
- `restore` with no app prints restore help and returns nonzero.
- `refresh` with no app performs a real cache refresh.
- No-argument noninteractive invocation prints root help and returns `0`.
- Managed reconciliation returns nonzero for setup failures or a nonzero `failed` or `needs-authorization` count.
  `missing-app`, `ambiguous`, `needs-forge`, and `skipped` statuses do not make the completed summary fail.

### Native helper exit statuses

The bundled `iconforge-native-icon` helper is an internal interface with explicit statuses:

| Status | Meaning                                                                             |
|--------|-------------------------------------------------------------------------------------|
| `0`    | `set` or `remove` succeeded, or `test` found a usable Finder custom icon            |
| `1`    | AppKit operation failed, verification failed, or `test` found no usable custom icon |
| `64`   | Invalid helper command usage                                                        |
| `66`   | Invalid app bundle or icon input                                                    |

Its accepted commands are `set <app> <icon>`, `test <app>`, and `remove <app>`. The helper is packaged for Icon Forge
and is not the primary user CLI.

## Safety, updates, and recovery

### Start with dry-run

Preview a direct apply:

```bash
iconforge apply <app> -i <icon.icns> -n
```

Preview a managed library:

```bash
iconforge apply -a -r <icon-root> -n -v
```

Preview restore selection:

```bash
iconforge restore <app> -n
```

Dry-run does not relax validation. The app, replacement icon, strategy prerequisites, and managed configuration must
still resolve.

### Internal mutation and signing

Internal replacement changes signed app-bundle contents. Icon Forge ad hoc re-signs with
`codesign --force --deep --sign -` by default. `--no-resign` is available for controlled workflows, but a modified
bundle with an invalid signature may fail to launch or update.

The `*_ugly.icns` backup lives inside the app bundle. Keep it while restoration matters, but remember that app updates
can delete or replace it. A preexisting file with that name is trusted without provenance checks.

### Finder custom icons

Native apply does not alter files under `Contents` or re-sign the bundle. It does replace any Finder custom icon already
assigned to the app directory, and Icon Forge does not save the previous custom icon.

When no single internal backup is selectable, `restore` removes the current Finder custom icon without checking who
created it. It cannot restore an older Finder custom icon.

### Asset catalogs and forced internal apply

Asset-catalog classification is a heuristic. Use `inspect` before overriding it. `--force-asset` permits internal
replacement only when a loose target already resolves; it does not modify `Assets.car` and does not guarantee a visible
result.

### App updates and protected apps

Application updates can overwrite loose replacements, internal backups, or Finder custom-icon metadata. Re-run `apply`
after an update when appropriate.

System Integrity Protection, ownership, MDM policy, filesystem permissions, and application signature policy can prevent
modification. Do not disable macOS security features to force Icon Forge to alter a protected app.

When automatic selection finds a loose icon inside a nonwritable bundle, it chooses `native` instead of attempting an
internal backup and copy. Direct mode prints a scoped helper command; managed mode reports `needs-authorization`. Run
only that individual native-helper operation with `sudo`, then run `iconforge refresh` normally. Do not run a permanent
root shell, recursively change ownership under `/Applications`, or run an entire managed reconciliation as root.

Automatic selection likewise chooses `native` for a vendor-signed app with a loose icon. This matters for hardened and
updater-managed apps: replacing a sealed resource and ad hoc signing the bundle can prevent launch or leave the bundle
invalid after an updater replaces only part of it. If an earlier Icon Forge version already modified such an app and
`codesign --verify --deep --strict --all-architectures <app>` fails, reinstall or update the app from its official
source before reapplying the icon with v2.

Use a disposable copied app bundle for risky tests. Never use a live critical app as the first test of a forced or
unfamiliar path.

### Cache refresh

Refresh recursively removes a small set of user cache paths and restarts Finder, Dock, and `iconservicesagent`. Save
in-progress Finder work and expect brief interface disruption.

Refresh cannot recreate icon files, backups, or Finder metadata removed by an updater. It only asks macOS to rebuild
rendered state from what currently exists.

### Recovery sequence

Inspect first:

```bash
iconforge inspect <app>
```

Preview restoration:

```bash
iconforge restore <app> --dry-run
```

Restore and refresh when the selected operation is correct:

```bash
iconforge restore <app> --refresh-caches
```

If `restore --dry-run` selects native removal but the app contains multiple `*_ugly.icns` backups, stop and resolve the
intended backup manually. If an app updater removed the custom icon rather than leaving stale caches, use `apply` to
reapply it; `refresh` alone cannot recover it.
