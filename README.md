<p align="center">
  <img src="assets/iconforge_logo.png" alt="iconforge logo" width="200"/>
</p>

`iconforge` is a macOS icon workflow CLI. It forges `.icns` files from source images, inspects how an app bundle declares its icon, applies a custom icon into an app bundle, restores the original icon backup, and clears the user-level icon caches that usually need to be refreshed afterward.

## Commands

```bash
iconforge forge <input> [output_name] [options]
iconforge inspect <app>
iconforge apply <app> --icon <file.icns> [--nuke] [--force-asset] [--dry-run]
iconforge restore <app> [--nuke] [--dry-run]
iconforge nuke [app] [--dry-run]
```

Legacy forge-style usage still works:

```bash
iconforge logo.png -o dist/icons
```

That is routed internally to `iconforge forge`.

## Typical flows

Forge a new icon:

```bash
iconforge forge assets/logo.png BrandMark -o dist
```

Inspect an app bundle before touching it:

```bash
iconforge inspect "/Applications/Visual Studio Code.app"
```

Apply a custom icon, re-sign the app, and refresh caches:

```bash
iconforge apply "/Applications/MyApp.app" --icon dist/BrandMark.icns --nuke
```

Restore the original backed-up icon:

```bash
iconforge restore "/Applications/MyApp.app" --nuke
```

Clear icon caches directly:

```bash
iconforge nuke
```

## What `apply` does

`apply` is the app-bundle mutation path:

1. Resolve the app bundle and target loose `.icns`
2. Back up the original icon as `*_ugly.icns` if that backup does not exist yet
3. Replace the bundle icon with your supplied `.icns`
4. Touch the app bundle and `Info.plist`
5. Re-sign the bundle with ad hoc signing by default
6. Optionally clear icon caches with `--nuke`

Use `--dry-run` to preview those actions without changing files.

## Asset catalog limitations

Many modern apps, especially Chromium/Electron-style bundles, advertise their icon through `CFBundleIconName` plus `Assets.car`. In that configuration, replacing a loose `.icns` often does nothing visible.

`iconforge inspect` calls this out explicitly. `iconforge apply` refuses by default when an app looks asset-catalog-backed. If you still want to try the loose replacement path anyway, pass `--force-asset`.

That override only means “attempt the bundle replacement anyway”. It does not guarantee the app will display the new icon.

## `nuke` behavior

`iconforge nuke` focuses on the practical user-level steps that usually matter on macOS:

1. Remove user-accessible icon cache files under `~/Library/Caches` and `/private/var/folders/...`
2. Touch the target app bundle when one is supplied
3. Restart Finder, Dock, and `iconservicesagent`
4. Refresh Quick Look cache when `qlmanage` is available

It does not use privileged deletion or destructive system-wide resets.

## Safety notes

- Modifying app bundles can invalidate signatures until the bundle is re-signed.
- Ad hoc signing is the default after `apply` and `restore`; use `--no-resign` only if you know you want to handle signing yourself.
- System apps and managed apps may reject modification or be restored by the OS or MDM tooling.
- Asset-catalog-backed apps may ignore loose `.icns` replacement even when the file copy succeeds.

## Development

```bash
make build
make test
make lint
```

The Go binary in `iconforge-processor/` remains responsible for image decoding, PNG conversion, and resizing. The macOS bundle operations stay in shell.
