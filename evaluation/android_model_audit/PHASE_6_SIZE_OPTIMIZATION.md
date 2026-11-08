# Phase 6 size optimization

Measurement kind for every byte count below: **build validation** (`stat` on the file Flutter wrote) or **static analysis** (`unzip` / Python `zipfile`, `aapt dump badging`). No emulator and no physical device measurement.

Phase 5 artifacts were overwritten by this rebuild. The "before" column is the Phase 5 `stat` values, not a second copy kept on disk.

## Before and after

| Artifact | Phase 5 bytes | Phase 6 bytes | Delta |
| --- | ---: | ---: | ---: |
| `app-debug.apk` | 462,682,939 | 462,551,570 | −131,369 |
| `app-arm64-v8a-release.apk` | 162,450,778 | 162,451,078 | +300 |
| `app-armeabi-v7a-release.apk` | 196,029,312 | 196,029,608 | +296 |
| `app-x86_64-release.apk` | 172,735,964 | 172,736,264 | +300 |
| `app-release.aab` | 231,081,722 | 231,089,677 | +7,955 |

There is no packaging reduction to claim. The release APKs grew by a few hundred bytes. The AAB grew by 7,955 bytes. The debug APK is 131,369 bytes smaller. The model zip entries and the large native libraries Phase 5 listed (`libflutter.so` arm64 release 11,763,360 bytes, `libtensorflowlite_jni.so` arm64 3,668,888 bytes, both TFLite files) are the same uncompressed sizes. The deltas are small-entry noise from the Kotlin 2.3.20 recompile (dex and resources). The Phase 5 APK was not kept, so those small entries were not diffed one by one. That is a limitation, not a hidden win.

## What is inside the arm64 release APK

`aapt dump badging`: `com.tariqmap.app`, versionName `0.1.0`, versionCode `2001`, minSdk 24, targetSdk 36, `native-code: arm64-v8a` only. Not debuggable.

Compressed sizes from the zip (models and `lib/` are stored uncompressed):

| Category | Compressed bytes | Uncompressed bytes |
| --- | ---: | ---: |
| Both TFLite models | 82,116,126 | 82,116,126 |
| `lib/arm64-v8a` | 71,810,224 | 71,810,224 |
| `classes.dex` and related dex | 7,334,924 | 19,356,672 |
| Android resources and metadata | 731,692 | 901,824 |
| Other Flutter assets | 259,961 | 439,015 |
| File on disk | 162,451,078 | |

Each model appears once:

| Zip entry | Uncompressed | SHA-256 prefix |
| --- | ---: | --- |
| `assets/flutter_assets/assets/models/road_damage.tflite` | 44,768,844 | `830f99bd8c31c5d2` |
| `assets/flutter_assets/assets/models/road_damage_roadsense.tflite` | 37,347,282 | `300798be883a7003` |

The same two entries, same sizes, same prefixes, are in the v7a APK, the x86_64 APK, the debug APK, and the AAB (`base/assets/flutter_assets/...`). No second path. No `kernel_blob.bin` in any release artifact. No `libVkLayer_khronos_validation.so` in any release artifact.

Version codes on the other splits: armeabi-v7a `1001`, x86_64 `4001`. Each release APK has one ABI. The debug APK is still a fat package: `native-code: arm64-v8a armeabi-v7a x86_64`, `application-debuggable`, `kernel_blob.bin` 102,869,984 bytes, and `lib/arm64-v8a/libVkLayer_khronos_validation.so` 15,240,080 bytes. Vulkan validation is debug-only and was already absent from release. Nothing further was stripped.

## What was inspected and left alone

Duplicate models. None. Both files are required (see the runtime report). Deleting one would break a supported load path. Status: NOT APPLICABLE as a deletion.

Same-ABI duplicate `.so`. None in the release APKs. The AAB has three ABIs of each library, which is what Play needs. Status: no change.

armeabi-v7a FFmpeg neon. `libavcodec_neon.so` and the other `*_neon.so` copies are still next to the non-neon FFmpeg libraries. They are not the same file packaged twice. Video stitch uses this dependency. Status: left in place.

AAB `BUNDLE-METADATA/com.android.tools.build.debugsymbols/`. Nine symbol files, including `libflutter.so.sym` per ABI. Play uses these for crash symbolication. They are not installed as a second `libflutter.so`. Removing them would not shrink the APK a phone installs and would weaken Play symbolication. Status: left in place. Not counted as an install-size reduction.

R8 / `shrinkResources`. Still false. Phase 5 left them off because R8 can strip TFLite JNI. No safe subset was proved, so they were not enabled and no R8 experiment was run. Status: NOT APPLICABLE.

Unused Dart packages. Not removed. `ffmpeg_kit_flutter_new` is the video-stitch dependency. No dependency was shown to be unused by a supported screen. Status: no change.

ABI splits. Still produced only by `flutter build apk --release --split-per-abi`. `abiFilters` was not set, so the AAB still contains arm64-v8a, armeabi-v7a, and x86_64. Status: unchanged and correct.

## Model decision

Both models stay bundled.

- Default, with no dart-define: `DetectionService.create` calls `_createLegacyService` and loads `road_damage` only. `ModelConfig.active` is that file. Input contract remains NHWC `[1,640,640,3]` to `[1,8,8400]`.
- `USE_ROADSENSE_MODEL=true` calls `_createHybridService`, which loads `road_damage_roadsense`. `USE_POTHOLE_MODEL_FOR_D40` defaults to true, so that path also loads `road_damage` as `road_damage_pothole` with `onlyD40`.
- Selection is compile-time (`bool.fromEnvironment`), not a runtime download. A release that only shipped the default file would fail the flagged hybrid path.

Status of the bundling decision: VERIFIED by source inspection plus the asset test plus the zip hashes. Status of a size win from dropping a model: NOT APPLICABLE.

## Paths

These are the files this rebuild wrote. The `apk/debug` and `apk/release` copies match the `flutter-apk` sizes byte for byte.

- `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-debug.apk` — 462,551,570
- `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` — 162,451,078
- `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` — 196,029,608
- `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-x86_64-release.apk` — 172,736,264
- `/tmp/Road-damage-project/app/build/app/outputs/bundle/release/app-release.aab` — 231,089,677
