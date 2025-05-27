<p align="center">
  <img src="assets/iconforge_logo.png" alt="iconforge logo" width="200"/>
</p>

**Convert any image into a macOS `.icns` icon bundle in seconds — from the terminal.**

Built with love by [@villagealchemist](https://github.com/villagealchemist)

MIT Licensed • Type-safe Bash • 100% test-covered

---

## ⚡️ Features

* 🔧 Convert `.png`, `.jpg`, `.jpeg`, `.webp`, `.gif`, `.tiff`, `.heic` into `.icns`
* 📦 Generates Apple-compatible `.iconset` and `.icns` from any image
* 🖼 Recursively batch convert folders
* 🗂 Optional PNG preservation with `--keep-png`
* 📁 Custom output directories
* 📜 Interactive CLI prompts if no args given
* ✅ Full test suite with `make test`
* 🧰 Developer tooling via `Makefile`
* 🔪 Written in POSIX-compatible Bash (macOS-safe)

---

## 🚀 Installation

Run the install script:

```bash
make install
```

This:

* Installs `bin/iconforge.sh` to `/usr/local/bin/iconforge`
* Makes it executable
* Verifies system dependencies (`sips`, `iconutil`, `find`)
* Optionally installs them if missing

To uninstall:

```bash
make uninstall
```

---

## 🧪 Usage
For full CLI flag reference and examples, see the [Usage Guide](./docs/usage.md).

```bash
iconforge [options] <input_image|directory> [output_name]
```

### Options

| Flag                | Description                                       |
| ------------------- | ------------------------------------------------- |
| `-o`, `--output`    | Output directory (default: current directory)     |
| `-k`, `--keep-png`  | Keep the resized `.png` alongside the `.icns`     |
| `-r`, `--recursive` | Recursively scan a directory for supported images |
| `-h`, `--help`      | Show help message                                 |
| `--version`         | Show installed iconforge version                  |

### Interactive Mode

If run without arguments, iconforge will guide you through:

```
🔧 Interactive mode
Input file(s) or directory:
Output directory [./]:
Keep intermediate PNG? (y/N):
Recursive scan (for folders)? (y/N):
```

---

## 📁 Example

```bash
iconforge assets/logo.png -o dist/icons -k
```

Creates:

```
dist/icons/logo/
🔹 logo.icns
🔹 logo.png
```

---

## 🔎 Developer Commands

```bash
make test           # Run full test suite
make test-verbose   # Show all logs during tests
make bump           # Prompt and update version in iconforge.sh
make release        # Tag and push a release (no file changes)
make clean          # Remove all tmp/ test artifacts
make install        # Install iconforge globally
make uninstall      # Uninstall the script
```

---

## 🔬 Tests

All tests live in `/tests`. Covered cases include:

* Single image conversion
* Recursive batch folders
* Duplicate filename rejections
* Invalid input handling
* Unwritable output paths
* Integration with version overrides

Run them all:

```bash
make test
```

## 📄 License

MIT © [villagealchemist](https://github.com/villagealchemist)

---
