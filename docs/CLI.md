# IconForge: forge, hearth, apply

This is the public CLI contract for the unreleased forge/hearth overhaul.
The application backend remains macOS-only. This work changes user-facing
configuration and orchestration, not the Go image processor or AppKit helper.

## A library that fits your filesystem

```bash
iconforge config set the-forge "$HOME/icon-work"
iconforge config set the-hearth "$HOME/app-icons"
```

The names are configuration keys, not mandated folder names. The directories
can be identical or independent. The forge is the default output destination;
the hearth is the finished ICNS library used by both direct and bulk apply.
A flat folder of existing application-named ICNS files needs no import step.

```text
app-icons/
  Firefox.icns
  Discord.icns
  Visual Studio Code.icns
```

```bash
iconforge apply Firefox --dry-run
iconforge apply Firefox
iconforge apply Firefox nuke
iconforge apply --all --dry-run --verbose
iconforge apply --all --nuke
```

A bare `apply` is always a usage error. Merely configuring a directory never
selects all applications or triggers mutations.

## Resolution and precedence

| Operation | Explicit override | Saved preference | Compatibility fallback | Final fallback |
| --- | --- | --- | --- | --- |
| Forge output | `--output DIR` | `the-forge` | `default-directory` | Current directory |
| Direct library lookup | `--from DIR` | `the-hearth` | `default-directory` | Actionable usage error |
| Bulk library | Positional directory or `--from DIR` | `the-hearth` | `default-directory` | Actionable usage error |
| Direct icon file | `--icon FILE` | Not read | Not read | Not applicable |

An explicit output, icon, or library bypasses unrelated configuration, including
an unreadable preference file. `--icon` and `--from` are alternatives; using both
is a usage error. Supplying both a positional bulk directory and `--from` is also
an error. Flags do not persist preferences.

Application names use the existing macOS resolver. Exact normalized matches are
automatic; duplicate installations are not resolved by scan order. Existing
interactive confirmation for a unique partial app-name match remains available.
No alias decision is automatically saved. Scripts must use unambiguous names or
explicit app paths rather than depending on a prompt.

After resolving an app, direct library lookup compares icon filename stems with
its bundle filename, bundle display name, and bundle name, using the same native
normalization as bulk matching. It does not fuzzy-match icon names. Zero matches
reports the searched library and remedies. Multiple matching files or aliases
reports the candidates and requires an explicit `--icon` selection. Duplicate
keys unrelated to the selected app do not block a direct apply; bulk preflight
still checks the whole selected library.

The existing scanner is retained: recursive ICNS discovery, no symlink traversal,
and exclusions for hidden/underscore-prefixed descendants, app bundles, iconsets,
and `_ugly.icns` backup names. A library root itself must not be dot-hidden, an
app bundle, or an iconset. This is a current scanner restriction, not a required
folder layout. Multiple themed variants should use separate library roots or an
explicit file instead of ambiguous copies in a single active library.

## Application locations

```bash
iconforge apply Firefox --app-root "/Volumes/Tools/Applications"
iconforge inspect Firefox --app-root "$HOME/Custom Apps"
iconforge restore Firefox --app-root "$HOME/Custom Apps"
```

`--app-root` is repeatable and supplements the existing roots only for that
invocation. It never changes a test-only environment variable or a saved setting.
The root must exist, must not resolve to `/`, and cannot contain tabs or newlines
because the existing application-record format uses those delimiters. Default
roots include the current directory, `~/Applications`, `/Applications`,
`/System/Applications`, and now `/System/Library/CoreServices`. Search depth remains
two levels, excluding the contents of application bundles.

An explicit `.app` path remains the way to select a particular installation.

## Configuration lifecycle

```bash
iconforge config show
iconforge config path
iconforge config get the-forge
iconforge config unset the-forge
```

`get` prints the explicitly saved value, returning status 1 if it is absent.
`show` prints effective forge/hearth values with their source, including a legacy
fallback or the current directory. `path` prints the preference-file location.

