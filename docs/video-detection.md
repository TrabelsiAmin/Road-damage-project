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
| Encoded annotated MP4 / MOV | **NOT IMPLEMENTED** (documented limitation) |
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
  → session directory deleted on screen dispose
```

Platform extraction uses Android `MediaMetadataRetriever` / iOS `AVAssetImageGenerator` through `video_thumbnail`. That is the reliable Flutter path. A full FFmpeg kit is not bundled (size, licensing, maintenance).

## Error handling

| Failure | Behaviour |
| --- | --- |
| Unsupported / corrupted container | initialize() fails; message shown; no inference |
| Zero duration | rejected |
| Empty JPEG at timestamp | skipped, counted in the limitation banner |
| Large video | interval stretched so at most 40 frames cover the clip |
| Mock-only service | frames still extracted; **no mock boxes** |
| Inference exception | that frame is skipped; others continue |
| Temp files | `tmp/tariqmap_video_frames/<session>/`; cleaned on dispose |

## Limitation: no output video

Encoding an annotated MP4 on-device needs a muxer (FFmpeg or MediaCodec). Shipping that solely to draw boxes is brittle and easy to fake with a "success" path that never writes a valid movie. TariqMap therefore keeps **annotated JPEGs + a contact sheet**. If a muxed preview is required later, add it behind an explicit FFmpeg dependency and a round-trip test — do not claim it works before that.
