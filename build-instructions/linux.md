# Building UnRot on Linux

The Linux desktop version is the reference platform: it was built and tested with Flutter 3.50.1 on
Ubuntu 24.04 (x64).

## 1. Install the tool chain

**Ubuntu / Debian / Mint / Pop!_OS**

```bash
sudo apt update
sudo apt install -y git curl unzip xz-utils clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++-12-dev
# optional, improves import of unusual PDFs:
sudo apt install -y poppler-utils
```

**Fedora**

```bash
sudo dnf install -y git clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel
sudo dnf install -y poppler-utils   # optional
```

**Arch / Manjaro**

```bash
sudo pacman -S --needed git clang cmake ninja pkgconf gtk3 xz
sudo pacman -S --needed poppler      # optional
```

At runtime the file picker uses the **XDG desktop portal** (D-Bus). GNOME, KDE and most desktops ship it.
On minimal window managers, install `xdg-desktop-portal` and a backend such as `xdg-desktop-portal-gtk`.

## 2. Install Flutter

Choose one:

* Snap: `sudo snap install flutter --classic`
* Manual: download the latest **stable** Linux archive from <https://docs.flutter.dev/release/archive>, extract it
  (e.g. to `~/development/flutter`) and add `~/development/flutter/bin` to your `PATH`.

Then check the set-up:

```bash
flutter --version          # 3.50 or newer, Dart 3.14
flutter doctor             # "Linux toolchain" must be ✓
```

## 3. Get the code

```bash
git clone https://github.com/ChrisJu05/UnRot.git
cd UnRot/app
flutter pub get
```

## 4. Run in debug mode

```bash
flutter run -d linux
```

Press `r` for hot reload and `R` for hot restart. You can pass files to import on start:

```bash
flutter run -d linux --dart-entrypoint-args ~/Documents/lecture-notes.pdf
```

## 5. Build a release

```bash
flutter build linux --release
```

The result is the folder `build/linux/x64/release/bundle/` (`arm64` on ARM machines). Copy **the whole folder**:
it contains the `unrot` executable, `lib/` and `data/`. Start it with:

```bash
./build/linux/x64/release/bundle/unrot                       # normal start
./build/linux/x64/release/bundle/unrot script.pdf book.epub  # imports the files on start
```

### Optional: add a menu entry with "Open with UnRot"

```bash
mkdir -p ~/.local/opt && cp -r build/linux/x64/release/bundle ~/.local/opt/unrot
cat > ~/.local/share/applications/io.github.unrot.unrot.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=UnRot
Comment=Learn your own material as short interactive reels
Exec=sh -c '$HOME/.local/opt/unrot/unrot "$@"' unrot %F
Terminal=false
Categories=Education;
MimeType=application/pdf;application/epub+zip;text/plain;text/markdown;application/vnd.openxmlformats-officedocument.wordprocessingml.document;
EOF
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

## 6. Tests

```bash
flutter analyze
flutter test
```

## Where data is stored

`~/.local/share/io.github.unrot.unrot/` contains imported sources, generated reels, progress and settings (JSON),
plus `secrets.json` (permissions `0600`) with your API keys. Set `UNROT_DATA_DIR=/some/folder` to use another
location (handy for testing).

## Pen and tablet support

Wacom and other tablets work through GTK. Strokes, the eraser end of the stylus and "stylus only" palm rejection
are supported. Whether pressure is available depends on the tablet driver (`libinput`/`xf86-input-wacom`). Test
it in *Settings → Pen & stylus → Test area*.

## Troubleshooting

| Problem | Fix |
|---|---|
| Colours/gradients look wrong or the window is black (VMs, remote desktops, software OpenGL/llvmpipe) | Start with `UNROT_DISABLE_IMPELLER=1 ./unrot` to use the Skia renderer instead of Impeller. |
| "Import files" does nothing | Install `xdg-desktop-portal` plus `xdg-desktop-portal-gtk` (or `-kde`) and log in again. |
| `CMake Error ... gtk+-3.0` | `libgtk-3-dev` (or your distribution's GTK 3 development package) is missing. |
| A PDF imports with missing text | Install `poppler-utils`; UnRot then falls back to `pdftotext` automatically (*Settings → Data*). Scanned PDFs need OCR, which is not supported yet. |
| Requests to the AI provider time out behind a proxy | UnRot respects `HTTPS_PROXY`/`NO_PROXY`. Start it from a shell where these are set. |
