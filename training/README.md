# TariqMap training package

Python tooling for RDD conversion, dataset audit, YOLOv8 train/eval/export, KD stub, and FFmpeg video mux.

Requires a labeled RDD extract. Refuses `Global_Potholes_Dataset-image`.

WP3 pavement (`--agent pavement`, D20/D40) is the training priority. Keep three agent datasets after `prepare_dataset.py`.

Google Colab (CUDA): [`docs/wp3-training.md`](../docs/wp3-training.md) and `colab/WP3_YOLOv8_training.ipynb`. **Training: NOT YET EXECUTED.**

```bash
pip install -r requirements.txt
python -m unittest discover -s tests
python -m src.check_environment
python -m src.verify_wp3_dataset --root data/processed/pavement --yaml config/pavement.yaml
python -m src.distill --agent pavement --plan-only
python -m src.process_video --input clip.mp4 --output /tmp/annotated.mp4 --fps 2
```

RDD2022 Figshare article 21431547 was downloaded on 2026-09-20 (13,264,172,619 bytes, extract 38,385 XML). Images are not vendored. See `reports/dataset_report.json`.

Training metrics: see `reports/METRICS.md` (detector **NOT RUN** — no GPU). Distill reports write `metrics: null` until a teacher exists.
