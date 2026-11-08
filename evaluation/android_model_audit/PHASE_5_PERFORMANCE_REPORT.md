# Phase 5 performance report

No detection threshold, stretch path, or weight file was changed. No phone timing was taken. Nothing below is a device benchmark.

## How each number was measured

| Result | Kind | Value |
| --- | --- | --- |
| Phase 4 debug APK | build artifact, `stat` | 462,518,489 bytes |
| Phase 5 debug APK | build artifact, `stat` | 462,682,939 bytes |
| arm64 release APK | build artifact, `stat` | 162,450,778 bytes |
| armeabi-v7a release APK | build artifact, `stat` | 196,029,312 bytes |
| x86_64 release APK | build artifact, `stat` | 172,735,964 bytes |
| AAB | build artifact, `stat` | 231,081,722 bytes |
| `road_damage.tflite` inside every package | zip entry, static | 44,768,844 bytes |
| `road_damage_roadsense.tflite` inside every package | zip entry, static | 37,347,282 bytes |
| Debug `kernel_blob.bin` | zip entry, static | 102,869,984 bytes |
| Debug native `lib/` | zip entries, static | 330,873,152 bytes uncompressed |
| Release arm64 `libflutter.so` | zip entry, static | 11,763,360 bytes, down from 38,846,424 in the debug arm64 library |
| Release arm64 `libtensorflowlite_jni.so` | zip entry, static | 3,668,888 bytes |
| Startup, inference, camera, memory on a phone | physical device | NOT EXECUTED |
| Emulator | emulator | BLOCKED. `/dev/kvm` is not writable by this user |

## What was not optimized

Minify and resource shrinking were not turned on. There is no before/after for R8 because it was not enabled. ABI splits do not make one model smaller. They stop a release APK from also carrying the other two ABIs. The AAB is larger than the arm64 APK because it still holds three ABIs and native debug symbols.

The two models plus arm64 FFmpeg are the bulk of what a phone would install from the arm64 APK. That was measured. It was not changed, because both models are assets the app can load and FFmpeg is used to write the annotated video.

## Status

| Item | Status |
| --- | --- |
| APK, AAB, and model sizes | VERIFIED as static measurements |
| Startup time | NOT EXECUTED |
| Emulator | BLOCKED |
| Claimed speedup | NOT APPLICABLE. None claimed |
