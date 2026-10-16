"""
validate_models.py
Compare one or more detection models on the RDD2022 labeled split, per class.

Usage examples
--------------
python validate_models.py --data /path/to/rdd2022/data.yaml \
    --model roadsense=roadsense_best.pt \
    --model old=old_model.pt

# Old model only available as .tflite (needs `pip install tensorflow` or ai-edge-litert):
python validate_models.py --data data.yaml \
    --model roadsense=roadsense_best.pt \
    --model old=app/assets/models/road_damage.tflite

Notes
-----
* Only D00, D10, D20, D40 are reported. "Repair" / "D99" are ignored.
* Class matching is done by NAME. Ultralytics evaluates by class INDEX, so if the
  dataset's class order differs from a model's order the numbers would be wrong.
  This script checks that and stops with a clear message unless --force is given.
"""
import argparse
import csv
import sys
from pathlib import Path

import yaml
from ultralytics import YOLO

TARGET = ["D00", "D10", "D20", "D40"]


def load_dataset_names(data_yaml: Path):
    with open(data_yaml, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    names = cfg.get("names")
    if isinstance(names, list):
        names = {i: n for i, n in enumerate(names)}
    return {int(k): str(v) for k, v in names.items()}


def model_names(model):
    names = model.names
    if isinstance(names, list):
        names = {i: n for i, n in enumerate(names)}
    return {int(k): str(v) for k, v in names.items()}


def check_alignment(label, m_names, d_names, force):
    """Compare names at each index for the target classes."""
    problems = []
    for cls in TARGET:
        m_idx = [i for i, n in m_names.items() if n == cls]
        d_idx = [i for i, n in d_names.items() if n == cls]
        if not m_idx:
            problems.append(f"{cls} missing from model names")
        elif not d_idx:
            problems.append(f"{cls} missing from dataset names")
        elif m_idx[0] != d_idx[0]:
            problems.append(f"{cls}: model index {m_idx[0]} != dataset index {d_idx[0]}")
    if problems:
        print(f"\n[{label}] CLASS ORDER MISMATCH between model and dataset:")
        for p in problems:
            print("  -", p)
        print(f"  model:   {m_names}\n  dataset: {d_names}")
        if not force:
            print("  Fix the dataset yaml (or remap labels) so indices match, or rerun with --force.")
            return False
        print("  --force given: continuing, results may be WRONG.")
    return True


def run_one(label, path, args, d_names):
    print(f"\n=== {label}: {path} ===")
    model = YOLO(path)
    if path.lower().endswith(".pt"):
        m_names = model_names(model)
        print("model.names:", m_names)
        if not check_alignment(label, m_names, d_names, args.force):
            return None
    else:
        print("Non-.pt model: cannot read its class names automatically; "
              "assuming the dataset's class order matches the model.")
        m_names = d_names

    res = model.val(
        data=args.data,
        split=args.split,
        imgsz=args.imgsz,
        conf=args.conf,
        iou=args.iou,
        batch=args.batch,
        device=args.device,
        plots=False,
        verbose=False,
    )
    box = res.box
    # per-class arrays are aligned with box.ap_class_index
    idx = list(box.ap_class_index)
    rows = {}
    for pos, cls_id in enumerate(idx):
        name = res.names[int(cls_id)] if hasattr(res, "names") else m_names.get(int(cls_id), str(cls_id))
        if name not in TARGET:
            continue
        rows[name] = {
            "precision": float(box.p[pos]),
            "recall": float(box.r[pos]),
            "mAP50": float(box.ap50[pos]),
            "mAP50-95": float(box.ap[pos]),
        }
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True, help="path to RDD2022 data.yaml (YOLO format)")
    ap.add_argument("--model", action="append", required=True,
                    help="label=path (repeat for each model)")
    ap.add_argument("--split", default="test", choices=["val", "test"])
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--conf", type=float, default=0.001, help="low conf is standard for mAP")
    ap.add_argument("--iou", type=float, default=0.6)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--device", default=None, help="e.g. 0 or cpu")
    ap.add_argument("--out", default="validation_results.csv")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    d_names = load_dataset_names(Path(args.data))
    print("dataset names:", d_names)

    all_results = {}
    for item in args.model:
        if "=" not in item:
            sys.exit(f"--model must be label=path, got: {item}")
        label, path = item.split("=", 1)
        r = run_one(label, path, args, d_names)
        if r is not None:
            all_results[label] = r

    if not all_results:
        sys.exit("No model produced results.")

    # Print table
    print("\n================ RESULTS (split=%s, imgsz=%d) ================" % (args.split, args.imgsz))
    header = f"{'model':<14}{'class':<8}{'P':>8}{'R':>8}{'mAP50':>9}{'mAP50-95':>10}"
    print(header)
    print("-" * len(header))
    for label, rows in all_results.items():
        vals = []
        for cls in TARGET:
            r = rows.get(cls)
            if r is None:
                print(f"{label:<14}{cls:<8}{'n/a':>8}")
                continue
            vals.append(r)
            print(f"{label:<14}{cls:<8}{r['precision']:>8.3f}{r['recall']:>8.3f}"
                  f"{r['mAP50']:>9.3f}{r['mAP50-95']:>10.3f}")
        if vals:
            n = len(vals)
            print(f"{label:<14}{'MEAN':<8}"
                  f"{sum(v['precision'] for v in vals)/n:>8.3f}"
                  f"{sum(v['recall'] for v in vals)/n:>8.3f}"
                  f"{sum(v['mAP50'] for v in vals)/n:>9.3f}"
                  f"{sum(v['mAP50-95'] for v in vals)/n:>10.3f}")
        print()

    with open(args.out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["model", "class", "precision", "recall", "mAP50", "mAP50-95"])
        for label, rows in all_results.items():
            for cls in TARGET:
                r = rows.get(cls)
                if r:
                    w.writerow([label, cls, r["precision"], r["recall"], r["mAP50"], r["mAP50-95"]])
    print("Saved:", args.out)


if __name__ == "__main__":
    main()
