# Android performance

**BLOCKED.**

Checked this machine:

- `flutter` not on `PATH`
- `adb` not on `PATH`
- no emulator binary found
- `adb devices` not run because `adb` is absent

No Android SDK install was attempted. A full SDK download is not a realistic measurement pass in this session, and a Linux TFLite invoke is not a phone result.

## Numbers that exist, and what they are

| Measurement | Value | Tag |
|---|---|---|
| Legacy file size | 44,768,844 bytes | VERIFIED |
| RoadSense file size | 37,347,282 bytes | VERIFIED |
| Linux `allocate_tensors` on the legacy file | 55.4 ms | VERIFIED, not app cold start |
| Linux `invoke` mean, zero tensor, n=8, 2 threads, XNNPACK | 112.4 ms (min 110.7, max 115.1) | VERIFIED, **not Android** |
| Linux `invoke` mean, 12 real images, earlier same VM | 103.7 ms, p95 104.6 ms | VERIFIED, **not Android** |
| Derived Linux throughput at 103.7 ms | about 9.6 invokes/s, preprocess excluded | ESTIMATED from that mean |
| Android CPU/GPU/NNAPI latency, FPS, RAM, cold start | none | BLOCKED |
| `docs/product-spec.md` target “under 2.5 s cold start on a mid-range phone” | not tested | NOT VERIFIED |

`ModelManager` copies ~43 MiB from assets into app documents and hashes it before the first inference. That copy is extra cold-start work on Android and was **not timed** on a device.

Release build is signed with the debug keystore. That is a shipping issue, not a speed measurement. **VERIFIED** in `build.gradle.kts`.

Camera path is one still at `ResolutionPreset.high`, not a live FPS loop (`camera_detection_screen.dart`). Live-stream FPS is **NOT APPLICABLE** to the current capture design.
