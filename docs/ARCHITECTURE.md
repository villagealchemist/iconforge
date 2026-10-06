# Architecture: keep policy separate from the platform

## Implemented in this pass

```text
iconforge.sh
  dispatch and root help
    -> cli.sh
       public argument normalization and resolution policy
         -> config.sh
            independent purpose-specific directory preferences
         -> backend.sh
            built-in macOS capability and execution boundary
              -> existing discovery, matching, and library scanner
              -> existing forge/apply/restore/nuke orchestration
              -> Go image processor + Objective-C/AppKit helper
```

The interface boundary is deliberately small. `backend_resolve_target` exposes a
resolved target plus normalized match keys. `backend_scan_icons` exposes parallel
file/key arrays. The CLI selects exactly one icon for a direct request or hands an
explicit library to bulk execution. Execution functions receive resolved argv,
not an executable command string or implicitly coupled default directory.

The adapter delegates to the existing `cmd_*` engine functions. These still parse
a canonical internal argv and retain their existing validation/rollback logic.
This is an incremental separation, not a claim that all shell orchestration has
already been rewritten into a fully portable domain library. Backend selection
currently recognizes macOS only. Preferences still use macOS plist tools. Portable
policy tests exercise the boundary with inert functions on Linux or macOS.

The root dispatcher does not infer a platform from a user's application name and
never loads a plugin path from the environment or preference file. The built-in
capability report distinguishes implemented macOS operations from future work.

## Guardrails worth preserving

Explicit app/file paths beat convenience lookup. Ambiguity is data to report, not
permission to choose the first filesystem result. Bulk selection stays explicit.
Dry-run uses the execution engine's validation path. Native custom icons and
internal signed-content mutation remain distinct strategies. Configuration updates
preserve unrelated keys and cannot silently repair corruption by erasing it.

An inferred path must not imply permission escalation, application deletion, code
re-signing, or machine-wide security changes. UI friendliness does not require any
of those shortcuts.

## Next extensions, not shipped features

Before adding multiple backends, promote the current arrays/argv into a versioned
request/plan/result model with stable error identifiers. Keep it independent of
Bash and UI code, likely alongside the existing Go processing packages. A GUI or
mobile frontend can then consume the same orchestration model rather than invoking
interactive commands and parsing human output. The current adapter boundary gives
that extraction a specific location; it is not yet that API.

Treat these as separate capabilities:

1. Artwork processing: decode, crop/fit, resize, and normalize.
2. Packaging: produce ICNS, asset-catalog files, Android resources, or other formats.
3. Installation/customization: apply or restore an artifact on a particular system.

A backend may support export without supporting replacement of another app's icon.
That distinction is essential for an honest mobile offering. Mobile platform rules
and viable application/customization methods need platform-specific verification
before implementation; this branch makes no mobile compatibility claims.

Useful next increments are machine-readable plans/results, remembered explicit
application mappings, named library profiles, dynamic app completion, a proper
batch review UI, and preservation of a pre-existing native custom icon for undo.
The current native strategy replaces that previous custom icon and does not back
it up. Persistent mappings should be explicit user decisions, keyed by stable app
identity and accompanied by duplicate-installation checks, not automatically saved
fuzzy matches. Profiles should be data, not shell snippets.

Avoid a plugin marketplace, auto-executed hooks, or an elaborate abstract hierarchy
before a second real backend exists. Add a capability, tests, and an honest failure
mode for unsupported operations first.

## Verification

`tests/test-cli-policy.sh` exercises the public policy using inert backend functions
without macOS or user settings. `tests/test-hearth.sh` adds macOS integration against
disposable application fixtures, including direct/bulk preview, real native apply
and restore, configuration isolation, and ambiguity rejection. The existing engine
regression tests remain in the suite. No new runtime dependency or binary is added.

Run on macOS before merging/releasing:

```bash
make lint
make test
make build-all
```

The portable policy suite is also runnable independently:

```bash
bash tests/test-cli-policy.sh
```
