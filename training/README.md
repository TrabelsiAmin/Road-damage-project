# TariqMap training package

Python tooling for RDD conversion, dataset audit, YOLOv8 train/eval/export.

Requires a labeled RDD extract. Refuses `Global_Potholes_Dataset-image`.

```bash
pip install -r requirements.txt
python -m unittest discover -s tests
python -m src.download_rdd
```
