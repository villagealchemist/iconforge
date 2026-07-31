# Releasing Icon Forge

Icon Forge is currently distributed through the `villagealchemist/iconforge` GitHub repository and the separate `villagealchemist/homebrew-iconforge` tap. Homebrew core is a later, independent submission process; publishing a public tap makes the supported install command available immediately.

## Release checklist

1. Start from a clean, reviewed branch and confirm `VERSION` contains the intended semantic version (without a leading `v`).
2. Run `make test`, `make lint`, and `make version`. The last command must print the same version as `VERSION`.
3. Update `README.md` if command behavior, supported macOS requirements, or installation instructions changed.
4. Commit the release changes, merge or push the release commit, and create an annotated tag named `v<version>`.
5. Push the tag and create a GitHub release from it. GitHub's generated source archive is the artifact consumed by Homebrew.
6. Download the exact `v<version>` source tarball from GitHub and calculate its SHA-256:

   ```bash
   curl -L -o iconforge-v<version>.tar.gz https://github.com/villagealchemist/iconforge/archive/refs/tags/v<version>.tar.gz
   shasum -a 256 iconforge-v<version>.tar.gz
   ```

7. In the separate `villagealchemist/homebrew-iconforge` repository, render `Formula/iconforge.rb` using the SHA from step 6:

   ```bash
   /path/to/iconforge/scripts/render-homebrew-formula.sh <version> <sha256> > Formula/iconforge.rb
   brew audit --strict --formula Formula/iconforge.rb
   brew install --build-from-source Formula/iconforge.rb
   brew test iconforge
   ```

8. Commit and push that formula. Verify the public install path in a fresh shell:

   ```bash
   brew tap villagealchemist/iconforge
   brew install villagealchemist/iconforge/iconforge
   iconforge --version
   ```

9. Publish GitHub release notes with the user-visible changes, upgrade instructions, known asset-catalog limitations, and the version/tag.
