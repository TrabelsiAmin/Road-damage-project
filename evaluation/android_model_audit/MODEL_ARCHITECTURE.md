# Model architecture (Android)

Tag: **VERIFIED** for tensor shapes and which file the default build loads. **NOT VERIFIED** for training hyperparameters, because no `.pt` and no `runs/` exist.

## Default model

| Item | Evidence | Tag |
|---|---|---|
| File | `app/assets/models/road_damage.tflite` | VERIFIED |
| Loader | `DetectionService._agentDefs` is only `_AgentDef('road_damage', ['D00','D10','D20','D40'])` (`detection_service.dart` lines 114–116). `_createLegacyService` builds `TFLiteAgentRunner` for that name. | VERIFIED |
| Flag | `TariqMapConstants.useRoadSenseModel` is `bool.fromEnvironment('USE_ROADSENSE_MODEL', defaultValue: false)` (`constants.dart`). | VERIFIED |
| Integrity | `ModelManager` copies the asset to `tariqmap_models/road_damage.tflite` and requires SHA-256 `830f99bd…`. Recomputed hash matches. | VERIFIED |
| Input | float32 NHWC `[1, 640, 640, 3]`, name `images`, quant scale 0 | VERIFIED (interpreter) |
| Output | float32 `[1, 8, 8400]`, name `output0` | VERIFIED |
| Embedded text | `YOLOv8_Small_RDD` | VERIFIED (bytes) |
| Android package | `applicationId` `com.tariqmap.app`, namespace `com.example.tariqmap`, `MainActivity` is a stock `FlutterActivity`. `aaptOptions.noCompress` includes `tflite`. Release signing is the debug keystore (`build.gradle.kts`). | VERIFIED (source). minSdk is `flutter.minSdkVersion`, **NOT VERIFIED** numerically (Flutter SDK absent). |

The runner refuses to stay loaded unless the output shape passes `isLegacyRoadDamageOutputShape`: batch 1, 8 channels, 8400 anchors. A RoadSense `[1, 9, 8400]` tensor fails that gate. **VERIFIED** by the new helper and by `spec_decoder_math.py`. The Dart unit test that calls the helper was **not executed** (no Flutter).

Decode (`legacy_decoder.dart`, previously inlined in the runner):

- For each anchor, argmax over channels 4..7.
- Scores `<= 0` never win, because the running best starts at 0 and the comparison is `>`.
- Thresholds: D00 0.35, D10 0.35, D20 0.30, D40 0.40. A score below the threshold is dropped (`bestScore < thresh`).
- cx, cy, w, h are clamped to `[0, 1]`, then stored as top-left `x = cx - w/2`, `y = cy - h/2`.
- Class-aware NMS, IoU 0.45 (`nms.dart`).
- No letterbox undo.

This matches the tensor we measured (values on a real image fell in about `[0, 1]`, 8 channels). **PARTIALLY VERIFIED**: layout and ranges were measured; the Dart function was not run on-device.

## RoadSense model (not default)

| Item | Evidence | Tag |
|---|---|---|
| File | `road_damage_roadsense.tflite`, 37,347,282 bytes, SHA-256 `300798be…` | VERIFIED |
| Input | float32 NCHW `[1, 3, 640, 640]` | VERIFIED |
| Output | float32 `[1, 9, 8400]` | VERIFIED |
| Graph strings | `A2C2f`, `AAttn`, `C3k2`, `DWConv`, `Detect`, Ultralytics `_NormalizeCoords`. `A2C2f` is a YOLO12 block, not the YOLOv8 C2f-only head. The string `YOLO12` itself is absent. “s” width is a Dart comment, not a parameter count. | PARTIALLY VERIFIED |
| Preprocess | `letterboxProcess`, pad RGB 114, then `imageToNchwFloat32` | VERIFIED (source) |
| Classes kept | D00, D10, D20. Index 3 is ignored. Index 4 is Repair and is not shown as damage. | VERIFIED (source) |
| When it loads | Only if `USE_ROADSENSE_MODEL` is true. Hybrid mode can also run the legacy file restricted to D40 (`onlyD40: true`). | VERIFIED (source). **NOT VERIFIED** at runtime on Android. |

## Export pipeline that did not produce these files

`training/src/export.py` expects a `.pt` and writes per-agent TFLite/ONNX. `training/config/model-bundles.json` still says `REPLACE_AFTER_EXPORT`. Those ONNX files are not in the tree. **VERIFIED** absence. So the shipped Android asset is not traceable to the checked-in export script.

## Camera entry

`camera_detection_screen.dart`: `ResolutionPreset.high`, JPEG, audio off, no frame stream. One `takePicture`, then `detectAll` on the file, then SQLite, then `ResultScreen`. **VERIFIED** as source behavior. **NOT VERIFIED** on a device.
