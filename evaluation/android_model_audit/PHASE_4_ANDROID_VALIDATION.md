# Phase 4 Android validation

## Toolchain

| Tool | Result |
| --- | --- |
| Flutter | 3.47.9 stable at `$HOME/sdk/flutter`. Matches `sdk: '>=3.4.0 <4.0.0'` |
| Dart | 3.13.7 |
| Java | OpenJDK 21.0.12 at `/usr/bin/java` |
| Android SDK | `$HOME/Android/Sdk`. `flutter doctor` reports the Android toolchain with licenses accepted |
| Platform | `platforms/android-36` |
| Build-tools | `35.0.0` |
| Platform-tools / adb | present, adb 1.0.41 |
| CMake | 3.22.1, installed by the debug build |
| NDK | Flutter asks for `28.2.13676358`. The debug build finished without a separate NDK install step failing |
| Emulator binary | not installed |
| `/dev/kvm` | present, mode `crw-rw----`, group `ssl-cert`. This user cannot open it |

`app/pubspec.yaml` dependency constraints were not changed. The SDK lives outside the repo.

## What ran

- `flutter pub get` had already been run in Phase 3. Phase 4 did not bump direct dependencies.
- `flutter analyze`: no issues.
- `flutter test`: 148 passed.
- `flutter build apk --debug`: succeeded. Artifact `app/build/app/outputs/flutter-apk/app-debug.apk`, 442 MB, gitignored.

## Build failure that was fixed

The first debug build stopped in `:tflite_flutter:compileDebugKotlin`:

`compileDebugJavaWithJavac` targeted 1.8 and `compileDebugKotlin` targeted 21.

That is inside the existing `tflite_flutter` Android code when Gradle runs on JDK 21. `app/android/gradle.properties` now sets `kotlin.jvm.target.validation.mode=warning`. The app module still sets Java and Kotlin to 17. The plugin version was not changed. A second build produced the APK. Flutter also warned that Kotlin Gradle plugin 2.2.20 will need to be at least 2.3.20 later. That upgrade was not done.

## What did not run

- No emulator. KVM is not usable by this user, so a guest would not be hardware-accelerated, and an emulator image was not installed.
- No `adb install`. No device was attached.
- No camera capture, no on-device EXIF check, no on-device inference timing.

Static analysis and a debug APK are not a device pass.

## Status

| Item | Status |
| --- | --- |
| SDK install and debug APK | PARTIALLY VERIFIED |
| `flutter analyze` and `flutter test` | VERIFIED |
| Emulator | BLOCKED. `/dev/kvm` is not writable by this user |
| Device test | BLOCKED. No device |

The debug APK can be copied to a phone. This machine did not install it or exercise the camera.
