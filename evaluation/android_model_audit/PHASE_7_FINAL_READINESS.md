# Phase 7 final readiness

The release build still compiles and the artifacts match Phase 6 byte for byte. The app is not Play-ready. No code change was made in this phase.

## Hard split

Verified on this machine:

- Host tests: analyze clean, Flutter 149/149, Python 36, SQL contract OK, spec math OK, vitest 93, dashboard production build.
- Android packages rebuilt: debug APK, three ABI release APKs, AAB. Sizes unchanged from Phase 6.
- Static APK/AAB: package `com.tariqmap.app`, versionName 0.1.0, min 24, target 36, both models once, arm64-only release APK, AAB has three ABIs, signer `CN=Android Debug`, release not debuggable, no JWT in release `libapp.so`.

Not executed:

- Install, launch, logcat, camera, gallery, inference, detection UI, threshold persistence on device, offline queue, sync retry, resume, restart.

Blocked:

- Emulator boot. `/dev/kvm` returns `EACCES` for uid 1000. The emulator package and system images are not installed. `adb devices` is empty.

Not applicable:

- A production signing change. None was made, and none should be made here to hide the debug certificate.
- A toolchain upgrade. Flutter 3.47.9, Gradle 8.14, AGP 8.11.1, Kotlin 2.3.20, and `tflite_flutter` 0.11.0 were left as Phase 6 left them.
- Production SQL. Not applied.

## Play blockers

1. The AAB is signed `CN=Android Debug`. Create an upload keystore on the release machine, fill gitignored `key.properties` or `STORE_FILE` / `KEY_ALIAS` / `STORE_PASSWORD` / `KEY_PASSWORD`, and rebuild the app bundle. Do not upload this container's AAB.
2. No emulator and no phone has installed `app-arm64-v8a-release.apk`. Camera, gallery, TFLite init, and sync are unchecked at runtime.
3. The weights are not scientifically validated. Loading the file, or hashing it, is not an accuracy claim.
4. `supabase/migrations/20261105_submit_observation_stable_ids.sql` must not be applied to production as part of this work.

Gradle 9.1 and AGP 9.0.1 warnings remain and do not fail this build.

## Git

HEAD: `cd7d16898465174c06a1362953c052f156e0485b`. Not committed. Not pushed.

Working tree at the start of Phase 7: 51 tracked files, +2085 / −996, plus the existing untracked Phase 1–6 files. Phase 7 added only these reports under `evaluation/android_model_audit/`. No weight, dataset, `ios/`, secret, or production Supabase file was edited. No test was disabled.

Artifacts, same bytes as Phase 6:

| Path | Bytes |
| --- | ---: |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-debug.apk` | 462,551,570 |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | 162,451,078 |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` | 196,029,608 |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-x86_64-release.apk` | 172,736,264 |
| `/tmp/Road-damage-project/app/build/app/outputs/bundle/release/app-release.aab` | 231,089,677 |
