# End-to-end (code path only)

**NOT VERIFIED** on a device, and **not executed** against Supabase. No schema change. No request was sent.

## Offline capture — source VERIFIED, runtime NOT VERIFIED

1. `CameraDetectionScreen._capture` takes one JPEG (`ResolutionPreset.high`, audio off).
2. It reads EXIF-oriented dimensions for the row, then calls `DetectionService.detectAll` on the file. The legacy runner does not use that oriented image. See `PREPROCESSING_ANALYSIS.md`.
3. GPS is best-effort. On failure, latitude and longitude are stored as 0 (`camera_detection_screen.dart`).
4. `ObservationRepository.save` writes SQLite before navigation.
5. `ResultScreen` is opened from the stored row when the read-back succeeds.
6. Web (`kIsWeb`) uses `MockAgentRunner` and shows a mock banner. Android load failure uses `FailedAgentRunner` (empty detections plus an error), not the mock. **VERIFIED** in `detection_service.dart`.

## Sync — source VERIFIED, server NOT VERIFIED

`ObservationSyncCoordinator.syncPending` uploads pending and failed rows, marks `uploading`, and on success `synced`. Cancel returns the row to pending and does not delete local data. Backoff is exponential with jitter, cap 300 s. The client calls RPC `submit_observation` and can fall back to table inserts if the RPC is missing (`api_client.dart`).

`test_sync_simulation.py`, `test_rls.py`, and `test_supabase.py` target the live project. They were **not run**.

## What a pass would require

An Android device or emulator, a non-production Supabase project, and a test that captures one image in airplane mode, kills the app, relaunches, and confirms the SQLite row is still there, then syncs only to the non-production project. None of that was done. Tag for the whole chain: **NOT VERIFIED**.
