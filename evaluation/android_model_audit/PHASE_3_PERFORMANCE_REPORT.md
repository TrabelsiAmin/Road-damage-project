# Phase 3 performance report

No detection behavior and no weights were changed. No speedup is claimed for the interpreter, image decode, sync, API, dashboard, or upload, because those were not measured on a device or under a representative load.

## Environment and limits

- Machine: Linux cloud agent. Flutter 3.47.9, Dart 3.13.7, Java 21.0.12, Vite 6.4.4.
- Not present: Android SDK, `adb`, emulator, a phone.
- The Flutter process is a host VM process. Its timings are not Android timings.
- `dashboard/dist` is gitignored. The production build completed in about 2 seconds. That is a bundler time, not a page-load time.
- No `.pt` or `.onnx` is in the tree. The default model file was not loaded for a benchmark.

## What was measured

| Probe | Method | Result | Decision |
| --- | --- | --- | --- |
| Duplicate classifier | 1,500 synthetic observations, distinct ids, latitudes spaced by 0.01 degrees, empty agent-run and detection lists. `time.perf_counter` around `classify_duplicates`. | 0.077 seconds. 0 confirmed, 0 possible, `deleted` 0, `merged` 0. | No code change. The nested place-and-time loop is quadratic. 1,500 spaced rows do not exercise that branch. A production export could be slower. This was not optimized. |
| Dashboard unit tests | Vitest 5, 19 files. | 93 tests, about 0.7 seconds of runner time. | Not a runtime budget. |
| Python contract and recovery tests | unittest. | 32 tests in 0.061 seconds. | Not a runtime budget. |
| Flutter tests | `flutter test` on the host. | About 15 seconds, 134 passed, 13 failed on missing fixtures. | Not a device budget. |

## What was inspected and not changed

| Area | Inspection | Change |
| --- | --- | --- |
| Interpreter lifecycle | `TfLiteAgentRunner` assigns `_interpreter` from `Interpreter.fromFile` once during load and calls `runForMultipleInputs` on that instance. `dispose` closes it. The threshold reload does not construct a new interpreter. | None. Creating it once was already the code. No frame-time measurement. |
| Image decode memory | EXIF orientation 1 and missing or invalid tags return the original bytes. Orientations 3, 6, and 8 decode, bake once, and encode JPEG quality 95 once before the existing compressor. | None for speed. The extra decode exists only for rotated images. Peak bytes were not measured. |
| Local queries | Sync still lists pending and failed rows, then walks them. The new cap stops a row at `maxRetries` instead of uploading it again. | Correctness, not a measured query improvement. |
| Sync batching | One observation per loop iteration, same as before. | No batching change. A batch API was not measured, so none was added. |
| API | FastAPI validation tests hit the local test client. | No query or index change. |
| Dashboard lists | `fetchObservations` caps a page at 500 and returns `truncated`. Older pages load on request and merge by id. | This bounds one response. It is not a claimed faster render. No browser trace was captured. |
| Upload size | Rotated photos are JPEG 95 once, then the existing WebP step. Upright photos are not re-encoded by the EXIF step. | No before/after byte counts on real photos. |

## Bottleneck decision

The only number taken before a possible change was the diagnostic microbench, and it was not slow enough, or representative enough, to justify a rewrite. Interpreter reuse, page size 500, and the retry cap were already required by correctness or were already how the code worked. They are not reported as speedups.

## Status

| Item | Status |
| --- | --- |
| Diagnostic microbench on synthetic rows | VERIFIED as a host timing only |
| Interpreter, decode memory, SQLite, sync batch, API, dashboard paint, upload size | NOT VERIFIED. Not measured on Android |
| Unmeasured speedup | NOT APPLICABLE. None claimed |
