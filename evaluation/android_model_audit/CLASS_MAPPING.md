# Class mapping

**Decision: app labels were not renamed.** Evidence does not prove that the four TFLite channels are Crack / Pothole / Rutting / Uneven-Surface.

## Evidence table

| Source | Index 0 | 1 | 2 | 3 | 4 | Proves the trained names? | Tag |
|---|---|---|---|---|---|---|---|
| `tflite_agent_runner.dart` `_classNames` | D00 | D10 | D20 | D40 | — | App contract only | VERIFIED as the strings Android uses |
| `TariqMapConstants.labels` | Longitudinal crack | Transverse crack | Alligator crack | Pothole | — | English gloss of the D-codes, not file metadata | VERIFIED as UI copy |
| `model-bundles.json` (app) | classes D00 D10 D20 D40 | | | | | Manifest, no names tensor | VERIFIED |
| `roadsense_decoder.dart` | D00 | D10 | D20 | D40 ignored | Repair | Different model, 5 scores | VERIFIED as source. Repair max on a 12-image Linux sample was 0.0 (prior run), **PARTIALLY VERIFIED** |
| `training/config/source-class-map.json` | D00 id 0 | D10 id 1 | D20 id 2 | D40 id 3 | D50… | A declared map for a dataset that is not in the repo | NOT VERIFIED against boxes |
| `training/config/cracks.yaml` etc. | separate agents, paths `data/processed/...` | | | | | Those folders are absent | NOT VERIFIED |
| TFLite metadata | string `YOLOv8_Small_RDD` only | | | | | No class-name list inside the file | VERIFIED absence |
| `test_images.py` and `test_single_image.py` | Crack | Pothole | Rutting | Uneven-Surface | — | Hard-coded. `inference_results/result_more_0.jpg` draws “Uneven-Surface 0.49” | VERIFIED that the script uses those words. **NOT VERIFIED** as the true taxonomy |
| `dashboard/.../validation_metrics.json` | D00/D10/D20/D40 with mAP | | | | | No results log | NOT VERIFIED |
| RDD2022 public convention | D00 longitudinal, D10 transverse, D20 alligator, D40 pothole | | | | | A public convention. It does not prove this weight file was trained with it | NOT VERIFIED for these weights |

Index alignment between the script and the app would mean index 3 is both “Uneven-Surface” and “D40 Pothole”. Those are different defects. Nothing in the checkpoint or in labels decides which gloss is true. **The Flutter strings stay.** The Python lists stay, with a comment that they are unproven, so old drawings remain comparable and nobody “fixes” the app from the script.

`lock_android_contract.py` fails if the app codes change or if the script warning is removed. That script passed.
