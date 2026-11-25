# Building UnRot on macOS

> Status: the macOS project (`app/macos/`) is generated and configured (sandbox entitlements for outgoing network
> requests and user-selected files are already set) but has not been built yet. The Dart code is shared with the
> tested Linux version.

## 1. Requirements

* macOS 14 (Sonoma) or newer is recommended. The app itself targets macOS 12+.
* **Xcode** from the Mac App Store (latest version), then:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept
```

* Some plugins may still need **CocoaPods**. Install it only if `flutter doctor` asks for it:
  `brew install cocoapods`.

## 2. Install Flutter

* With Homebrew: `brew install --cask flutter`, **or**
* manually: download the latest **stable** macOS archive (Apple Silicon or Intel) from
  <https://docs.flutter.dev/release/archive>, extract it to `~/development/flutter` and add
  `~/development/flutter/bin` to your `PATH`.

```bash
flutter --version   # 3.50 or newer
flutter doctor      # "Xcode - develop for iOS and macOS" must be ✓
```

## 3. Get the code

```bash
git clone https://github.com/ChrisJu05/UnRot.git
cd UnRot/app
flutter pub get
```

## 4. Run in debug mode

```bash
flutter run -d macos
```

## 5. Build a release

```bash
flutter build macos --release
```

The app bundle is `build/macos/Build/Products/Release/UnRot.app`. Drag it to `/Applications`.

### Signing and distribution

* For your own Mac nothing else is needed (first start: right-click → *Open*).
* For distribution, open `app/macos/Runner.xcworkspace` in Xcode, select the *Runner* target → *Signing &
  Capabilities*, choose your team, change the bundle identifier (default `io.github.unrot.unrot`) and archive
  (*Product → Archive*). Outside the App Store, sign with a *Developer ID* certificate and notarise with
  `xcrun notarytool`.

## 6. Tests

```bash
flutter analyze
flutter test
```

## Entitlements (already configured)

`app/macos/Runner/DebugProfile.entitlements` and `Release.entitlements` contain:

* `com.apple.security.app-sandbox`: the app runs sandboxed
* `com.apple.security.network.client`: needed to call the AI provider APIs
* `com.apple.security.files.user-selected.read-only`: needed by the file picker to import material

## Where data is stored

Sandboxed: `~/Library/Containers/io.github.unrot.unrot/Data/Library/Application Support/io.github.unrot.unrot/`
(shown in *Settings → Data*).

## Pen support

Wacom/graphics tablets and an iPad used as a tablet via Sidecar (Apple Pencil) send stylus events with pressure.

## Troubleshooting

| Problem | Fix |
|---|---|
| AI requests fail with "Operation not permitted" | Make sure `com.apple.security.network.client` is still in both entitlements files. |
| Import dialog does not open | `com.apple.security.files.user-selected.read-only` must be present. |
| `pdftotext` fallback is not used | The sandbox blocks external tools, so the built-in PDF reader is used. This is expected. |
| CocoaPods errors after a Flutter upgrade | `cd app/macos && pod repo update && pod install`, or `flutter clean && flutter pub get`. |
