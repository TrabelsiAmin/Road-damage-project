# Phase 13 external evidence

Cutoff: files strictly after `evaluation/android_model_audit/PHASE_12_FINAL_READINESS.md`, mtime `2026-11-07 12:04:07 +0000` (epoch 1794053047). HEAD `cd7d16898465174c06a1362953c052f156e0485b`.

Searched: the repo working tree (excluding `.git`, `dashboard/node_modules`, `dashboard/dist`, `app/build`, `__pycache__`), `/tmp` to depth 4, `/home/ubuntu` to depth 4 (excluding `.cache`, `.npm`, `.gradle`, `sdk`, `Android`), `/opt`, `/mnt`, `/var/tmp`, `/cursor`, `/cursor/stores`. These paths do not exist: `/tmp/uploads`, `/tmp/drop`, `/home/ubuntu/uploads`, `/home/ubuntu/drop`, `/opt/uploads`, `/home/ubuntu/Downloads`, `/home/ubuntu/Desktop`.

Files newer than the cutoff are not evidence: the Phase 12 readiness file itself, `/tmp/hsperfdata_ubuntu/25648` (JVM perf data), `/tmp/agent-store-fuse.log` (a `ListAgentStoreDirectory` call, HTTP 200), and `.git/index`. Phase 12 already recorded `/tmp/adb.1000.log`. It was not newer than this cutoff and was not re-read as new evidence.

`PHASE_11_FINAL_ACCEPTANCE_CHECKLIST.md` was not edited. No acceptance item changed.

| Item | Exists | Path | Contents | Supports | Still missing |
| --- | --- | --- | --- | --- | --- |
| Emulator or device test logs | No | — | NOT PROVIDED | None. Item 2 stays NOT DONE | Any logcat or test log from a phone or emulator |
| Install and launch | No | — | NOT PROVIDED | None. Item 1 stays NOT DONE | `adb install` and a launch of the arm64 APK |
| TFLite runtime logs, both paths | No | — | NOT PROVIDED | None. Item 3 stays NOT DONE | An Android log for `road_damage.tflite`, and a separate log for RoadSense only if `USE_ROADSENSE_MODEL` was set |
| Original annotations and license | No | — | NOT PROVIDED | None. Item 5 stays NOT DONE | Real YOLO, COCO, VOC, or CSV labels, and a license |
| Training or export configuration | No | — | NOT PROVIDED | None | A config or export log tied to these TFLite bytes |
| Authoritative class-index mapping | No | — | NOT PROVIDED. Mapping stays UNKNOWN | None. Item 5 stays NOT DONE | Evidence that these weights use a stated index order |
| Non-debug upload certificate | No | — | NOT PROVIDED. `app/android/key.properties` is still absent | None. Item 4 stays NOT DONE | `apksigner` or `jarsigner` output whose subject is not `CN=Android Debug` |
| Production Supabase approval | No | — | NOT PROVIDED | None. Item 6 stays NOT DONE | A recorded approval. The SQL file was not applied |

Scientific evaluation was not run. Regression was not re-executed. The last run remains Phase 11: analyze clean, flutter test 149/149, Python 49, SQL contract OK, spec math OK, vitest 93, Vite OK. Nothing was committed or pushed.
