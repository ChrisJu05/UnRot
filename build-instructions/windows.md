# Building UnRot on Windows

> Status: the Windows project (`app/windows/`) is generated and configured but has not been built yet. The
> Dart code is shared with the tested Linux version; please report problems.

## 1. Requirements

* Windows 10 or 11, 64-bit (x64; Windows on ARM works with an ARM64 Flutter SDK).
* [Git for Windows](https://git-scm.com/download/win).
* **Visual Studio 2022 or newer** (Community edition is fine; *not* VS Code) with the workload
  **"Desktop development with C++"**. Keep the default components (MSVC compiler, C++ CMake tools for Windows, and
  a Windows 10/11 SDK).
* **Developer Mode** enabled (Flutter plugins use symlinks): run `start ms-settings:developers` and switch it on.
* **NuGet CLI** (`nuget.exe`) on the `PATH`: the text-to-speech plugin (read aloud) downloads C++/WinRT with it
  during the build. Install it with `winget install Microsoft.NuGet`, or download `nuget.exe` from
  <https://www.nuget.org/downloads> into a folder that is on your `PATH`, and check with `nuget help`.

## 2. Install Flutter

1. Download the latest **stable** Windows zip from <https://docs.flutter.dev/release/archive> and extract it to a
   path without spaces or special permissions, e.g. `C:\dev\flutter` (not `C:\Program Files`).
2. Add `C:\dev\flutter\bin` to your user `PATH` (Start → "Edit environment variables for your account").
3. In a new PowerShell:

```powershell
flutter --version     # 3.50 or newer
flutter doctor        # "Visual Studio - develop Windows apps" must be ✓
```

## 3. Get the code

```powershell
git clone https://github.com/ChrisJu05/UnRot.git
cd UnRot\app
flutter pub get
```

## 4. Run in debug mode

```powershell
flutter run -d windows
```

## 5. Build a release

```powershell
flutter build windows --release
```

The app is in `build\windows\x64\runner\Release\`. Ship **the whole folder** (`unrot.exe`, `flutter_windows.dll`,
plugin DLLs and the `data\` folder). Machines without Visual Studio may need the
[Microsoft Visual C++ Redistributable](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist) (x64).

Files passed on the command line are imported on start, so you can associate file types with `unrot.exe` or drag
files onto it:

```powershell
.\build\windows\x64\runner\Release\unrot.exe C:\Users\me\Documents\script.pdf
```

### Optional: installer

* **MSIX** (Microsoft Store or sideloading): add the [`msix`](https://pub.dev/packages/msix) dev dependency and run
  `dart run msix:create`.
* **Classic installer**: point [Inno Setup](https://jrsoftware.org/isinfo.php) at the Release folder.

## 6. Tests

```powershell
flutter analyze
flutter test
```

## Where data is stored

`%APPDATA%\io.github.unrot\UnRot\` (the exact path is shown in *Settings → Data*). `secrets.json` in that
folder holds your API keys. Set the environment variable `UNROT_DATA_DIR` to use another folder.

## Pen support

Windows Ink pens (Surface Pen, Wacom, other N-trig/AES devices) are reported as stylus with pressure. The eraser end
erases, and *Settings → Pen & stylus → Stylus only* enables palm rejection on touch screens.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Building with plugins requires symlink support` | Enable Developer Mode (see requirements). |
| `nuget.exe not found. Please install it.` | Install the NuGet CLI (see requirements) and open a new terminal. |
| No sound when reading aloud | Read aloud uses the Windows voices (*Settings → Time & language → Speech*). Install a German or English voice there if the reel's language has none. |
| `Unable to find suitable Visual Studio toolchain` | Install the "Desktop development with C++" workload, then rerun `flutter doctor`. |
| PDF text is missing | Optional: install [poppler for Windows](https://github.com/oschwartz10612/poppler-windows/releases), add its `bin` folder to `PATH`, and keep *Settings → Data → Use system pdftotext* on. |
| Windows Defender SmartScreen warns on first start | Expected for unsigned builds; sign the exe/MSIX with a code-signing certificate for distribution. |
