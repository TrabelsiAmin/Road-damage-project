# TariqMap training package

Python tooling for RDD conversion, dataset audit, YOLOv8 train/eval/export, and FFmpeg video mux.

Requires a labeled RDD extract. Refuses `Global_Potholes_Dataset-image`.

```bash
pip install -r requirements.txt
python -m unittest discover -s tests
python -m src.check_environment
python -m src.download_rdd --fetch-metadata
python -m src.process_video --input clip.mp4 --output /tmp/annotated.mp4 --fps 2
```

RDD2022 Figshare article 21431547 is the labeled dump (≈13.3 GB). Metadata from the last probe lives in `reports/rdd_access.json` and `reports/rdd2022_meta/`. Images are not vendored.

Training metrics: see `reports/METRICS.md` (currently **NOT RUN**).
