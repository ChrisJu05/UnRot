# Building UnRot for Android

> Status: the Android project (`app/android/`) is generated and configured (including the `INTERNET` permission
> needed for AI requests in release builds) but has not been built yet. The Dart code is shared with the tested
> Linux version. Android can be built from Linux, macOS or Windows.

## 1. Requirements

* **Android Studio** (latest stable) from <https://developer.android.com/studio>. It bundles a JDK and the SDK
  manager. In *Settings → Languages & Frameworks → Android SDK* install:
  * an Android SDK Platform (latest),
  * *SDK Tools*: Android SDK Build-Tools, Android SDK Command-line Tools, Android SDK Platform-Tools,
    Android Emulator.
* Optional: Android Studio's *Flutter* plugin.
* A phone/tablet with **USB debugging** (Settings → About → tap *Build number* 7× → Developer options → USB
  debugging), or an emulator (Android Studio → *Device Manager*).

## 2. Install Flutter

Follow the Flutter step of your host OS ([linux.md](linux.md), [windows.md](windows.md), [macos.md](macos.md)), then:

```bash
flutter doctor --android-licenses   # accept all
flutter doctor                      # "Android toolchain" must be ✓
```

If the SDK is not found: `flutter config --android-sdk /path/to/Android/Sdk`.

## 3. Get the code

```bash
git clone https://github.com/ChrisJu05/UnRot.git
cd UnRot/app
flutter pub get
```

## 4. Run in debug mode

```bash
flutter devices
flutter run -d <device-id>
```

## 5. Build a release

```bash
flutter build apk --release          # build/app/outputs/flutter-apk/app-release.apk  (sideload)
flutter build apk --split-per-abi    # smaller APKs per CPU architecture
flutter build appbundle --release    # build/app/outputs/bundle/release/app-release.aab  (Google Play)
```

Install an APK on a connected device with `flutter install` or `adb install build/app/outputs/flutter-apk/app-release.apk`.

### Release signing

The template signs release builds with the debug key, which is fine for personal use. For Play Store uploads, create
a keystore:

```bash
keytool -genkey -v -keystore ~/unrot-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias unrot
```

then create `app/android/key.properties` (do **not** commit it):

```properties
storePassword=...
keyPassword=...
keyAlias=unrot
storeFile=/home/you/unrot-release.jks
```

and reference it in `app/android/app/build.gradle.kts` as described in
<https://docs.flutter.dev/deployment/android#configure-signing-in-gradle>. Also change `applicationId`
(`io.github.unrot.unrot`) to your own id before publishing.

## Pen support

Samsung S Pen, USI pens (Chromebooks, Lenovo, …) and other active styluses are reported as stylus with pressure.
The stylus button erases, *Stylus only* enables palm rejection, and *Stylus draws directly on reels* lets you
annotate reels while fingers keep swiping.

## Using a local AI server (Ollama/LM Studio)

* From the **emulator**, your computer's `localhost` is `http://10.0.2.2:11434/v1`.
* From a **phone**, use your computer's LAN address, e.g. `http://192.168.1.20:11434/v1` (make the server listen on
  the LAN, e.g. `OLLAMA_HOST=0.0.0.0`).
* Android blocks plain `http://` traffic in release builds. For a local server, add
  `android:usesCleartextTraffic="true"` to the `<application>` tag in `app/android/app/src/main/AndroidManifest.xml`
  (or a network security config that allows only your server). Cloud providers use HTTPS and need nothing.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Android license status unknown` | `flutter doctor --android-licenses` |
| Gradle/JDK version errors | Use the JDK bundled with Android Studio: `flutter config --jdk-dir "<Android Studio>/jbr"` |
| AI works in debug but not in release | The `INTERNET` permission must be in `src/main/AndroidManifest.xml` (already added). |
| `Cleartext HTTP traffic not permitted` | See "Using a local AI server" above. |
