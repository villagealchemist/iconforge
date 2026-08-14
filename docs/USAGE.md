# IconForge command reference

This is the complete public reference for IconForge 2.0.0. It describes the source tree, the source installation, and
the Homebrew formula built from that source.

## Contents

- [Operating model](#operating-model)
- [Invocation and parsing](#invocation-and-parsing)
- [`forge`](#forge)
- [Application resolution](#application-resolution)
- [`inspect`](#inspect)
- [Direct `apply`](#direct-apply)
- [Bulk `apply`](#bulk-apply)
- [`restore`](#restore)
- [`nuke`](#nuke)
- [Installation and runtime layout](#installation-and-runtime-layout)
- [Safety and recovery](#safety-and-recovery)
- [Development and verification](#development-and-verification)

## Operating model

IconForge is a stateless macOS command-line tool.

- Each invocation receives its image, application, icon directory, and output directory explicitly.
- The current directory is the only default forge destination.
- Bulk application always requires `-a/--all` and a directory on that same command line.
- No shell file, environment variable, preference file, or prior invocation supplies product defaults.
- Temporary work uses the standard per-user temporary directory when macOS provides one and otherwise `/tmp`.
- Dry runs inspect and validate real inputs but do not write outputs, change applications, remove caches, or restart
  user processes.

The public installation contains three cooperating pieces:

1. A Bash entry point and Bash libraries for parsing, planning, app discovery, and safe orchestration.
2. An IconForge-owned Go processor for decoding, resizing, PNG normalization, and ICNS assembly.
3. An IconForge-owned Objective-C/AppKit helper for Finder custom icons and read-only ICNS validation.

The Go dependency graph is vendored. Apple system interfaces and command-line tools are used where the operation is
specific to macOS.

## Invocation and parsing

### Root syntax

```text
iconforge [root-option]
iconforge <command> [arguments] [options]
iconforge help [command]
iconforge <existing-supported-image> [forge-arguments] [forge-options]
iconforge -- <existing-supported-image> [forge-arguments]
```

Root options:

| Short | Long        | Meaning                    |
|-------|-------------|----------------------------|
| `-h`  | `--help`    | Print root help            |
| `-v`  | `--version` | Print `iconforge v2.0.0`   |

No arguments prints root help and exits successfully. `iconforge forge` without an input prints forge help and exits
with an error; there is no prompt-driven setup mode.

The command names are `forge`, `inspect`, `apply`, `restore`, `nuke`, and `help`. An unknown word is a command error
unless it resolves to an existing supported image path. A command name wins over a same-named file; address that file
with `./`, an absolute path, or root `--`.

`iconforge help` prints the root overview. It accepts one command name to print that command's help and recognizes
`-h/--help` as another spelling of the root overview. Use `iconforge help -- <command>` when an explicit
end-of-options marker is useful.

Examples:

```bash
iconforge -v
iconforge --version
iconforge help apply
iconforge ./artwork.png
iconforge -- -strange-name.png
```

### Option grammar

Every command recognizes `--` as the end-of-options marker. Tokens after it are operands even if they begin with `-`.

Each public option has one short and one long spelling. Keep each short option separate and pass values as the next
argument:

```bash
iconforge forge -k -d -o ./preview ./art.png
```

These forms are rejected:

```text
iconforge forge -kd ./art.png
iconforge forge --output=./preview ./art.png
```

`-v` is contextual. At the root it means version; after `apply` it means verbose status output.

### Exit status

| Status | Meaning                                                                 |
|--------|-------------------------------------------------------------------------|
| `0`    | The requested work succeeded, or help/version was printed successfully |
| `1`    | Input, preflight, resolution, authorization, or execution failed        |
| `2`    | The command line itself was invalid                                     |

Bulk apply may skip expected unmatched, ambiguous, or declined entries and still return `0` when it successfully
applied at least one icon and encountered no validation or mutation failures. A bulk run with nothing eligible returns
nonzero.

## `forge`

Turn supported artwork into one or more `.icns` files.

### Syntax

```text
iconforge forge [options] <image> [output-name]
iconforge forge [options] <image> [<image> ...]
iconforge forge -r [options] <directory>
iconforge <existing-supported-image> [output-name] [options]
```

Options:

| Short | Long          | Value   | Meaning                                                  |
|-------|---------------|---------|----------------------------------------------------------|
| `-o`  | `--output`    | `<dir>` | Destination directory; default is the current directory  |
| `-k`  | `--keep-png`  | none    | Keep one normalized full-size PNG beside each ICNS       |
| `-r`  | `--recursive` | none    | Permit recursive processing of one directory             |
| `-f`  | `--force`     | none    | Replace pre-existing regular output files without asking |
| `-d`  | `--dry-run`   | none    | Print the complete plan without writing                   |
| `-h`  | `--help`      | none    | Print forge help                                          |

### Supported artwork

Extensions are matched case-insensitively:

- `.png`
- `.jpg` and `.jpeg`
- `.webp`
- `.tif` and `.tiff`
- `.gif`

The input must decode successfully regardless of its extension. Animated images use the decoder's representative
frame; IconForge output is static.

IconForge warns and continues when either source dimension is below 512 pixels. Upscaling a small source cannot invent
detail, so inspect the result before applying it.

### Single and multiple inputs

Without `--recursive`, each operand must be a supported image file. The normal output name is the input's filename stem
with its spaces and Unicode characters preserved:

```text
./art/My Great Icon.png → ./My Great Icon.icns
```

A final output name is accepted only for one image. It is a basename, not a path: it must be nonempty after its optional
`.icns` suffix is removed and cannot contain `/`.

```bash
iconforge forge ./art.png Product --output ./dist
```

This creates `./dist/Product.icns`. With `--keep-png`, it also creates `./dist/Product.png`.

### Recursive input

A directory is accepted only with `-r/--recursive`, must be the only input, and cannot use a custom output name.

```bash
iconforge forge --recursive ./source --output ./dist
```

Relative paths below the source are mirrored below the destination:

```text
source/chat/logo.png       → dist/chat/logo.icns
source/music/logo.webp     → dist/music/logo.icns
source/_drafts/test.tiff   → dist/_drafts/test.icns
```

The scan is deterministic and does not follow symlinks. It skips:

- Descendants whose path component begins with `.`.
- Generated directories whose name ends in `.iconset`.
- The output directory when it is a proper descendant of the input directory.

Ordinary underscore-prefixed directories are included. The source root itself remains valid regardless of its name.

### Manifest and collision checks

IconForge builds one immutable manifest before creating any output. It canonicalizes source and destination paths and
checks final paths case-insensitively so the plan is safe on the normal macOS filesystem.

The whole run fails before writing when:

- Two planned files resolve to the same final path.
- A planned output resolves to any selected input.
- A destination exists but is not a regular file.
- A custom name would escape or create another directory.
- A recursive source/output relationship cannot be made unambiguous.

With `--keep-png`, selecting a PNG whose canonical path is already its planned kept-PNG path is a no-op for that one
PNG. Any other source/output alias fails preflight.

### Existing output files

Pre-existing regular outputs are handled as one group:

- In an interactive terminal, IconForge lists the conflicts and asks once whether to replace them.
- Declining performs no writes.
- Without an interactive terminal, the run performs no writes.
- In either refusal case, IconForge prints an exact command using `-f/--force`.
- `--force` authorizes replacement of those existing regular files only. It never resolves manifest collisions or
  permits an input file to be overwritten.

### Transactional publication

After preflight, every ICNS and requested PNG is built in a private staging directory. Only a completely successful
staged run is published. Each final file is installed with an atomic replacement; if publication fails, IconForge puts
previous output files back and removes newly introduced files.

Temporary iconsets and staging directories are removed on success, failure, and interruption. A recursive operation
does not intentionally leave a half-published tree.

### Dry run

`-d/--dry-run` performs input discovery, decoding checks, naming, collision analysis, and overwrite analysis. It prints
planned outputs and planned replacements but does not ask the overwrite question, create directories, or write files.

### Forge examples

```bash
# Image-first, current-directory output
iconforge ./logo.png

# Explicit command and output directory
iconforge forge ./logo.webp --output ./build/icons

# Preserve a normalized PNG
iconforge forge ./logo.tiff Product --keep-png

# Mirror a source tree
iconforge forge ./artwork --recursive --output ./icons

# Replace already-existing regular outputs
iconforge forge ./artwork --recursive --output ./icons --force

# Treat a leading-dash filename as an operand
iconforge forge -- ./-draft.png
```

## Application resolution

`inspect`, direct `apply`, `restore`, and app-specific `nuke` share one resolver.

### Explicit paths

An explicit path works anywhere when it resolves to a valid `.app` bundle. Relative paths containing `/`, dot-prefixed
relative paths, and absolute paths are treated as paths and must exist. A bare installed-app name may include or omit
its `.app` suffix.

### Name search

Names are searched across:

- The current directory.
- `~/Applications`.
- `/Applications`.
- `/System/Applications`.

Search descends at most two directory levels below each root and never descends into an `.app` bundle.

Each candidate is compared using its bundle filename, `CFBundleDisplayName`, and `CFBundleName`. Normalization removes a
trailing `.app`, performs Unicode-aware case folding, treats punctuation and whitespace as separators, collapses those
separators, and trims them.

### Exact and partial results

- One exact normalized match resolves automatically.
- More than one exact match is ambiguous and fails.
- One unique partial match is shown as `Did you mean …?` in an interactive terminal.
- Confirming uses it for that run only.
- Declining, a noninteractive invocation, or multiple partial candidates does not guess.

When a name candidate has a nonempty `CFBundleIdentifier`, any other discovered bundle with that same identifier joins
the candidate set. This prevents automatic selection between duplicate installations of the same app.

Direct commands fail when resolution does not complete. Bulk mode skips unresolved keys and records their reason in
the final summary. IconForge never stores an alias or chosen application.

## `inspect`

Read an application's icon metadata without changing it.

### Syntax and options

```text
iconforge inspect <app>
iconforge inspect -- <app>
```

| Short | Long     | Meaning            |
|-------|----------|--------------------|
| `-h`  | `--help` | Print inspect help |

Exactly one app is required. Output includes:

- The resolved bundle, `Info.plist`, and resources paths.
- `CFBundleIconFile`, `CFBundleIconName`, and primary-icon values.
- Discovered `Assets.car` files.
- A resolved loose `.icns` target, when one exists.
- Whether the app appears to use an asset catalog.

`inspect` does not write the application, use the native helper's mutation operations, touch the bundle, sign it, or
run Nuke.

Examples:

```bash
iconforge inspect "Visual Studio Code"
iconforge inspect "/Applications/Google Chrome.app"
```

## Direct `apply`

Apply one existing `.icns` file to one application.

### Syntax and options

```text
iconforge apply <app> -i <file.icns> [options]
```

| Short | Long         | Value                    | Meaning                                      |
|-------|--------------|--------------------------|----------------------------------------------|
| `-i`  | `--icon`     | `<file.icns>`            | Required icon file                           |
| `-s`  | `--strategy` | `native\|internal-icns` | Select direct-apply strategy; default native |
| `-n`  | `--nuke`     | none                     | Run Nuke once after a successful real apply  |
| `-d`  | `--dry-run`  | none                     | Preview app, strategy, and optional Nuke      |
| `-v`  | `--verbose`  | none                     | Enable per-entry status in bulk mode          |
| `-h`  | `--help`     | none                     | Print apply help                              |

The app and icon must each appear exactly once. The icon must be a regular `.icns` file and pass read-only native
validation before mutation. `--strategy` cannot be used with bulk apply. Direct apply already prints its selected
strategy and result, so `-v/--verbose` does not add another direct status layer.

### Native strategy

Native is the default and the only strategy used by bulk mode. The bundled AppKit helper sets a Finder custom icon on
the `.app` root and then verifies that macOS reports one present.

This route does not:

- Replace anything under `Contents/`.
- Create an internal icon backup.
- Re-sign the app.
- Fall back to internal mutation when the helper is absent.

If the helper is missing or non-executable, IconForge reports a broken installation and stops. A real apply to a
nonwritable app is reported as needing authorization before mutation; dry-run can still show the intended native
operation. IconForge does not elevate itself. If authorization is appropriate, authorize only the native helper's
single-app operation rather than the entire CLI.

A native apply replaces any Finder custom icon that is already present. IconForge cannot reconstruct a prior Finder
customization after replacement.

### `internal-icns` strategy

This explicit expert strategy is available only for direct apply. Supplying its name is acknowledgment that IconForge
will replace vendor signing with an ad hoc signature.

Preflight requires:

- A writable `.app` bundle with writable resources and metadata.
- One existing loose `.icns` target resolved from the app's icon metadata.
- A valid replacement `.icns`.
- No indication that the app's icon comes from an asset catalog.
- No ambiguous internal backup state.

On the first internal apply, IconForge preserves the original loose icon as the app's `*_ugly.icns` backup. Later
applies do not overwrite that first backup. It then copies the replacement, touches the app, ad hoc re-signs the entire
bundle, and strictly verifies every architecture.

If copying, touching, signing, or verification fails, IconForge restores the preserved icon, touches and signs again,
and verifies the rollback. A rollback that cannot be fully verified is a hard failure; reinstall the app from its
trusted source before launching it.

### Direct dry run and Nuke

Dry-run prints the resolved app, chosen strategy, target, backup path where relevant, signing work, and requested Nuke
without performing any of it.

`-n/--nuke` runs once only after a real apply succeeds. It does not run after a failed operation or during dry-run.

Examples:

```bash
iconforge apply "Discord" --icon ./Discord.icns --dry-run
iconforge apply "/Applications/Discord.app" --icon ./Discord.icns --nuke
iconforge apply "/path/to/Disposable.app" -i ./Test.icns -s internal-icns
```

## Bulk `apply`

Match regular `.icns` files below one explicit directory to installed applications and apply them natively.

### Syntax and options

```text
iconforge apply -a <directory> [options]
iconforge apply --all <directory> [options]
```

| Short | Long        | Value   | Meaning                                         |
|-------|-------------|---------|-------------------------------------------------|
| `-a`  | `--all`     | none    | Select bulk mode; followed by one directory     |
| `-n`  | `--nuke`    | none    | Run Nuke once after at least one successful apply |
| `-d`  | `--dry-run` | none    | Validate and preview without changing apps      |
| `-v`  | `--verbose` | none    | Print a status line for each icon entry         |
| `-h`  | `--help`    | none    | Print apply help                                |

`-a/--all` is a selector, not a directory-valued option; the directory is the required positional operand that follows
it. Exactly one directory is accepted. Bulk mode rejects `--icon` and `--strategy`. Bare `iconforge apply` is an error
and never scans anything.

### Icon scan

The supplied root may begin with an underscore. A dot-hidden root or a root whose name ends in `.app` or `.iconset`
(case-insensitively) is rejected. Below an eligible root, the deterministic recursive scan collects regular `.icns`
files and does not follow symlinks. It prunes:

- Descendant components beginning with `.` or `_`.
- `.app` and `.iconset` directory trees.
- Internal rollback-backup filenames.

The filename stem, not its parent directory, is the app key:

```text
icons/social/Discord.icns             → key "Discord"
icons/work/Visual Studio Code.icns    → key "Visual Studio Code"
```

Every file is validated as ICNS before app mutation begins.

### Bulk preflight

All resolution and validation happens before the first change. The run fails without mutation when:

- Two filename stems normalize to the same key.
- Any collected file is malformed or unreadable.
- Two keys resolve to the same application.
- The native helper is missing.

Exact matches are included automatically. Unique partial suggestions are collected and presented in one interactive
question. Accepting includes those suggestions for this invocation only. Declining excludes the suggestions but allows
exact matches to continue. In noninteractive mode, suggestions are skipped with exact-path guidance.

### Execution and summary

Bulk apply always uses the native strategy. It never modifies `Contents/`, creates a backup, signs an app, or invokes
administrator authorization.

Entries run in deterministic order. The final summary counts:

- Applied.
- Unmatched.
- Ambiguous.
- Declined suggestions.
- Authorization needed.
- Failed.

Expected resolution skips remain visible. A permission, validation, helper, or mutation failure returns nonzero. If at
least one entry applies and there are no such failures, unmatched or declined entries do not make the entire run fail.
Nothing eligible returns nonzero.

With `-n/--nuke`, Nuke runs once after the complete bulk operation and only when at least one real application changed.
It never runs once per entry.

Examples:

```bash
iconforge apply --all ./icons --dry-run --verbose
iconforge apply -a ./icons -v
iconforge apply -a ./icons -n
iconforge apply -a -- ./-icons
```

## `restore`

Remove a Finder custom icon and restore one unambiguous internal backup when it exists.

### Syntax and options

```text
iconforge restore <app> [options]
```

| Short | Long        | Meaning                                          |
|-------|-------------|--------------------------------------------------|
| `-n`  | `--nuke`    | Run Nuke once after a successful real restore    |
| `-d`  | `--dry-run` | Preview without changing the app or user caches  |
| `-h`  | `--help`    | Print restore help                               |

Restore resolves exactly one app. It removes a Finder custom icon when present. If exactly one preserved internal
backup exists, it also copies that backup over the loose target, touches the bundle, ad hoc re-signs it, and strictly
verifies the result. Multiple plausible backups are ambiguous and fail closed.

Restoring icon bytes and applying an ad hoc signature cannot recreate a vendor's original signature. Reinstall from the
trusted vendor when original provenance is required.

`-n/--nuke` runs once only after a successful real restore.

Examples:

```bash
iconforge restore "Discord" --dry-run
iconforge restore "/Applications/Discord.app" --nuke
```

## `nuke`

Reset only the current user's macOS icon caches.

### Syntax and options

```text
iconforge nuke [app] [options]
```

| Short | Long        | Meaning                                             |
|-------|-------------|-----------------------------------------------------|
| `-d`  | `--dry-run` | Print cache paths and user processes without acting |
| `-h`  | `--help`    | Print Nuke help                                     |

With an app operand, IconForge resolves and touches that bundle before resetting caches. Without an app, it performs
only the current-user cache work.

Nuke considers these current-user cache locations:

- `~/Library/Caches/com.apple.iconservices.store`
- `~/Library/Caches/com.apple.iconservices`
- `com.apple.dock.iconcache` and `com.apple.iconservices*` below `DARWIN_USER_CACHE_DIR`, when that directory exists

It removes existing targets, then restarts the current user's Finder, Dock, and icon service agent. Quick Look is asked
to reset when its system utility is available. Missing cache files and processes are tolerated.

Nuke never targets privileged system-wide caches and refuses to run as root, because root's home and service context
are not the logged-in user's icon environment. Save active Finder work before running it.

Nuke can rebuild presentation from icon data that still exists. It cannot recreate a deleted Finder custom icon,
internal backup, or vendor-signed application content.

Examples:

```bash
iconforge nuke --dry-run
iconforge nuke
iconforge nuke "/Applications/Discord.app"
```

## Installation and runtime layout

### Requirements

- macOS.
- Bash 3.2 or newer for the command layer.
- Go new enough to satisfy the version declared in `iconforge-processor/go.mod` for source builds.
- Xcode Command Line Tools for `xcrun clang` and macOS frameworks.

The repository vendors the imported `golang.org/x/image` packages. `make build`, tests, and the Homebrew formula force
Go's vendor mode and do not resolve those packages over the network. See [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

### Source install

The default prefix is `~/.local`:

```bash
make install
```

Choose another non-root prefix explicitly:

```bash
PREFIX="$HOME/Applications/iconforge-runtime" make install
```

For a system-wide source installation, build as the normal user and elevate only the install copy:

```bash
make build
sudo env PREFIX=/usr/local ./install.sh
```

The installer refuses `/` as a prefix and refuses a nonexistent prefix whose nearest existing parent is not writable.
It replaces only IconForge's runtime directory and launcher below the selected prefix.

Installed layout:

```text
<prefix>/
├── bin/
│   └── iconforge
└── lib/iconforge/
    ├── iconforge
    ├── VERSION
    ├── LICENSE
    ├── THIRD_PARTY_NOTICES.md
    ├── lib/iconforge/
    ├── iconforge-processor/iconforge-processor
    └── iconforge-native-icon/iconforge-native-icon
```

The launcher resolves the sibling runtime directory and executes the installed entry point. The runtime does not
search the repository, current directory, home directory, or preference files for executable components.

Uninstall from the same prefix:

```bash
make uninstall
sudo env PREFIX=/usr/local ./uninstall.sh
```

Uninstall removes only `<prefix>/bin/iconforge` and `<prefix>/lib/iconforge`. It does not remove generated icons, modify
apps, erase current-user icon caches, or edit shell startup files. It returns nonzero when neither installation path
exists.

### Homebrew

```bash
brew install villagealchemist/iconforge/iconforge
```

The formula is source-only. It pins an exact source commit and checksum, builds both owned helpers, installs the same
runtime layout below `libexec`, and creates the public launcher in Homebrew's `bin`.

## Safety and recovery

### General rules

- Use `--dry-run` before unfamiliar operations.
- Use `inspect` before choosing internal mutation.
- Test internal mutation on a disposable app copy.
- Do not change ownership or permissions under `/Applications` to make an operation pass.
- Do not elevate the whole IconForge process.
- Treat an app update as capable of replacing any customization.

### Native customization

Native apply changes Finder-level custom-icon state outside `Contents/`, so it normally preserves the app's existing
code signature. It replaces any prior Finder custom icon and cannot preserve that unknown artwork for later recovery.

Some protected applications require authorization for the one AppKit helper operation. Direct apply stops with scoped
authorization guidance, and bulk apply skips the entry. If authorization is appropriate, elevate only the helper's
single-app operation and then run user-context Nuke without elevation.

### Internal mutation

Internal apply writes inside an application and deliberately replaces its signature with an ad hoc signature. That can
affect updater behavior, security checks, vendor support, and provenance. The first preserved icon is not a copy of the
vendor signature and cannot reconstruct it.

If internal apply or its rollback cannot be strictly verified, do not launch the bundle. Delete the disposable test or
reinstall the real app from its trusted source.

### Updates

An application updater can replace the bundle, delete an internal backup, or remove Finder custom-icon state.
IconForge cannot force an updater to retain those changes. Reinspect the updated app and reapply the source `.icns` if
appropriate.

## Development and verification

Common checks:

```bash
make build
make test
make test-verbose
make lint
make build-all
make version
```

- `make build` compiles the Go processor in vendor mode and the native helper for the current machine.
- `make test` runs Go tests and the shell integration suite.
- `make lint` runs ShellCheck when installed, `go vet` in vendor mode, and a non-mutating Go-format check.
- `make build-all` temporarily cross-compiles the Go processor and native helper for Intel and Apple silicon, then
  removes the artifacts. It is an architecture build check, not a release package.

The Go processor's ICNS tests require all ten standard and Retina representations:

```text
icon_16x16.png
icon_16x16@2x.png
icon_32x32.png
icon_32x32@2x.png
icon_128x128.png
icon_128x128@2x.png
icon_256x256.png
icon_256x256@2x.png
icon_512x512.png
icon_512x512@2x.png
```

CI runs the build, lint, test, cross-compilation, formula-contract, and clean-tree checks on pinned current Intel and
Apple-silicon macOS runners. This verifies those environments; it is not a blanket minimum-version claim.
