# Phase 6 Android runtime

This machine is a remote Linux container. It is not an Apple Silicon Mac. `/dev/kvm` is `crw-rw---- root:ssl-cert`. The user `ubuntu` is not in `ssl-cert`. The emulator was not started. No claim is made that KVM can be fixed on macOS from here. No emulator test passed. No physical device test passed.

## Emulator status

BLOCKED. An ARM64 system image was not installed and was not booted. The debug APK was not installed on an emulator.

## Which APK an Apple Silicon emulator should use

Use the arm64-v8a package.

- Release check: `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (`native-code: arm64-v8a`, versionCode 2001). Copy it to the Mac. Do not install `app-armeabi-v7a-release.apk` or `app-x86_64-release.apk` on an Apple Silicon emulator.
- The fat debug APK also contains `arm64-v8a` libraries, so Android Studio can install `app-debug.apk` on an arm64 AVD. It is a debug build (debuggable, Vulkan validation layer, Dart kernel). It is the wrong artifact for a release-size check.
- The Apple Silicon emulator uses the Mac hypervisor. It does not use this container's `/dev/kvm`.

## Android Studio steps (Apple Silicon Mac)

1. Install Android Studio from the official site. Open SDK Manager and install Android SDK Platform 36 (this app's `targetSdk` and `compileSdk` are 36; `minSdk` is 24).
2. Install an **arm64-v8a** system image for API 36, Google APIs. Do not install an x86_64 image for this check.
3. Device Manager → Create Device → a phone profile → that arm64 API 36 image. Finish and start the AVD. Confirm the emulator shows `arm64` in the extended controls or via `adb shell getprop ro.product.cpu.abi` printing `arm64-v8a`.
4. `adb install -r app-arm64-v8a-release.apk` for the release artifact, or `adb install -r app-debug.apk` for the fat debug build. Then run the checklist below on that AVD. A second pass on a physical phone is still required before Play.

## Runtime checklist

Unit tests are not device tests. "Automated test" means a host `flutter test` or Python test that covers the logic, not an installed APK.

| Item | Emulator | Device | Automated test | Notes |
| --- | --- | --- | --- | --- |
| Install | NOT EXECUTED | NOT EXECUTED | NOT EXECUTED | APKs exist and `aapt` reads them. Nothing installed them |
| Startup | NOT EXECUTED | NOT EXECUTED | NOT EXECUTED | No process was launched |
| Camera permission | NOT EXECUTED | NOT EXECUTED | NOT EXECUTED | Manifest still has `CAMERA` and camera is not required hardware |
| Gallery | NOT EXECUTED | NOT EXECUTED | NOT EXECUTED | `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` maxSdk 28 remain |
| Model init | NOT EXECUTED | NOT EXECUTED | PARTIALLY VERIFIED | Asset test checks the default path and both checksums. No interpreter was created on Android |
| Offline inference | NOT EXECUTED | NOT EXECUTED | NOT EXECUTED | |
| Detection results | NOT EXECUTED | NOT EXECUTED | PARTIALLY VERIFIED | Decoder unit tests only. No camera frame |
| Confidence threshold | NOT EXECUTED | NOT EXECUTED | VERIFIED | `confidence_threshold_test.dart`, `legacy_decoder_test.dart` (D40 0.40). Not a device slider pass |
| Visualization | NOT EXECUTED | NOT EXECUTED | NOT EXECUTED | |
| Local persistence | NOT EXECUTED | NOT EXECUTED | PARTIALLY VERIFIED | Existing repository/organization unit tests. No on-device SQLite file was opened |
| History | NOT EXECUTED | NOT EXECUTED | NOT EXECUTED | |
| Offline queue | NOT EXECUTED | NOT EXECUTED | PARTIALLY VERIFIED | `sync_plan_test.dart` and Python offline/sync recovery tests |
| Sync retry | NOT EXECUTED | NOT EXECUTED | PARTIALLY VERIFIED | Same sync tests. No network retry against a server |
| Auth errors | NOT EXECUTED | NOT EXECUTED | PARTIALLY VERIFIED | `sync_plan_test.dart` checks a sync error does not keep a JWT-shaped token |
| Restart | NOT EXECUTED | NOT EXECUTED | NOT EXECUTED | |

## Model loading (static)

Status: VERIFIED by reading the loaders. Not verified on a device.

`TariqMapConstants.useRoadSenseModel` is `bool.fromEnvironment('USE_ROADSENSE_MODEL', defaultValue: false)`.

`DetectionService.create`:

- Flag false (default, and the way these APKs were built): `_createLegacyService` loads agent `road_damage` from `assets/models/road_damage.tflite`.
- Flag true: `_createHybridService` loads `road_damage_roadsense`. If `USE_POTHOLE_MODEL_FOR_D40` is true (its default), it also loads `road_damage` under the agent name `road_damage_pothole` with `onlyD40: true`. If RoadSense fails to load, it falls back to the legacy service, which again needs `road_damage.tflite`.

`ModelManager` copies the bundled asset for the agent name and checks the SHA-256 stored on `ModelConfig`. The new test locks the default path to `assets/models/road_damage.tflite` and checks both checksums. The default was not switched.

Both files must stay in the APK. There is no duplicate asset path. The redundant pubspec line was the only packaging overlap, and it did not produce a second zip entry.
