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
# optional, voice for "read aloud" (most desktops already have speech-dispatcher):
sudo apt install -y espeak-ng
```

**Fedora**

```bash
sudo dnf install -y git clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel
sudo dnf install -y poppler-utils   # optional
sudo dnf install -y espeak-ng       # optional, read aloud
```

**Arch / Manjaro**

```bash
sudo pacman -S --needed git clang cmake ninja pkgconf gtk3 xz
sudo pacman -S --needed poppler      # optional
sudo pacman -S --needed espeak-ng    # optional, read aloud
```

**Read aloud** on Linux calls `espeak-ng` (preferred, also `espeak`) or speech-dispatcher's `spd-say`. Nothing is
needed at build time; *Settings → Audio* shows which voice was found. eSpeak has voices for German, English and
most other languages. If speech-dispatcher is configured with a nicer voice (e.g. Piper or RHVoice) and espeak-ng
is not installed, that voice is used.

At runtime the file picker uses the **XDG desktop portal** (D-Bus). GNOME, KDE and most desktops ship it.
On minimal window managers, install `xdg-desktop-portal` and a backend such as `xdg-desktop-portal-gtk`.

## 2. Install Flutter

**Recommended: install with git.** This works on every distribution (x64 and ARM) and needs no snap:

```bash
git clone https://github.com/flutter/flutter.git -b stable ~/development/flutter

# make the "flutter" command available in every new terminal
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.bashrc   # zsh users: ~/.zshrc
source ~/.bashrc
```

Alternatively, download the stable Linux archive from <https://docs.flutter.dev/release/archive>, extract it to
`~/development/flutter` and add the same `PATH` line.

Then check the set-up. The first run downloads the Dart SDK and takes a minute:

```bash
flutter --version          # 3.50 or newer, Dart 3.14
flutter doctor             # "Linux toolchain" must be ✓
```

Update later with `flutter upgrade`.

**Snap (Ubuntu only, optional):** `sudo snap install flutter --classic`. If `flutter` is then "not found":

* `/snap/bin` is not on your `PATH` yet: log out and back in, or run `export PATH="$PATH:/snap/bin"`.
* Linux Mint blocks snaps by default, and Fedora/Arch need extra snapd set-up. Use the git install above instead.

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
| `flutter: command not found` | The Flutter `bin` folder is not on your `PATH`. Run `source ~/.bashrc` or open a new terminal; check with `ls ~/development/flutter/bin/flutter`. With snap, see section 2. |
| Colours/gradients look wrong or the window is black (VMs, remote desktops, software OpenGL/llvmpipe) | Start with `UNROT_DISABLE_IMPELLER=1 ./unrot` to use the Skia renderer instead of Impeller. |
| "Import files" does nothing | Install `xdg-desktop-portal` plus `xdg-desktop-portal-gtk` (or `-kde`) and log in again. |
| `CMake Error ... gtk+-3.0` | `libgtk-3-dev` (or your distribution's GTK 3 development package) is missing. |
| A PDF imports with missing text | Install `poppler-utils`; UnRot then falls back to `pdftotext` automatically (*Settings → Data*). Scanned PDFs need OCR, which is not supported yet. |
| *Settings → Audio* says "No voice found" | Install `espeak-ng` (see step 1) and restart UnRot. Check with `espeak-ng "Hallo"` in a terminal. |
| Reels are read but nothing is heard | Check the system volume and output device (PulseAudio/PipeWire); `espeak-ng "test"` must be audible. |
| Requests to the AI provider time out behind a proxy | UnRot respects `HTTPS_PROXY`/`NO_PROXY`. Start it from a shell where these are set. |
