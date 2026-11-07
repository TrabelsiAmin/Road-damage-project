# Robustness

**QUALITATIVE. Not mAP. Not Android.**

Host: Linux VM, CPU, `road_damage.tflite`, stretch to 640, production thresholds (D00/D10 0.35, D20 0.30, D40 0.40). Five unlabeled images from the sparse sample. Transforms were written under `/tmp/tariqmap-evaluation/android_model_audit/tmp-images`, not into the dataset.

This run counts **pre-NMS anchors** that already pass the class threshold. It is a different statistic from the earlier post-NMS “kept boxes” (2 D20 on 12 images). Do not mix them.

| Transform | Pre-NMS candidates on the 5 images | Mean | Tag |
|---|---|---:|---|
| identity | 11, 0, 0, 0, 0 | 2.2 | VERIFIED count |
| dark ×0.4 | 7, 0, 0, 0, 0 | 1.4 | VERIFIED count |
| bright ×1.6 | 6, 0, 0, 0, 0 | 1.2 | VERIFIED count |
| Gaussian blur 15×15 | 0, 0, 0, 0, 0 | 0 | VERIFIED count |
| JPEG quality 20 | 0, 0, 0, 0, 0 | 0 | VERIFIED count |
| Gaussian noise σ=18 | 0, 0, 0, 0, 0 | 0 | VERIFIED count |
| rotation 5° | 9, 0, 0, 0, 0 | 1.8 | VERIFIED count |

Interpretation **PARTIALLY VERIFIED** at most: four of five images already produce zero candidates, so “dropped to zero” is not a robustness curve. Blur, heavy JPEG, and noise removed the only image’s candidates. That does not say how many of those 11 anchors were true damage. There is no negative set and no Tunisian day/night set in the repo (`docs/ml-evaluation.md` asks for one). That set is **NOT AVAILABLE**.

Source file: `robustness_counts.json`.
