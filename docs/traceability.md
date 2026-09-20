# TariqMap traceability matrix

This document maps the **validated conception** to the repository.
Week 1 of the project was specification-only. Status words are used strictly:

| Status | Meaning |
| --- | --- |
| **PLANNED** | Specified, not built |
| **IMPLEMENTED** | Code or config exists |
| **TESTED** | Automated test covers the behaviour |
| **VALIDATED** | Empirically confirmed (metrics, field, or recorded probe) |
| **PARTIAL** | Some of the above, with a named gap |

Nothing in this matrix claims a production SIG, RAG, or trained mAP.
No evaluation numbers are recorded here. See `training/reports/METRICS.md`
(`NOT RUN`).

ML path that must remain: **baseline → teacher → KD → student → quantization → deploy**.
KD is a stub (`training/src/distill.py`) until a teacher checkpoint exists.
Deployment keeps **three agent runners** (WP2/WP3/WP4). RDD may be converted as
one dump, then split by `prepare_dataset.py`. WP3 (pavement D20/D40) is the
training and inference **priority**.

## Work packages → folders

| WP | Name | Classes / duty | Primary folders |
| --- | --- | --- | --- |
| WP1 | Acquisition & Orchestration | Image / video / camera → validate → route | `app/lib/screens/`, `app/lib/services/detection_service.dart`, `app/lib/services/video_frame_extractor.dart`, `training/src/process_video.py` |
| WP2 | Agent Fissures | D00, D10 only | `app/lib/services/tflite_agent_runner.dart` (cracks), `training/config/cracks.yaml` |
| WP3 | Agent Chaussée (**priority**) | D20, D40 only. Visual 2D. **No depth** | `training/config/pavement.yaml`, `training/src/train.py --agent pavement`, `pavement.tflite` (not bundled) |
| WP4 | Agent Marquage & Surface | D50, D60, D90 | `training/config/surface.yaml` |
| WP5 | SIG, attribution, incidents, decision | GPS → route/segment/institution → incident lifecycle. RAG = support only | `app/lib/services/territorial_service.dart`, `app/lib/models/incident.dart`, `backend/lifecycle.py` |

Flow: Acquisition → Validation/Prétraitement → Orchestration → WP2/WP3/WP4 → results → WP5 →
`DETECTED → ANALYZED → ASSIGNED → IN_PROGRESS → RESOLVED → ARCHIVED`.

## Domain UML coverage

| Entity | Status | Component |
| --- | --- | --- |
| Image | IMPLEMENTED | Observation.imagePath + SQLite / files |
| Observation | IMPLEMENTED / TESTED | `app/lib/models/observation.dart` |
| Detection | IMPLEMENTED / TESTED | Detection (`detectionId` derived, `classId`, `confidence`, `bbox`, `detectedAt`) |
| Defect | PLANNED | Taxonomy only (D-codes). No Defect table |
| Report | PLANNED | Result screen is not a signed report |
| GPSCoordinate | PARTIAL | lat/lon + `gpsAvailable`; no dedicated type |
| Road / RoadSegment / Territory | PLANNED | TerritorialService returns unmatched stubs |
| Incident | PARTIAL | Lifecycle constants only; no incident store |
| Intervention | PLANNED | — |
| User | PLANNED | Actor is selected; no auth/user model |
| Actor | IMPLEMENTED / TESTED | Three peers in `TariqMapConstants.actors` |
| Recommendation | PLANNED | RAG decision-support, not built |

## Matrix

