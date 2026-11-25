# Build instructions

UnRot is a single [Flutter](https://flutter.dev) code base (in [`../app`](../app)) that targets five platforms.
Pick your platform:

| Platform | Guide | Build host | Status |
|---|---|---|---|
| Linux (x64 / arm64) | [linux.md](linux.md) | Linux | Built and tested |
| Windows 10/11 | [windows.md](windows.md) | Windows | Project generated, not yet built/tested |
| macOS | [macos.md](macos.md) | macOS | Project generated, not yet built/tested |
| iOS / iPadOS | [ios.md](ios.md) | macOS + Xcode | Project generated, not yet built/tested |
| Android | [android.md](android.md) | Linux, macOS or Windows | Project generated, not yet built/tested |

All platforms share the same steps:

1. Install the **Flutter SDK, stable channel, 3.50 or newer** (ships Dart 3.14). Check with `flutter --version`.
2. Install the platform tool chain listed in the platform guide and run `flutter doctor` until the line for
   your platform is green.
3. Get the code and dependencies:
   ```bash
   git clone https://github.com/ChrisJu05/UnRot.git
   cd UnRot/app
   flutter pub get
   ```
4. Run in debug mode with hot reload: `flutter run -d <platform>` (`linux`, `windows`, `macos`, or a device id
   from `flutter devices`).
5. Build a release with `flutter build <platform> --release`.

Run the tests on any desktop host with:

```bash
cd UnRot/app
flutter test      # unit + widget tests (no device needed)
flutter analyze   # static analysis
```

## Notes that apply everywhere

* **AI keys**: UnRot calls the AI provider directly from the device with the key you enter in
  *Settings → AI provider*. Keys are stored in a separate `secrets.json` file inside the app's private data folder
  (readable only by your user on Linux/macOS). Platform keychains can be plugged in later (see
  [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)).
* **Offline mode** works without any key or network connection, which makes it the easiest way to check that a build works.
* **Pen input** uses Flutter's pointer events (`PointerDeviceKind.stylus` / `invertedStylus` with pressure), so
  Apple Pencil, Samsung S Pen, USI pens, Windows Ink and Wacom tablets all use the same code.
* If you change the Flutter version, run `flutter pub upgrade` and `flutter test` before building.
