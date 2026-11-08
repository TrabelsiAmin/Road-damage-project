# Executive summary — Android model audit

**Status: the Android detector is NOT scientifically validated.** mAP, precision, recall, and per-class AP are **NOT VERIFIED**. There are still zero label files.

HEAD `cd7d168`. No commit, no push, no retrain, no weight overwrite, no Supabase call.

## What Android loads

**VERIFIED.** With the default build (`USE_ROADSENSE_MODEL` unset), `DetectionService._createLegacyService` loads one agent, `road_damage`, from `app/assets/models/road_damage.tflite`.

Re-measured with `ai_edge_litert` on this Linux VM:

- float32 NHWC `[1, 640, 640, 3]` → `[1, 8, 8400]`
- 44,768,844 bytes (42.69 MiB)
- SHA-256 `830f99bd8c31c5d24138c16db7862dfb62293b96cc1dec241c36140bff8a813f` (matches `model_manager.dart`)
- embedded string `YOLOv8_Small_RDD`
- Linux invoke on a zero tensor: mean **112.4 ms**, n=8, XNNPACK, 2 threads. An earlier real-image loop on the same VM was mean **103.7 ms**, n=12. **Neither number is an Android result. Android latency is BLOCKED.**

`road_damage_roadsense.tflite` is a different graph: NCHW `[1, 3, 640, 640]` → `[1, 9, 8400]`, with YOLO12 blocks `A2C2f` and `AAttn`. It is not loaded unless the compile-time flag is true. The two files are not interchangeable. The legacy loader now rejects a `[1, 9, 8400]` output via `isLegacyRoadDamageOutputShape`.

## Dataset

**VERIFIED** from `git ls-tree`: 29,120 `.jpg` files under `Global_Potholes_Dataset-image/images`, no other extensions. `training/reports/global_potholes_audit.json` says `UNLABELED` and `image_count` 29120. `docs/dataset-audit.md` class counts and `dashboard/src/data/validation_metrics.json` mAP figures remain **NOT VERIFIED**. No `.pt`, no `.onnx`.

## What changed in source

Production stretch was **not** replaced with letterbox. The missing `.pt` does not prove which preprocess was exported. The current stretch is now a named function, `stretchToModelInput`, and the runner calls it. Decode math was moved to `decodeLegacyYoloOutput` without a layout change: scores stay at `output[0][4+c][anchor]`, boxes stay center-format normalized to the stretched canvas. Class strings in the app stay D00/D10/D20/D40. The Python scripts still say Crack/Pothole/Rutting/Uneven-Surface, with an explicit **UNPROVEN** comment. Those names were not renamed.

## Tests

| Suite | Before | After | Tag |
|---|---|---|---|
| `training/tests/test_contracts.py` | 2 passed | 2 passed | VERIFIED |
| dashboard vitest | 80 passed | 80 passed | VERIFIED |
| `lock_android_contract.py` | n/a | passed | VERIFIED |
| `spec_decoder_math.py` | n/a | passed | VERIFIED (Python mirror, not Dart) |
| Flutter unit tests, including the new ones | not run | not run | BLOCKED (no `flutter`, no `adb`, no device) |

## Defense pack

### Twelve answers a jury can be given

1. The phone build runs `road_damage.tflite`, four score channels, not the RoadSense file.
2. The file’s own string is `YOLOv8_Small_RDD`. That is an embedded label, not a training log.
3. Input is 640 RGB float32 divided by 255. Output is normalized cx, cy, w, h plus four scores.
4. Android shows D00, D10, D20, D40. A desktop script uses different English words. We did not prove they are the same classes.
5. We did not compute mAP. The committed image folder has no boxes.
6. The dashboard JSON that quotes mAP is not backed by a split or a results file in this repo.
7. The app stretches the photo to 640×640. Training code letterboxes. We did not change that, because the original checkpoint is missing.
8. NMS is class-aware at IoU 0.45. D40 is kept only at or above 0.40.
9. The settings slider is stored and is not read by the interpreter.
10. Offline means SQLite first. Sync is a later RPC. We did not call Supabase.
11. Timings in this audit are a Linux CPU. There was no phone.
12. RoadSense stays off. Turning it on would load a different tensor layout.

### Five-minute Android demo (only if a device is in the room)

Say, before touching the phone: “This demo shows capture, on-device inference, and a local save. It does not show measured accuracy.”

1. Open the app. Model status should say the legacy RDD model is active and RoadSense is off. If the banner says mock, stop: that is the web path, not Android.
2. Airplane mode on. Capture one photo. Wait for “Analyzing…”. Open the result. Point at the class code and the confidence. Do not translate D40 into “pothole mAP”.
3. Show the photo still listed in the offline queue as pending.
4. Do not move the confidence slider and claim the boxes changed. It does not feed the model.
5. Turn the network back only if the jury asks to see the queue, and do not promise the server accepted the row unless that environment was prepared. This audit did not verify production sync.

### Fifteen questions, and the honest reply

1. What is the mAP? Not measured.
2. Is D40 weak, as the dashboard says? That number is not reproducible here.
3. How many potholes are in the 29,120 images? Unknown. No labels.
4. Is this YOLOv8 or YOLO12? The default file says YOLOv8_Small_RDD. The other file has YOLO12 blocks and is off.
5. Why do some pictures say Uneven-Surface? That string is only in `test_images.py`. The app does not use it.
6. Did you letterbox? Not on the default model. RoadSense does. We left the default as stretch.
7. What is the Android FPS? Not measured. Linux invoke was about 104–112 ms, CPU only, preprocess excluded.
8. Does it run offline? The code saves to SQLite before upload. Not verified on a phone in this audit.
9. What if the model file is corrupt? SHA-256 is checked. Failure becomes an empty result with an error, not a silent mock, on Android.
10. Are the four classes RDD2022? The app says so. The weight file does not contain the names. Treat the names as the app contract, not as a proven training taxonomy.
11. Can we retrain tonight? Not on this folder. It is unlabeled. This audit did not retrain.
12. Is the slider the operating threshold? No. Thresholds are D00/D10 0.35, D20 0.30, D40 0.40 inside the runner.
13. Did you test the camera? No device and no emulator.
14. Is there a license? No LICENSE file.
15. Who owns the repo? TrabelsiAmin. AbderrahimNeji has commits and merged dashboard/iOS PRs. He is not the owner.

### Claims that must not be made

- Any mAP, precision, recall, or F1 for either TFLite file.
- That the 29,120 images contain 12,055 potholes or any other class count from `docs/dataset-audit.md`.
- That Crack/Pothole/Rutting/Uneven-Surface are the trained names.
- That Linux milliseconds are phone milliseconds.
- That letterbox and stretch were proven equivalent.
- That RoadSense and the legacy file are the same model.
- That Supabase sync succeeded.
- That the settings slider calibrates confidence.
