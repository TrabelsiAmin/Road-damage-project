# Phase 5 release readiness

HEAD `cd7d168`. Nothing was committed or pushed. Phase 1–4 reports are still in `evaluation/android_model_audit/`. Tracked diff is 48 files, +2026 / −984, plus the same untracked Phase 1–4 tree and these Phase 5 reports. `app/pubspec.yaml` was not edited. No weight, dataset, `ios/`, or `.env` file is in the diff. Generated APKs and the AAB are gitignored under `app/build/`.

## What a person can do next

The arm64 release APK can be copied to a phone for a supervised test. It is signed with the Android debug certificate. It is not a Play upload.

Absolute paths and sizes:

| File | Bytes |
| --- | --- |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-debug.apk` | 462,682,939 |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | 162,450,778 |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` | 196,029,312 |
| `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-x86_64-release.apk` | 172,735,964 |
| `/tmp/Road-damage-project/app/build/app/outputs/bundle/release/app-release.aab` | 231,081,722 |

## Test plan that was not run

Apple Silicon Mac, Android Studio emulator:

1. Install Android Studio and an arm64 system image. Hardware acceleration on a Mac uses the Apple hypervisor, not this container's `/dev/kvm`.
2. Install `app-arm64-v8a-release.apk` with `adb install -r`. Do not use the 462 MB debug APK unless you need hot reload.
3. Cold start. Confirm the label TariqMap and that the process is not waiting on a debugger.
4. Deny camera, then allow it. The in-app error should stay recoverable with Retry.
5. Open the gallery picker and import one photo.
6. Confirm the legacy model loads (`road_damage.tflite`, not a letterbox switch). Run one offline inference with the network disabled.
7. Check the class codes on the result are only D00, D10, D20, D40, or the existing unknown label. Do not expect a new accuracy number.
8. Leave the screen and reopen the capture. The local row should still be there.
9. Confirm the offline queue shows pending, not synced, while the network is off.
10. Restore the network and run sync only against a non-production project.
11. Kill the app during sync and reopen. The local row should still exist.
12. Watch memory in Android Studio during one inference and one video import. This container did not measure that.

Physical phone: the same steps, plus a portrait photo and a landscape photo so EXIF orientation can be checked against the boxes on screen. Use the arm64 APK for a current phone. Use the armeabi-v7a APK only for a 32-bit device.

None of those steps were executed here.

## What still blocks a Play Store release

1. Signing. The AAB and release APKs use `CN=Android Debug`. Play requires an upload key that this clone does not have and that this phase did not generate.
2. No device or emulator pass. Camera, inference, and sync on hardware are not verified.
3. The model is not scientifically validated. No mAP was computed.
4. `submit_observation` in `supabase/migrations/20261105_submit_observation_stable_ids.sql` passed a disposable local database in Phase 4 and is not deployed. Production can still be on the old function.
5. RLS and storage recommendations are still unapplied comments.
6. Install size. The arm64 release APK is 162,450,778 bytes because it contains both TensorFlow Lite models and FFmpeg. That is an honest package, not a Play size waiver.
7. Version `0.1.0` (code 1, or the split-APK offsets 1001/2001/4001). A store release needs a product decision on the version users should see.
8. Flutter warns that Kotlin 2.2.20 will need to be at least 2.3.20. It was left unchanged so the JVM-target fix did not become a dependency upgrade.
9. A release build without `SUPABASE_URL` and `SUPABASE_ANON_KEY` dart-defines will not start. Those defines must be the public anon key, never the service-role key. Env vars do not replace RLS.

## Status

| Question | Status |
| --- | --- |
| Local debug and release builds | VERIFIED |
| Ready for a supervised sideload test of the arm64 release APK | Yes, as a manual test |
| Ready for Play production | No |
