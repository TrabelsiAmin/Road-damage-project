# Preprocessing

## Per model

| Model | What the Android code does | What training/export code does | Decision this audit |
|---|---|---|---|
| `road_damage.tflite` (default) | `img.decodeImage` **without** EXIF bake, then `stretchToModelInput` → `copyResize` to 640×640, RGB `/255`, NHWC. Boxes are in that stretched frame. No pad removal. | `training/src/train.py` uses Ultralytics, which letterboxes. `export.py` does not show a stretch flag. The `.pt` is missing. | **Did not switch to letterbox.** Missing weights, so the exported preprocess is **NOT VERIFIED**. Current stretch is now locked by `stretchToModelInput` and `legacy_stretch_contract_test.dart` (Dart test **BLOCKED**, not run). |
| `road_damage_roadsense.tflite` | `decodeAndOrient`, `letterboxProcess` pad 114, NCHW `/255`, then undo pad in `toOriginalNormalized`. | Same Ultralytics letterbox family. Still no `.pt`. | **Not modified.** It already letterboxes, and it is off by default. |

## Measured disagreement (Linux, one image)

Prior run on `b784e91c…`, 480×640, same legacy weights, confidence floor 0.25:

| Preprocess | Class | Score | Box xywh (normalized) |
|---|---|---:|---|
| Stretch | D20 | 0.629 | 0.352, 0.687, 0.189, 0.197 |
| Letterbox 114 | D20 | 0.556 | 0.358, 0.654, 0.173, 0.140 |

**VERIFIED** as a numeric difference on that image. It is not an accuracy delta. It is why a silent swap would move boxes.

## EXIF — PARTIALLY VERIFIED (code only)

- Camera screen stores width/height from `decodeAndOrient` (`camera_detection_screen.dart`).
- Legacy inference decodes with `img.decodeImage` and does not bake orientation.
- `AnnotatedImageWidget` displays with `Image.file`, which applies EXIF.
- RoadSense bakes EXIF before letterbox.

If a camera JPEG has orientation other than 1, the box frame and the displayed frame can disagree. **NOT VERIFIED** on an Android capture. Not changed, because it is part of the unproven preprocess and there is no device photo in this audit.

## Settings slider — VERIFIED (source)

`settings_screen.dart` reads and writes `confidence_threshold`. Grep shows no other reader. The runner uses `_classThresholds` only. Moving the slider does not change Android detections. Left unchanged so we do not invent a new global threshold on top of uncalibrated per-class values.

## Tests that lock stretch

`legacy_stretch_contract_test.dart` expects a 640×480 image to become 640×640 with the top-center pixel still image content, while `letterboxProcess` on the same image has a non-zero `padY` and a gray-114 top pixel. That test did not run here.
