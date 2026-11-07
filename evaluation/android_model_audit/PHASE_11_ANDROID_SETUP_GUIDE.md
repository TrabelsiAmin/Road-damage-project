# Phase 11 Android setup guide

Neither an emulator nor a physical device has passed. This host is Linux, not an Apple Silicon Mac. This phase opened `/dev/kvm` and got `EACCES` (errno 13). `adb devices` printed only `List of devices attached`. No APK was installed.

Values read from the existing arm64 release APK with `aapt dump badging` and from `flutter --version` on 2026-11-07:

| Field | Value |
| --- | --- |
| Flutter | 3.47.9 stable, revision c197ca5199, Dart 3.13.7 |
| applicationId | `com.tariqmap.app` |
| versionName | `0.1.0` (`pubspec.yaml` is `0.1.0+1`) |
| arm64 versionCode | 2001 |
| minSdk | 24 |
| targetSdk | 36 |
| compileSdk | 36 |
| ABI of the release APK below | `arm64-v8a` only |

## Artifact

Present on this machine:

- `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` — 162,451,078 bytes
- `/tmp/Road-damage-project/app/build/app/outputs/bundle/release/app-release.aab` — 231,089,677 bytes

The same APK size is also at `app/build/app/outputs/apk/release/app-arm64-v8a-release.apk`. Copy the arm64 APK to the Mac. Do not install the armeabi-v7a or x86_64 split on Apple Silicon.

If that file is missing, rebuild from `app/` with the Android SDK installed. This does not create an upload key:

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
flutter build apk --release --split-per-abi
```

The arm64 output is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

The APK on this machine is signed `CN=Android Debug`. That is expected until the signing guide is followed. It can still be installed on an emulator or a device that allows the debug certificate.

## Emulator on an Apple Silicon Mac

These steps have not been executed.

1. Install Android Studio from the official site. Open SDK Manager.
2. Install Android SDK Platform 36. The app's minSdk is 24 and its targetSdk and compileSdk are 36.
3. Install an **arm64-v8a** Google APIs system image for API 36. Do not use an x86_64 image. The Mac hypervisor boots this AVD. This container's `/dev/kvm` is irrelevant there.
4. Device Manager → Create Virtual Device → a phone profile → that arm64 API 36 image. Start it.
5. Confirm the ABI:

```bash
adb devices -l
adb shell getprop ro.product.cpu.abi
```

The second command must print `arm64-v8a`.

6. Install and launch:

```bash
adb install -r app-arm64-v8a-release.apk
adb shell monkey -p com.tariqmap.app -c android.intent.category.LAUNCHER 1
adb logcat -d -s flutter,AndroidRuntime,tflite
```

7. Scenarios, all NOT EXECUTED here:

- Camera: grant or deny when prompted. The manifest requests `CAMERA` and does not require the camera feature. Emulator camera may be a virtual scene. A missing camera is a blocked camera check, not a pass.
- Image inference: pick a gallery image. The default build loads `road_damage.tflite` only. It does not load RoadSense unless the APK was built with `--dart-define=USE_ROADSENSE_MODEL=true`. The existing APK was not built with that flag.
- Offline sync: enable airplane mode, capture or queue an item, then restore the network. Do not point the app at production Supabase for this check.

## Physical device

Separate from the emulator. Also NOT EXECUTED.

1. Enable Developer options and USB debugging.
2. `adb devices -l` must show the phone, not only an emulator.
3. `adb shell getprop ro.product.cpu.abi` should be `arm64-v8a` for this APK. A 32-bit-only phone needs `app-armeabi-v7a-release.apk` instead. That split was built in Phase 6/7 and is not the Apple Silicon artifact.
4. Use the same `adb install`, `monkey`, and `logcat` commands as above.
5. Repeat camera, gallery inference, airplane-mode queue, and network restore on the phone. An emulator pass would not count as this pass.

## What a logcat pass would have to show

No `FATAL EXCEPTION`. No missing `libflutter.so` or `libtensorflowlite_jni.so`. No failure to copy `assets/models/road_damage.tflite`. This document does not claim those lines were seen.
