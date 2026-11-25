# Building UnRot for iOS / iPadOS

> Status: the iOS project (`app/ios/`) is generated (minimum iOS 15) but has not been built yet. The Dart
> code is shared with the tested Linux version. iPad + Apple Pencil is a natural fit for the pen features.

## 1. Requirements

* A **Mac** with the latest **Xcode** (iOS apps can only be built on macOS); see [macos.md](macos.md) for the
  Xcode/Flutter set-up.
* An iPhone/iPad with iOS 15 or newer, or the iOS Simulator (Xcode → *Settings → Platforms* → install iOS).
* An Apple ID. A free account can install on your own device (re-sign every 7 days). The App Store/TestFlight
  require a paid Apple Developer Program membership.
* CocoaPods only if `flutter doctor` asks for it (`brew install cocoapods`).

```bash
flutter doctor      # "Xcode - develop for iOS and macOS" must be ✓
```

## 2. Get the code

```bash
git clone https://github.com/ChrisJu05/UnRot.git
cd UnRot/app
flutter pub get
```

## 3. Configure signing (once)

1. `open ios/Runner.xcworkspace`
2. Select the **Runner** target → **Signing & Capabilities**.
3. Pick your **Team** and change the **Bundle Identifier** to something unique, e.g. `io.github.<yourname>.unrot`.
4. On the device: *Settings → Privacy & Security → Developer Mode* → on (iOS 16+), and after the first install trust
   the developer under *Settings → General → VPN & Device Management*.

## 4. Run in debug mode

```bash
flutter devices                 # find your device or simulator id
flutter run -d <device-id>
open -a Simulator && flutter run -d ios   # simulator
```

## 5. Build a release

```bash
flutter build ipa --release     # archive for TestFlight / App Store (upload with Xcode Organizer or Transporter)
flutter build ios --release     # app bundle only (install via Xcode)
```

Output: `build/ios/ipa/*.ipa` and `build/ios/archive/Runner.xcarchive`.

## Importing material

*Import files* opens the iOS document picker, so files from *On My iPhone/iPad*, iCloud Drive and other file
providers work. *Paste text* is the fastest way to add notes from other apps.

## Apple Pencil

Pencil strokes have pressure. *Stylus only* (palm rejection) lets your hand rest on the screen while you write, and
*Stylus draws directly on reels* lets you annotate any reel while fingers keep swiping. Use the eraser tool in the
toolbar (the Pencil's double-tap gesture is not mapped yet).

## Using a local AI server (Ollama/LM Studio on your Mac or PC)

iOS blocks plain `http://` and local-network access by default. To use an *OpenAI-compatible* server on your LAN,
add to `ios/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>UnRot connects to your local AI server to generate reels.</string>
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

Cloud providers (Anthropic, OpenAI, Gemini, OpenRouter, …) use HTTPS and need no changes.

## Troubleshooting

| Problem | Fix |
|---|---|
| `No profiles for 'io.github.unrot.unrot' were found` | Change the bundle identifier and pick your team (step 3). |
| `Untrusted Developer` on device | Trust the certificate under *Settings → General → VPN & Device Management*. |
| Pod/SPM resolution errors | `flutter clean && flutter pub get`, then build again (or `cd ios && pod install --repo-update`). |