Storage remains `~/.config/iconforge/config.plist`, or an absolute
`$XDG_CONFIG_HOME/iconforge/config.plist`. Plist keys are `the_forge`, `the_hearth`,
and the legacy `default_directory`. Configuration remains structured data and is
never sourced as shell code. No old `.env` file or `.iconforgerc` is executed.

Set resolves relative paths at configuration time and accepts a quoted `~/...`
without `eval`. A destination need not exist yet, but its existing ancestor must
be a directory. The filesystem root, dangling symlinks, empty paths, and multiline
values are rejected. Existing paths are resolved again when used.

Changes preserve other settings, including unknown future preferences. Writes
use a same-directory temporary file, mode 0600, atomic rename, and an exclusive
configuration-update lock. Unset is idempotent and removes only its key; an empty
plist may be removed. A malformed or non-dictionary preference file fails closed
rather than being overwritten by `set`. Inspect or move aside the invalid file
explicitly before recreating preferences. After an interrupted update, a stale
empty `.config.lock` directory may need manual removal after checking that no
configuration writer is running.

There is no automatic migration write. Existing `default-directory` remains a
fallback until an operation-specific preference takes priority. Unsetting one of
the new preferences can reveal that legacy fallback again; `config show` makes
this visible.

## Grammar and refresh

Value options accept both `--name VALUE` and `--name=VALUE`. Short flags remain
separate, not clustered. `--` retains its normal end-of-options behavior. Prefix
leading-dash option values with `./`, or use an absolute path.

```bash
iconforge forge ./art.png Firefox --output="$HOME/icon-work"
iconforge apply Firefox --icon=./Firefox.icns
iconforge apply -- "An App With Spaces"
```

`apply Firefox nuke` is a limited convenience spelling of
`apply Firefox --nuke`. The shorthand is recognized only as the second direct
operand before `--`. `apply Nuke` still targets the app named Nuke. It is not a
command-chain interpreter. In bulk mode, a bare `nuke` can be the library's name;
use `--nuke` to request cache work.

`refresh` and `nuke` invoke the same existing current-user cache operation.
`apply --refresh` and `restore --refresh` are aliases for their `--nuke` flag.
Nothing enables broad cache clearing automatically. Bulk mode performs the
requested refresh once after successful application, not once per item.

Root `-v` remains version; apply `-v` remains verbose. Existing exit codes remain
0 for success, 1 for resolution/validation/execution failure, and 2 for invalid
usage. Existing bulk skip/partial-success semantics remain unchanged.

## Diagnostics and completion

```bash
iconforge doctor
iconforge doctor Finder
iconforge capabilities
iconforge completion zsh
```

Doctor checks backend availability, installed helper executables, and effective
configuration. An optional app inspection reports writability or a system-managed
location. It does not probe by writing, elevate privileges, restart processes,
or change security settings. This is a diagnostic, not a guarantee that an icon
will be visible in every macOS surface.

Completion is emitted, never installed into a user's shell automatically:

```bash
# Bash
source <(iconforge completion bash)

# Zsh, after compinit
source <(iconforge completion zsh)

# Fish
iconforge completion fish | source
```

The completion scripts cover commands, configuration keys, common flags, and
paths. They do not yet enumerate installed application names dynamically.

## Safety and scope

The native custom-icon strategy remains the default. Internal bundle replacement
still requires `--strategy internal-icns`, is never chosen automatically, and
remains unavailable in bulk mode. The existing ICNS validation, transactional
forge publication, internal rollback, and current-user Nuke safeguards are reused.
Dry runs reach those existing validation paths without executing their writes.

Finder's application icon and its special Dock presentation are separate concerns.
Finding Finder under CoreServices does not make either customization supported.
This pass does not disable SIP or Gatekeeper, modify the signed system volume,
remove bundled applications, implement mobile customization, or load third-party
code. See [architecture and next steps](ARCHITECTURE.md).
