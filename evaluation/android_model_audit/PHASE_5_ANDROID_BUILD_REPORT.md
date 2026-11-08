# Phase 5 Android build report

Host: Linux container, Flutter 3.47.9, Dart 3.13.7, Java 21.0.12, Android SDK `$HOME/Android/Sdk`, platform android-36, build-tools 35.0.0. These sizes are the files on disk after the Phase 5 builds. They are not device install sizes.

## Sizes in bytes

| Artifact | Bytes | Flutter's rounded line |
| --- | --- | --- |
| Phase 4 debug APK, before this phase | 462,518,489 | about 442 MB was the earlier rounded report |
| Debug APK after this phase | 462,682,939 | rebuilt; 164,450 bytes larger, not smaller |
| Release `app-armeabi-v7a-release.apk` | 196,029,312 | 196.0 MB |
| Release `app-arm64-v8a-release.apk` | 162,450,778 | 162.5 MB |
| Release `app-x86_64-release.apk` | 172,735,964 | 172.7 MB |
| Release `app-release.aab` | 231,081,722 | 231.1 MB |

Paths:

- `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-debug.apk`
- `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `/tmp/Road-damage-project/app/build/app/outputs/flutter-apk/app-x86_64-release.apk`
- `/tmp/Road-damage-project/app/build/app/outputs/bundle/release/app-release.aab`

The same APKs are also under `app/build/app/outputs/apk/`. All of `app/build/` is gitignored.

## What the debug APK contains

Uncompressed entry groups in the Phase 5 debug APK:

| Group | Uncompressed bytes |
| --- | --- |
| `lib/` all ABIs | 330,873,152 |
| `assets/` | 198,705,553 |
| `kernel_blob.bin` | 102,869,984 |
| `road_damage.tflite` | 44,768,844 |
| `road_damage_roadsense.tflite` | 37,347,282 |
| `libVkLayer_khronos_validation.so` (arm64 only) | 15,240,080 |

There is no separate x86 (32-bit) ABI. Native libraries are not duplicated inside one ABI. `libc++_shared.so` appears once per ABI.

## What the release arm64 APK contains

| Entry | Uncompressed bytes |
| --- | --- |
| `road_damage.tflite` | 44,768,844 |
| `road_damage_roadsense.tflite` | 37,347,282 |
| `lib/arm64-v8a/libavcodec.so` | 22,174,672 |
| `lib/arm64-v8a/libflutter.so` | 11,763,360 |
| `lib/arm64-v8a/libtensorflowlite_jni.so` | 3,668,888 |
| `kernel_blob.bin` | absent |
| Vulkan validation library | absent |
| Other ABIs | absent |

The armeabi-v7a release APK is larger because that ABI ships both `libavcodec.so` and `libavcodec_neon.so`.

The AAB contains all three ABIs plus native symbol files under `BUNDLE-METADATA/com.android.tools.build.debugsymbols/` (`libflutter.so.sym` is about 18.8 MB for arm64, 17.9 MB for x86_64, and 13.9 MB for armeabi-v7a). Those symbols are for Play crash reports. They are not a second copy of the engine inside an installed APK. The bundle does not contain `kernel_blob.bin` or the Vulkan validation library.

## Identity and signing

| Field | Debug APK | Split release APK | AAB |
| --- | --- | --- | --- |
| applicationId | `com.tariqmap.app` | `com.tariqmap.app` | `com.tariqmap.app` is in the bundle manifest |
| versionName | 0.1.0 | 0.1.0 | 0.1.0 is in the bundle manifest |
| versionCode | 1 | 1001 / 2001 / 4001 | Flutter's app bundle keeps the pubspec code; the offsets above are only the split APKs |
| minSdk | 24 | 24 | same Gradle config |
| targetSdk | 36 | 36 | same Gradle config |
| debuggable | yes | no | release bundle |
| signer | debug | `CN=Android Debug`, SHA-256 `b4997d024925af75e4fd201efd278380a727d01486fa3c586e6e670c67996382` | same local release signing |

No upload keystore exists. The release artifacts are signed with the debug keystore because `signingConfig` points at it. They will not be accepted as a Play production upload.

## JVM target

Debug, release, and bundle logs have no `Inconsistent JVM` line and no `source value 8` note. The remaining Flutter line, printed for each build, is:

`Warning: Flutter support for your project's Kotlin version (2.2.20) will soon be dropped. Please upgrade your Kotlin version to a version of at least 2.3.20 soon.`

## Regression

| Suite | Result |
| --- | --- |
| `flutter analyze` | No issues, exit 0 |
| `flutter test` | 148 passed, 0 failed |
| Training contracts, API, sync recovery, offline, SQL contract, Pillow EXIF | 36 passed |
| `lock_android_contract.py` | `CONTRACT OK` |
| `spec_decoder_math.py` | `SPEC MATH OK` |
| Dashboard Vitest | 93 passed |
| `vite build` | succeeded |
| Debug APK | succeeded |
| Release ABI APKs | succeeded |
| AAB | succeeded |
| Emulator | BLOCKED. `/dev/kvm` is not writable |
| Physical device | NOT EXECUTED |
| SQL execution against production | NOT EXECUTED |
| Local disposable Postgres from Phase 4 | NOT re-executed this phase. The SQL file was not changed |

## Status

| Item | Status |
| --- | --- |
| Debug, release APKs, AAB | VERIFIED as builds |
| Size numbers above | VERIFIED by file size and zip entry size |
| Play-signed release | BLOCKED |
| Device install | NOT EXECUTED |
