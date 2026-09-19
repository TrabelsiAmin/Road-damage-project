# TariqMap Flutter app

Offline-first road inspection client.

## Status

| Feature | Status |
| --- | --- |
| Gallery import | **CURRENTLY WORKING** — mock boxes if no TFLite (banner on) |
| Result screen / SQLite queue / sync client | **CURRENTLY WORKING** against the **DEMO/MOCK** backend |
| Video import | **CURRENTLY WORKING** frame pipeline; **REQUIRES MODEL**; no muxed output video |
| Live camera | **CURRENTLY WORKING** YUV/BGRA path + preview-aligned overlay; **REQUIRES MODEL** |
| TFLite | Runner + letterbox **CURRENTLY WORKING**; weights **REQUIRES MODEL** |
| Web | Mock-only (no `dart:io` camera/video extract) |

## Run

```bash
flutter pub get
flutter test
flutter run
```

Android emulator/device is the intended target. iOS project files were not part of the original import.

## Inference contract

1. EXIF orientation (stills)
2. Letterbox to 640×640, pad value 114
3. RGB float32 `[0, 1]`, NHWC
4. YOLOv8 `cx, cy, w, h` + class scores
5. Inverse letterbox → normalised original-image boxes
6. Class-aware NMS (IoU 0.45, conf 0.35)

Live camera does **not** assume JPEG. Android frames are converted from YUV420 (or NV21); iOS from BGRA8888. Boxes are painted on the `CameraPreview` `AspectRatio`, not the full-screen `Stack`.

Video frames are real JPEGs from `video_thumbnail`. Mock detections are disabled on that path.

## Installing a real model

After `training` export + `verify_tflite`:

1. Put `cracks.tflite` / `pavement.tflite` / `surface.tflite` in `assets/models/`
2. List them in `pubspec.yaml` assets (directory already included)
3. Put SHA-256 into `model-bundles.json`
4. Cold-start the app — Model Status should show LOADED, not MOCK
