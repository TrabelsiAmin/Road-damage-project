# Phase 9 final readiness

Scientific evaluation is still blocked. Annotation tooling exists. It does not invent labels, a class map, or a split of the 29,120 images.

## Status

| Question | Status |
| --- | --- |
| JPEG count and duplicate pairs | VERIFIED again. 29,120 paths, 29,028 unique blobs, 92 pairs, 200 checked out, 0 annotations. |
| Public source of those JPEGs | NOT VERIFIED. First commit is `530096993889` (`Initial project import`) plus a Windows path. No URL. |
| Upstream annotations for those JPEGs | NOT VERIFIED. None in git. |
| Training export for these weights | NOT VERIFIED. Commit `30224f15` names `oracl4/RoadDamageDetection` and the file embeds `YOLOv8_Small_RDD`. Their `.pt` was not hashed against this TFLite. |
| Class mapping | NOT VERIFIED. Upstream notebook order matches the Flutter list. `test_images.py` does not. Mapping was not marked verified. |
| Schema and guidelines | VERIFIED as documents. Categories remain pending. |
| Validator and duplicate-aware split | VERIFIED on synthetic fixtures. Real split NOT APPLICABLE. |
| `evaluate_readiness.py` | VERIFIED. Synthetic COCO without a verified mapping still has `metrics: null` and exit 2. |
| Host regression | VERIFIED. Analyze clean, Flutter 149, Python 36, contract OK, spec math OK, vitest 93, vite OK. |
| Android rebuild | NOT EXECUTED. |
| Play release | Still blocked by the debug-signed AAB and the missing device run, in addition to the missing labels. |

## Blockers that remain

1. A real annotation file, reviewed, with provenance, for images that will be scored.
2. A mapping from those category ids to the TFLite channels, with evidence other than a guessed index order.
3. A duplicate-aware split run only after those labels exist.
4. An upload key and a device pass before Play.

## Git

HEAD `cd7d16898465174c06a1362953c052f156e0485b`. `git status --short` is 51 modified tracked files and 26 untracked paths, the same shape as Phase 8. Phase 9 files sit under the untracked `evaluation/` tree. Model checksums are unchanged. `Global_Potholes_Dataset-image` and `ios/` have no status lines. Nothing was committed or pushed.
