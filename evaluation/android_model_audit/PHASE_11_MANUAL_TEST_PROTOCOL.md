# Phase 11 manual test protocol

No row is PASS. Emulator and device columns are NOT EXECUTED. Host unit tests are not a substitute for a row.

Package: `com.tariqmap.app`. Use `app-arm64-v8a-release.apk` (162,451,078 bytes) on arm64. The installed build does not set `USE_ROADSENSE_MODEL`, so only `road_damage.tflite` loads. That file is NHWC `[1, 640, 640, 3]` → `[1, 8, 8400]`.

Threshold rule, from `app/lib/inference/confidence_threshold.dart`:

- Until the user saves the slider, class floors stay D00 0.35, D10 0.35, D20 0.30, D40 0.40.
- After save, one score clamped to 0.10–0.80 replaces every class floor.
- NMS IoU stays 0.45 and is not the slider.

| Scenario | Prerequisites | Steps | Expected result | Evidence | Pass/fail |
| --- | --- | --- | --- | --- | --- |
| First launch | APK installed, app data cleared | Open the app from the launcher | Process stays up. No crash dialog. First-run organization or home UI appears | Screenshot plus `adb logcat -d` with no `FATAL EXCEPTION` | NOT EXECUTED |
| Camera permission granted | Camera hardware or an emulator virtual camera | Open live capture and allow Camera | Preview starts, or a clear error if the emulator has no camera. `enableAudio` is false, so the app should not require the microphone | Screenshot of the preview or of the stated error. Log excerpt | NOT EXECUTED |
| Camera permission denied | Same | Deny Camera | Capture does not start. The screen says the camera could not start or that no camera is available. The app does not crash | Screenshot | NOT EXECUTED |
| Image selection | A local JPEG | Choose a gallery image and continue | The image opens. Orientation follows the file's EXIF. Inference uses stretch to 640×640 | Screenshot of the selected image and the result | NOT EXECUTED |
| TFLite init | Default release APK | Open a flow that runs detection | Legacy model loads. RoadSense does not load. Log may show the legacy agent only | Log excerpt naming `road_damage` and not a RoadSense load error | NOT EXECUTED |
| Detection rendering | A capture that returns boxes | Open the result | Boxes and labels use D00, D10, D20, D40, or the text `Unknown class`. An unknown code is not shown as D40 | Screenshot of each label that appeared | NOT EXECUTED |
| Confidence before save | Fresh install, slider not saved | Run one image. Read Settings | Floors are D00/D10 0.35, D20 0.30, D40 0.40. NMS IoU is 0.45 | Screenshot of the settings text | NOT EXECUTED |
| Confidence after save | Same | Set the slider to 0.50 and save. Run another capture | Every class uses 0.50. IoU stays 0.45. A value outside 0.10–0.80 is clamped, not stored raw | Screenshot before and after save | NOT EXECUTED |
| Offline operation | Airplane mode | Capture one image | The observation is stored locally. No crash when the network is absent | Screenshot of the queue and a log line that sync did not claim success | NOT EXECUTED |
| Pending sync | That queued item | Open the offline queue | The item is listed as pending, not synced | Screenshot | NOT EXECUTED |
| Network restoration | Queue still pending. A non-production endpoint only | Leave airplane mode | The app retries. It must not be aimed at production Supabase for this exercise. Failure against a missing test server is a recorded result, not a silent pass | Log of the retry and the queue state after it | NOT EXECUTED |
| Restart | Pending item still present | Force-stop and reopen | The pending item is still there | Two screenshots, before and after | NOT EXECUTED |

RoadSense on device is a separate build: `flutter build apk --release --split-per-abi --dart-define=USE_ROADSENSE_MODEL=true`. That APK does not exist in the Phase 6/7 outputs. Do not mark the default APK as a RoadSense pass. When that flag is on, the app also loads the legacy file for D40 unless `USE_POTHOLE_MODEL_FOR_D40` is set false.
