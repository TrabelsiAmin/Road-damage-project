# Phase 7 security report

Static inspection of the Phase 6 artifacts and of the Phase 7 rebuild. The rebuild wrote the same byte sizes, and the arm64 APK still contains each model once with the same SHA-256 prefixes, so the certificate and manifest checks below apply to the tree as it is. No signing config was edited. No production certificate was created. `key.properties` is absent. The four signing environment variables were unset for the rebuild.

## Artifact identity

| Item | ARM64 release APK | AAB |
| --- | --- | --- |
| Path | `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | `app/build/app/outputs/bundle/release/app-release.aab` |
| Bytes | 162,451,078 | 231,089,677 |
| Package | `com.tariqmap.app` | same application id inside the bundle |
| versionName / versionCode | 0.1.0 / 2001 | built from the same Gradle config (split codes: v7a 1001, x86_64 4001) |
| min / target | 24 / 36 | same |
| ABI | `native-code: arm64-v8a` only (18 `.so` files under `lib/arm64-v8a`) | `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| Models | each once: `road_damage.tflite` 44,768,844, `road_damage_roadsense.tflite` 37,347,282 | each once under `base/assets/flutter_assets/assets/models/` |
| Vulkan validation / kernel blob | absent | absent |
| Debuggable | not set in the binary manifest | release bundle, not a debug APK |
| Signer | `apksigner`: `CN=Android Debug`, SHA-256 `b4997d024925af75e4fd201efd278380a727d01486fa3c586e6e670c67996382` | `keytool -printcert` on `META-INF/ANDROIDD.RSA`: same owner and SHA-256. `jarsigner -verify` exited 0 (`jar verified`) |

Other release splits after the rebuild: armeabi-v7a 196,029,608 bytes, x86_64 172,736,264 bytes. Debug APK 462,551,570 bytes, `application-debuggable`, and it still contains `kernel_blob.bin` and one Vulkan validation library. That is expected for debug.

## Secrets

Release `lib/arm64-v8a/libapp.so`: the byte string `service_role` occurs once. The surrounding snapshot text is Flutter layout symbols (`markNeedsLayout` / `get:_isVertical`), not a key. `eyJ` occurs twice, each run is 3 bytes, zero dots, not a JWT. `eyJhbGci` occurs zero times. `BEGIN PRIVATE` occurs zero times. The same counts are on the three AAB `libapp.so` copies.

Debug `kernel_blob.bin`: 7× `service_role`, 35× `eyJ`, 2× `eyJhbGci`. That blob is the debug kernel and is not in the release APK or the AAB. The values were not printed.

No `http://` scan was re-run against source this phase beyond the Phase 6 result (none in `app/lib`). Production Supabase was not contacted. The SQL migration was not applied.

## Permissions (merged ARM64 release)

Present: `CAMERA`, `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `WRITE_EXTERNAL_STORAGE` maxSdk 28, `READ_EXTERNAL_STORAGE`, `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, and the app's own non-exported receiver permission.

Absent: `RECORD_AUDIO`. `allowBackup=0`. `usesCleartextTraffic=0`.

## Signing posture

Status: VERIFIED as static analysis. The release artifact is intentionally debug-signed when no upload key is configured. That configuration was not changed to imitate a production cert. Play still requires a real upload key created outside this repo.

Status of a production signature: NOT VERIFIED, by design.
