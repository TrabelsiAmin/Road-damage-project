# Video detection

## Status

| Step | Status |
| --- | --- |
| Pick MP4 / MOV (and other `video_thumbnail` formats) | **CURRENTLY WORKING** |
| Read duration via `video_player` | **CURRENTLY WORKING** |
| Sample timestamps (interval + 40-frame cap) | **CURRENTLY WORKING** |
| Extract JPEG at each timestamp | **CURRENTLY WORKING** (platform thumbnail APIs) |
| Letterbox → TFLite → inverse letterbox → NMS | **CURRENTLY WORKING** (code) / **REQUIRES MODEL** (weights) |
| Annotated per-frame JPEG + contact sheet | **CURRENTLY WORKING** |
| Encoded annotated MP4 / MOV | **CURRENTLY WORKING** when FFmpeg CLI is on PATH (Linux/desktop, verified decode). **NOT AVAILABLE** on stock Android/iOS (no FFmpeg binary) |
| Fake boxes on video | **NOT USED** |

## Why the old path was wrong

`VideoImportScreen` used to call `DetectionService.detectAll(_videoFile)` on the **container file**. An image decoder cannot read an MP4. That produced either decode errors or, with the mock runner, the same invented boxes on every "frame".

## Current pipeline

```
Video file
  → VideoPlayerController.initialize()   (codec / duration / corruption)
  → VideoSampling.timestampsMs()         (interval, max 40 frames)
  → video_thumbnail JPEG at each t       (empty/failed timestamps recorded)
  → DetectionService.detectAllBytes(..., allowMock: false)
  → AnnotationRenderer (only if real boxes exist)
  → contact sheet of up to 12 annotated frames
  → FFmpeg concat + libx264 (if ffmpeg/ffprobe exist)
       → ffprobe (video stream + duration)
       → ffmpeg decode to null (must be silent)
       → save MP4 under app documents /tariqmap_videos/
  → session JPEG directory deleted on screen dispose; muxed MP4 is kept
```

Platform extraction uses Android `MediaMetadataRetriever` / iOS `AVAssetImageGenerator` through `video_thumbnail`. Desktop/training uses the same concat recipe via `python -m src.process_video`.

The encoded file is a **sampled-frame montage** (each JPEG held until the next sample timestamp), not a full original-fps re-encode of the source clip.

## Verified muxer test

On a machine with FFmpeg 6.x:

```bash
cd training
python -m unittest tests.test_mux_video
# also: flutter test test/unit/video_muxer_test.dart
```

Those tests synthesize or draw JPEGs, mux H.264 `yuv420p` +faststart, then require `ffprobe` duration > 0 and `ffmpeg -i out.mp4 -f null -` with empty stderr. Status is never `OK` without that decode.

There are **no inspection videos** in this git repository (gitignore). Tests use a generated `testsrc` clip / solid-color JPEGs.

## Error handling

| Failure | Behaviour |
| --- | --- |
| Unsupported / corrupted container | initialize() fails; message shown; no inference |
| Zero duration | rejected |
| Empty JPEG at timestamp | skipped, counted in the limitation banner |
| Large video | interval stretched so at most 40 frames cover the clip |
| Mock-only service | frames still extracted; **no mock boxes** |
| Inference exception | that frame is skipped; others continue |
| FFmpeg missing | contact sheet kept; banner explains MP4 needs FFmpeg on PATH |
| FFmpeg mux/decode error | contact sheet kept; mux status is FAILED, not OK |
| Temp JPEG files | `tmp/tariqmap_video_frames/<session>/`; cleaned on dispose |

## Desktop CLI

```bash
cd training
python -m src.process_video --input clip.mp4 --output /tmp/annotated.mp4 --fps 2
python -m src.process_video --verify-only /tmp/annotated.mp4
```
