# Phase 6 final readiness

The Android release build works on this container. It is not ready to upload to Play.

## Status

| Gate | Status | Why |
| --- | --- | --- |
| Default model still `road_damage.tflite`, both models present once | VERIFIED | Source, asset test, zip SHA-256 prefixes |
| No duplicate model packaging | VERIFIED | One zip entry each, all five artifacts |
| Vulkan validation out of release | VERIFIED | Present only in the debug APK |
| ABI splits | VERIFIED | arm64 versionCode 2001, v7a 1001, x86_64 4001; AAB has three ABIs |
| R8 left off | VERIFIED | `isMinifyEnabled` and `isShrinkResources` are false |
| Size reduction | NOT APPLICABLE | Release APKs +296 to +300 bytes, AAB +7,955. Debug −131,369. No asset was removed |
| Kotlin 2.3.20 | VERIFIED | Debug, release, and AAB built. Old 2.2.20 warning is gone. JVM target stays 17 |
| Gradle 9.1 / AGP 9.0.1 warnings | NOT APPLICABLE as a fix | Flutter warns. Error floor is the versions already in the project. Not upgraded |
| Env signing with debug fallback | VERIFIED | Missing keystore is selected and then rejected. Unset path signs `CN=Android Debug` |
| Production upload signature | NOT VERIFIED | No upload keystore exists here, by design |
| Manifest hardening | VERIFIED | Static. Backup off, cleartext off, release not debuggable, microphone permission removed |
| Emulator startup | BLOCKED | `/dev/kvm` is not writable by `ubuntu`. This is not the user's Mac |
| Device checklist | NOT EXECUTED | No phone |
| Host regression | VERIFIED | analyze clean, Flutter 149/149, Python 36, SQL contract, spec math, vitest 93, vite build, three package builds |
| Scientific validation of the weights | NOT VERIFIED | Unchanged. Do not treat a successful APK as a model-quality claim |
| Production SQL / Supabase | NOT APPLICABLE | Not run. The local migration must not be applied to production from this work |

## What still blocks a Play release

1. The AAB is signed with the Android debug certificate. Play needs an upload key created on the release machine, then `flutter build appbundle --release` with `key.properties` or the four environment variables set. Steps are in `PHASE_6_SIGNING_SECURITY.md`.
2. No emulator and no device has installed the APK. Camera, gallery, inference, history, queue, sync, auth errors, and restart are unchecked on Android. The Apple Silicon steps are in `PHASE_6_ANDROID_RUNTIME.md`. Use `app-arm64-v8a-release.apk`.
3. The weights are not a scientifically validated detector. Shipping the APK does not change that.
4. `supabase/migrations/20261105_submit_observation_stable_ids.sql` is not a production change. Do not apply it to the hosted project as part of this phase.

Gradle 8.14 and AGP 8.11.1 future-support warnings do not block this build. They will block a later Flutter upgrade if they are still unaddressed when Flutter raises its error floor.

## Git review

HEAD: `cd7d16898465174c06a1362953c052f156e0485b` on `main`. Not committed. Not pushed.

`git diff --stat` against HEAD: 51 files, +2085 / −996. That includes Phase 1–5 plus this phase. Phase 6's tracked edits are `app/.gitignore`, `app/android/app/build.gradle.kts`, `app/android/settings.gradle.kts` (Kotlin version only), and `app/pubspec.yaml` (one redundant asset line removed). `app/android/gradle.properties` and `AndroidManifest.xml` are dirty from earlier phases and were not edited again after the Phase 6 backup.

Untracked that this phase added: `app/android/key.properties.example`, `app/test/unit/model_asset_test.dart`, and this report directory's Phase 6 files under `evaluation/` (the `evaluation/` tree was already untracked from prior phases).

Phase 5 reports are still at `evaluation/android_model_audit/PHASE_5_*.md`.

Not in the diff: dataset images, `ios/`, a filled `key.properties`, any `.jks` or `.keystore`, production Supabase SQL applied from here. No test file was gutted or marked skipped to force a pass.

Model checksums after the rebuild match the pre-edit digests in `PHASE_6_IMPLEMENTATION_REPORT.md`.

Generated artifacts (gitignored `app/build/`):

| Path | Bytes |
| --- | ---: |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-debug.apk` | 462,551,570 |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | 162,451,078 |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` | 196,029,608 |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-x86_64-release.apk` | 172,736,264 |
| `/tmp/Road-damage-project/app/build/app/outputs/bundle/release/app-release.aab` | 231,089,677 |

The same APK bytes are also under `app/build/app/outputs/apk/debug/` and `app/build/app/outputs/apk/release/`.

## Deployment requirements if someone continues

- Keep minify off until a TFLite keep-rule pass is proved with `flutter test` and a release build.
- Keep both `.tflite` files.
- Do not set `abiFilters` if the AAB must still serve all three ABIs.
- On a Mac: create the upload keystore, fill the gitignored properties or the env vars, rebuild the app bundle, install the arm64 APK on an arm64 API 36 emulator and on a phone, and walk the checklist in the runtime report.
- Do not upload the debug-signed AAB from this container.
