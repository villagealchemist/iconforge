# 🛠 iconforge — Usage Guide

Convert any image into a pixel-perfect macOS `.icns` file using your terminal.

---

## ⚙️ Basic Syntax

```bash
iconforge [options] <input_image|directory> [output_name]
```

---

## 🧩 Options

| Flag                | Description                                               |
| ------------------- | --------------------------------------------------------- |
| `-o`, `--output`    | Set output directory (default: current working directory) |
| `-k`, `--keep-png`  | Preserve the converted PNG alongside the `.icns`          |
| `-r`, `--recursive` | Recursively process all supported images in a directory   |
| `-h`, `--help`      | Show usage help                                           |
| `--version`         | Print installed version number                            |

---

## 🧪 Supported Formats

Input file types:

* `.png`
* `.jpg`, `.jpeg`
* `.webp`
* `.tiff`, `.tif`
* `.gif`
* `.heic`

---

## 🧙 Examples

### 🔹 Convert a single image

```bash
iconforge assets/logo.png
```

Outputs:

```
./logo/logo.icns
```

### 🔹 Output to custom directory

```bash
iconforge logo.png -o build/icons
```

Outputs:

```
build/icons/logo/logo.icns
```

### 🔹 Rename output

```bash
iconforge logo.png MyIcon
```

Outputs:

```
./MyIcon/MyIcon.icns
```

### 🔹 Batch convert all images in a folder

```bash
iconforge -r ./images -o ./dist/icons
```

Outputs:

```
dist/icons/img1/img1.icns
...
dist/icons/imgN/imgN.icns
```

### 🔹 Keep PNG version

```bash
iconforge logo.webp --keep-png
```

Outputs:

```
./logo/logo.icns
./logo/logo.png
```

---

## 🔍 Interactive Mode

If run with no arguments, `iconforge` enters interactive mode:

```text
🔧 Interactive mode
Input file(s) or directory:
Output directory [./]:
Keep intermediate PNG? (y/N):
Recursive scan (for folders)? (y/N):
```

---

## 🛑 Duplicate Filename Protection

When run in batch mode, iconforge ensures that:

* All base filenames are unique after extensions are stripped
* Conflicts will abort the run with a clear error

---

## 📦 Output Structure

Generated icons are written to:

```
<output_dir>/<base_name>/<base_name>.icns
```

If `--keep-png` is enabled:

```
<output_dir>/<base_name>/<base_name>.png
```

---

## 💡 Tips

* Works out-of-the-box on macOS (requires `sips`, `iconutil`, `find`)
* Supports relative or absolute paths
* Automatically creates output directories if needed

---

## 🧹 Cleaning

Temporary files (e.g., converted PNGs in `/tmp`) are auto-cleaned unless you specify `--keep-png`.

---

For full test coverage and developer commands, see the [README](./README.md) or run:

```bash
make help
```

Forge onward 🧪
