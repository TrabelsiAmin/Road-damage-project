# Phase 5 implementation report

Work is on `/tmp/Road-damage-project`. HEAD is still `cd7d168`. Nothing was committed or pushed. Weights, datasets, `ios/`, production Supabase, detection thresholds, and the 640×640 stretch path were not changed. Class codes stay D00, D10, D20, and D40. No Play signing key was created.

Backups of the Gradle and manifest files are in `evaluation/android_model_audit/backups/phase5/`.

## P0 — Debug APK size

- Problem: The Phase 4 debug APK was reported as about 442 MB. The file on disk was 462,518,489 bytes.
- Root cause, from `unzip` entry sizes, not from a guess:
  - `assets/flutter_assets/kernel_blob.bin` is 102,869,984 bytes. That is the debug Dart kernel. Release builds do not contain it.
  - `lib/` native code is 330,873,152 bytes uncompressed across three ABIs (`armeabi-v7a` 121,708,568, `arm64-v8a` 107,246,128, `x86_64` 101,918,456). FFmpeg (`libavcodec` and related) is a real dependency of video stitching. `libflutter.so` is about 33–40 MB per ABI in debug, and `lib/arm64-v8a/libVkLayer_khronos_validation.so` is 15,240,080 bytes (debug Vulkan validation).
  - Both model files are present and were left in place: `road_damage.tflite` 44,768,844 bytes and `road_damage_roadsense.tflite` 37,347,282 bytes. The second model is loaded only when `USE_ROADSENSE_MODEL` is set. Removing it would break that path, so it stayed.
- Fix: No asset was deleted. Release builds use ABI splits and an App Bundle. R8 minify and resource shrinking stay off. R8 can remove TFLite JNI and Flutter plugin classes; `proguard-rules.pro` already keeps `org.tensorflow.lite.**`, but that file is not a proof that the rest of the Flutter embedding would survive shrinking. `isMinifyEnabled` and `isShrinkResources` are explicitly false.
- Files: `app/android/app/build.gradle.kts`.
- Before / after: see `PHASE_5_ANDROID_BUILD_REPORT.md`. The rebuilt debug APK is 462,682,939 bytes. It did not get smaller. The release arm64 APK is 162,450,778 bytes. That drop is the debug kernel, the other ABIs, and the Vulkan validation library leaving the release package, measured by listing the APK entries.
- Tests: debug, split release, and app bundle builds succeeded. `flutter test` stayed 148/148.
- Limitations: A phone that installs the arm64 release APK still receives both models and the arm64 FFmpeg libraries. Play would deliver one ABI from the bundle, not the 231 MB upload size.
- Status: VERIFIED for the measured sizes. A smaller universal debug APK was not a safe change.

## P0 — JVM target mismatch

- Problem: `:tflite_flutter:compileDebugKotlin` failed because Java was 1.8 and Kotlin followed JDK 21.
- Root cause: `tflite_flutter` 0.11.0 sets `JavaVersion.VERSION_1_8` and does not set a Kotlin JVM target. Phase 4 hid the check with `kotlin.jvm.target.validation.mode=warning`.
- Files: `app/android/app/build.gradle.kts`, `app/android/gradle.properties`.
- Fix: That warning flag was removed. Every Android module other than `:app` is configured, after evaluation, to compile Java and Kotlin for JVM 17, the same target the app module already uses. The plugin version was not changed. Debug and release share this setting.
- Tests: debug APK, three release APKs, and the AAB. The logs do not contain `Inconsistent JVM` or `source value 8`.
- Remaining warning, which is not the JVM-target mismatch: Flutter prints `Warning: Flutter support for your project's Kotlin version (2.2.20) will soon be dropped. Please upgrade your Kotlin version to a version of at least 2.3.20 soon.` Kotlin was not upgraded. That would be a dependency change, and the JVM mismatch is already gone without it.
- Status: VERIFIED. The tflite Java/Kotlin mismatch no longer appears in the three build logs.

## P0 — Release and bundle builds

- Files: `app/android/app/build.gradle.kts`. Signing stays `signingConfigs.getByName("debug")`, which was already how this project built a local release. No keystore was generated.
- `applicationId` is `com.tariqmap.app`. `versionName` is `0.1.0`. Debug `versionCode` is 1. Split release APKs use Flutter's ABI offsets: armeabi-v7a 1001, arm64-v8a 2001, x86_64 4001. `minSdk` 24. `targetSdk` 36. `compileSdk` 36.
- Both `.tflite` files are inside every release APK and the AAB. `kernel_blob.bin` and `libVkLayer_khronos_validation.so` are not.
- The arm64 release APK is signed by the Android debug certificate (`CN=Android Debug`). That is not a Play Store signature.
- Release `libapp.so` does not contain the project ref `lendqcjihusqkmxansbl` or an `eyJ` JWT. It does contain the word `service_role` next to the existing client check that refuses that role. The debug kernel still contains the debug anon fallback, which is the Phase 3 decision.
- Status: VERIFIED as local build artifacts. Play signing is NOT VERIFIED and was not attempted.

## P1 — Emulator

Not run. `/dev/kvm` is still not writable by this user. A test plan is in `PHASE_5_RELEASE_READINESS.md`. Status: BLOCKED.

## P1 — Android security

- Problem: The merged manifest did not say backup or cleartext policy, and the camera plugin added `RECORD_AUDIO` even though live capture sets `enableAudio: false` and the app does not record.
- Files: `app/android/app/src/main/AndroidManifest.xml`.
- Fix: `android:allowBackup="false"`, `android:usesCleartextTraffic="false"`, and `tools:node="remove"` on `RECORD_AUDIO`. Camera, internet, fine and coarse location stay. `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` (max SDK 28) stay because gallery import and saving a video still need them on older APIs. `ACCESS_NETWORK_STATE` and `WAKE_LOCK` come from connectivity and the Flutter engine. They were left.
- Checked on the built debug APK: `debuggable` is true, backup is false, cleartext is false, `RECORD_AUDIO` is absent. The arm64 release APK is not marked debuggable, backup is false, cleartext is false.
- No service-role secret was added. Production backend settings were not changed.
- Status: VERIFIED for the flags in these artifacts. A device install was not done.

## P1 — Release UX

The launcher label is already `TariqMap`. The launcher icon and `LaunchTheme` are the existing ones. Version is `0.1.0+1`. The camera screen already says `Camera could not start. Check permission and try again.` and has Retry. No visual change was made. Status: NOT APPLICABLE for a redesign. The existing strings were not re-tested on a device.

## P1 — Regression

`flutter test` 148 passed. `flutter analyze` found no issues. Backend, SQL contract, dashboard Vitest, and the Vite production build passed. Details are in `PHASE_5_ANDROID_BUILD_REPORT.md`.

## Status

| Item | Status |
| --- | --- |
| Measured size breakdown | VERIFIED |
| Debug APK smaller | NOT APPLICABLE. It stayed about the same size on purpose |
| Release ABI APKs and AAB | VERIFIED as builds |
| JVM mismatch | VERIFIED gone |
| Kotlin 2.2.20 future-support warning | Still printed. Not upgraded |
| Play signing | BLOCKED. Debug certificate only |
| Emulator and phone | BLOCKED / NOT EXECUTED |