| # | Specification requirement | WP | Repository component | Status | Missing implementation | Planned change | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | D40 potholes belong only to WP3 Agent Chaussée | WP3 | `TariqMapConstants.agentClasses['pavement']`, `training/config/pavement.yaml`, `prepare_dataset.py` | **TESTED** | Real `pavement.tflite` weights | Train WP3 baseline (sibling agent), then export | `observation_test` `agentFor('D40')`; `test_contracts.py`; `test_distill.py` |
| 2 | D20 alligator only on WP3; visual 2D; **no depth estimation** | WP3 | `depthEstimationEnabled = false`; D90 limitation in class map | **IMPLEMENTED** / **TESTED** (flag) | None for the prohibition | Keep 2D-only in model cards | `gps_enrichment_test` (flag); class-map JSON `limitation` |
| 3 | WP3 small-object (pothole/alligator) evaluation | WP3 | `docs/evaluation.md`, `baseline.yaml` candidates yolov8s/960, `finetune.yaml` objective | **PLANNED** | No labeled test split run; no small-object recall | After baseline: `src.evaluate` on D20/D40 subset | `src.evaluate` writes `NOT_RUN` without weights (`test_rdd_pipeline.py`) |
| 4 | WP2 only D00 longitudinal + D10 transverse | WP2 | `cracks.yaml`, agentClasses | **TESTED** | Real `cracks.tflite` | Train after WP3 baseline | `test_contracts.py`; `observation_test` disjoint classes |
| 5 | WP4 D50 faded crossing, D60 faded lane, D90 visual rutting; separate from WP3 | WP4 | `surface.yaml`; D43→D60, D44→D50 mapping | **PARTIAL** | D90 absent from RDD; D50/D60 only if D43/D44 exist | Skip surface train if `analyze_labeled_dataset` reports missing | `test_rdd_pipeline.py` D43/D44/D90 |
| 6 | Do not collapse WP2/WP3/WP4 into one YOLO at deploy | WP2–4 | Three TFLite runners in `DetectionService`; `rdd_unified.yaml` is audit-only | **IMPLEMENTED** / **TESTED** | Bundled weights | Keep three `*.tflite` files | `test_contracts.py`; `test_distill.py` rejects agent `unified` |
| 7 | Video = extract frames; never pass MP4 to image detector | WP1 | `VideoFrameExtractor` + `detectAllBytes`; `docs/video-detection.md` | **IMPLEMENTED** / **TESTED** (extractor/muxer) | Encoded MP4 needs FFmpeg on PATH (not on stock Android/iOS) | Keep contact sheet fallback | `video_muxer_test.dart`; `test_mux_video.py` |
| 8 | Each video frame is an Observation with timestamp, source video, GPS if available | WP1 | `Observation.sourceVideoPath`, `frameTimestampMs`; `VideoImportScreen` persists via repository | **IMPLEMENTED** / **TESTED** (model + memory repo) | Device-level video persist not widget-tested | Copy JPEG out of session temp (done) | `gps_enrichment_test` sourceVideoPath |
| 9 | Flutter image / video / camera capture | WP1 | `home_screen`, `video_import_screen`, `camera_detection_screen` | **IMPLEMENTED** | Camera/video widget tests skipped (native plugins) | Keep three entry points | `home_screen_test` is a stub; gallery/result tests exist |
| 10 | GPS → SIG → route/segment/institution | WP5 | `TerritorialService.match` | **PLANNED** (stub) / **TESTED** (unmatched behaviour) | No road graph, no PostGIS, no owner from coordinates | Replace stub with SIG match API; never guess | `gps_enrichment_test` unmatched owner |
| 11 | If no GPS: keep observation, later enrichment | WP5 / WP1 | `gpsAvailable`, lat/lon 0 still saved; gallery/camera/video catch GPS errors | **IMPLEMENTED** / **TESTED** | No later enrichment job | WP5 enrichment when a fix is obtained | `gps_enrichment_test`; sync_state_test already used 0,0 |
| 12 | Three peer actors: Municipalité, Ministère, Tunisie Autoroutes. **No hierarchy** | WP5 | `TariqMapConstants.actors`, `WelcomeScreen`, `backend/lifecycle.py` | **IMPLEMENTED** / **TESTED** | No workspace auth | Do not rank actors in UI or SIG stub | `gps_enrichment_test`; `backend/tests/test_lifecycle.py` |
| 13 | Incident lifecycle DETECTED→ANALYZED→ASSIGNED→IN_PROGRESS→RESOLVED→ARCHIVED | WP5 | `app/lib/models/incident.dart`, `backend/lifecycle.py`, `GET /v1/contract` | **PARTIAL** (constants) | No incident entity, no PATCH machine, no UI | Persist incidents after operator confirm | Dart + Python lifecycle tests |
| 14 | Incident fields: incidentId, detectedAt, severity, priority, status, description | WP5 | Observation has id, createdAt, priorityScore/Label | **PLANNED** | No Incident model instance / table | Add after observation→incident confirm | — |
| 15 | RAG = decision support only; actor decides | WP5 | Flag `ragIsDecisionSupportOnly`; docs | **PLANNED** | No RAG index, no LLM, no recommendation UI | Introduce retrieval over manuals only as advice | Constant test |
| 16 | Teacher → KD → Student → Quantization → Deploy | ML | `src.train` baseline; `src.distill` stub; `src.export` float16/int8 | **PARTIAL** | No teacher, no KD loop, no `.pt`/`.tflite` | Baseline first (in progress elsewhere); then teacher/KD | `test_distill.py` `metrics is None` |
| 17 | First baseline then teacher/student/distill/opt/eval/deploy | ML | README + `docs/training.md` order; WP3 first | **PLANNED** (docs) | No completed baseline on this clone | Do not start a second 13GB RDD download / full train here | `evaluate` NOT_RUN guard |
| 18 | On-device TFLite (letterbox, inverse map, NMS) | WP1–4 | `tflite_agent_runner.dart`, `letterbox_math.dart`, `nms.dart` | **IMPLEMENTED** / **TESTED** (code) | Weights **REQUIRES MODEL** | Install three verified bundles | `inference_pipeline_test.dart`, `nms_test.dart` |
| 19 | FastAPI observation ingest | WP5 | `backend/main.py` POST `/v1/observations` | **IMPLEMENTED** (demo/mock) | No auth, no disk, no GIS | Keep mock until real backend | Manual; contract unit tests |
| 20 | Offline SQLite observation log + sync queue | WP1 / WP5 | `observation_dao.dart`, `SyncCoordinator` | **IMPLEMENTED** / **TESTED** | Sync against mock only | Idempotent POST already | `sync_state_test.dart` |
| 21 | Orchestration: three independent agent calls; one failure does not drop others | WP1 | `DetectionService.detectAll` | **IMPLEMENTED** / **TESTED** | Real per-agent isolation on device | Keep parallel Future.wait | `observation_test` failedAgents |
| 22 | Detection: detectionId, classId, confidence, bbox, detectedAt | Domain | `Detection` getters + JSON aliases | **IMPLEMENTED** / **TESTED** | Runners do not yet stamp a UUID detectionId | Optional explicit ids at decode time | `coordinate_test` |
| 23 | Backend `/v1/roads/match`, `/v1/incidents` | WP5 | Documented in `docs/backend-contract.md` | **PLANNED** | Endpoints not in mock server (except `/v1/contract`) | Implement when SIG source is chosen | — |
| 24 | RDD labeled training; not Global Potholes | ML | `prepare_dataset.py` STOP; `download_rdd.py` | **IMPLEMENTED** / **TESTED** (guards) | Local 13.3 GB zip not in this worktree (sibling may fetch) | This agent must not re-download | `test_rdd_pipeline.py` |

## WP3 snapshot (priority)

| Item | Status |
| --- | --- |
| Class split D20/D40 only | TESTED |
| Separate pavement runner | IMPLEMENTED |
| Visual 2D / no depth | IMPLEMENTED (policy + docs) |
| Small-object protocol | PLANNED (eval not run) |
| YOLOv8 baseline metrics | NOT RUN — do not fabricate |
| Teacher / KD / student | STUB (`src.distill`) |
| Quantized TFLite on device | REQUIRES MODEL |

## Honesty constraints

- Do not write this system as if SIG/RAG/incidents are in production.
- Do not merge agents for convenience.
- Do not fill mAP tables. `src.distill` and `src.evaluate` return `metrics: null` when not run.
