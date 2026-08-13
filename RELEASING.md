# Releasing Icon Forge

An Icon Forge release coordinates two repositories:

- `villagealchemist/iconforge` owns the source tag, generated source archive, version, tests, documentation, and formula template.
- `villagealchemist/homebrew-iconforge` owns the published tap formula.

The repositories can drift independently, so do not describe a 2.x Homebrew install as current until the tap formula has been updated and tested against the matching source tag.

## Release checklist

1. Start from a clean, reviewed branch. Confirm that `VERSION` contains the intended `MAJOR.MINOR.PATCH` value without a leading `v`, and that the Go module's toolchain requirement is intentional.

2. Build and validate the release tree:

   ```bash
   make test
   make lint
   make version
   make build-all
   git diff --check
   git status --short
   ```

   `make lint` skips ShellCheck when it is unavailable and checks Go formatting without modifying files. A release check is not complete if ShellCheck was skipped.

3. Confirm that the release binaries were produced for both supported macOS architectures:

   ```bash
   file iconforge-processor-darwin-amd64
   file iconforge-processor-darwin-arm64
   file iconforge-native-icon-darwin-amd64
   file iconforge-native-icon-darwin-arm64
   ```

4. Exercise the public help and version surfaces against `VERSION`:

   ```bash
   ./iconforge.sh --version
   ./iconforge.sh --help
   ./iconforge.sh forge --help
   ./iconforge.sh inspect --help
   ./iconforge.sh apply --help
   ./iconforge.sh restore --help
   ./iconforge.sh refresh --help
   ```

5. If manually testing icon mutation, use only a disposable copied bundle such as `~/Applications/Google Chrome IconForge Test.app`. Verify apply, helper test, restore, and final helper-test failure on the copy. Never use a live installed browser for release smoke tests.

   For 2.0.1, also verify that automatic apply reports `native`, creates no `*_ugly.icns` backup, and leaves the copied
   bundle's signature identity unchanged. Forge a test icon, unpack it with `iconutil -c iconset`, and require all ten
   standard filenames before release.

6. Audit `README.md`, `docs/USAGE.md`, installed help, and the Homebrew description for new commands, options, formats, dependencies, compatibility names, safety behavior, and internal links. Validate every command example against the release tree.

   Confirm that protected-bundle dry runs report `needs-authorization` without prompting, and that nested applications such as Adobe Photoshop are matched at their inner `.app` path.

7. Commit the reviewed release changes, merge or push the release commit, and create an annotated tag named `v<version>`. Push the tag and create a GitHub release from it. GitHub's generated source archive is the Homebrew source artifact.

8. Download that exact tagged archive and calculate its SHA-256:

   ```bash
   curl -L -o iconforge-v<version>.tar.gz https://github.com/villagealchemist/iconforge/archive/refs/tags/v<version>.tar.gz
   shasum -a 256 iconforge-v<version>.tar.gz
   ```

9. In the source repository, render the formula with the release version and checksum:

   ```bash
   ./scripts/render-homebrew-formula.sh <version> <sha256> > /tmp/iconforge.rb
   ruby -c /tmp/iconforge.rb
   ```

10. Copy the rendered formula to `Formula/iconforge.rb` in the separate tap repository. Review the full diff to confirm that it builds and installs the Go processor, native AppKit helper, Bash libraries, entry point, and `VERSION` from the same release.

11. With Homebrew's installed tap checkout pointing at the candidate tap repository, validate the formula and exercise a
    real forge operation through the installed public launcher. A version-only check is insufficient because it does not
    load the Go processor:

   ```bash
   brew style Formula/iconforge.rb
   brew audit --strict villagealchemist/iconforge/iconforge
   brew reinstall --build-from-source villagealchemist/iconforge/iconforge
   brew test villagealchemist/iconforge/iconforge
   iconforge --version
   rm -rf /tmp/iconforge-release-smoke
   iconforge forge /path/to/iconforge/assets/iconforge-logo.png --output /tmp/iconforge-release-smoke
   test -f /tmp/iconforge-release-smoke/iconforge-logo.icns
   ```

12. Commit and push the tested tap formula. Verify the public path in a fresh shell:

   ```bash
   brew uninstall iconforge
   brew untap villagealchemist/iconforge
   brew tap villagealchemist/iconforge
   brew install villagealchemist/iconforge/iconforge
   iconforge --version
   rm -rf /tmp/iconforge-release-smoke
   iconforge forge /path/to/iconforge/assets/iconforge-logo.png --output /tmp/iconforge-release-smoke
   test -f /tmp/iconforge-release-smoke/iconforge-logo.icns
   brew test villagealchemist/iconforge/iconforge
   ```

13. Publish release notes with user-visible changes, upgrade guidance, macOS and toolchain requirements, updater and Finder-custom-icon caveats, and the exact version and tag.
