"""TariqMap YOLOv8n training entry point.

Trains one agent at a time with:
- Deterministic seed
- Augmentation from augmentation.yaml
- Early stopping
- Best-checkpoint saving
- Per-class validation metrics on test split
- Model card generation

Usage:
    python -m src.train --agent cracks --data config/cracks.yaml --weights yolov8n.pt
    python -m src.train --agent pavement --data config/pavement.yaml --weights yolov8n.pt
    python -m src.train --agent surface --data config/surface.yaml --weights yolov8n.pt
"""
from __future__ import annotations

import argparse
import json
import random
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import yaml

try:
    from ultralytics import YOLO as _YOLO
except ImportError:  # pragma: no cover
    _YOLO = None


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

AGENTS: dict[str, list[str]] = {
    "cracks":   ["D00", "D10"],
    "pavement": ["D20", "D40"],
    "surface":  ["D50", "D60", "D90"],
}


# ---------------------------------------------------------------------------
# Reproducibility
# ---------------------------------------------------------------------------

def _set_seeds(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    try:
        import torch
        torch.manual_seed(seed)
        if torch.cuda.is_available():
            torch.cuda.manual_seed_all(seed)
    except ImportError:
        pass


# ---------------------------------------------------------------------------
# Augmentation config merger
# ---------------------------------------------------------------------------

def _load_augmentation_params(aug_config_path: Path) -> dict:
    """Load augmentation.yaml and return the 'augmentation' block as kwargs."""
    if not aug_config_path.exists():
        print(f"[train] WARNING: augmentation config not found at {aug_config_path}. Using defaults.")
        return {}
    cfg = yaml.safe_load(aug_config_path.read_text())
    return cfg.get("augmentation", {})


def _load_training_params(aug_config_path: Path) -> dict:
    """Load training hyperparameters from augmentation.yaml."""
    if not aug_config_path.exists():
        return {}
    cfg = yaml.safe_load(aug_config_path.read_text())
    params = cfg.get("training", {})
    # Remove non-ultralytics keys
    params.pop("class_confidence_thresholds", None)
    params.pop("negative_sample_fraction", None)
    return params


# ---------------------------------------------------------------------------
# Model card generator
# ---------------------------------------------------------------------------

def _write_model_card(
    agent: str,
    data_config: Path,
    weights: str,
    run_dir: Path,
    results: dict,
    seed: int,
) -> None:
    card = {
        "agent": agent,
        "classes": AGENTS[agent],
        "base_model": weights,
        "data_config": str(data_config),
        "training_seed": seed,
        "trained_at_utc": datetime.now(timezone.utc).isoformat(),
        "run_directory": str(run_dir),
        "metrics": results,
        "limitations": [
            "D90 (rutting) is visual-only — no depth measurement from 2D image.",
            "Performance may degrade on images outside the training domain (different countries, cameras).",
            "Minimum object size: ~32×32 pixels at 640 input resolution.",
            "Night-time / very dark images not well represented in training data.",
        ],
        "mobile_deployment": {
            "target_format": "TFLite",
            "input_size": "640x640",
            "precision": "float16 (recommended) or int8 (highest compression)",
            "note": "Export with src.export after training completes.",
        },
    }
    card_path = run_dir / "model_card.json"
    card_path.write_text(json.dumps(card, indent=2))
    print(f"[train] Model card → {card_path}")


# ---------------------------------------------------------------------------
# Main training function
# ---------------------------------------------------------------------------

def train(
    agent: str,
    data_config: Path,
    weights: str,
    epochs: int,
    imgsz: int,
    seed: int,
    aug_config: Path,
    project: str = "runs",
    allow_cpu: bool = False,
    finetune: bool = False,
    batch: int | None = None,
) -> None:
    classes = AGENTS.get(agent)
    if classes is None:
        raise SystemExit(f"Unknown agent: {agent}. Choose from {list(AGENTS)}")

    _set_seeds(seed)

    if not data_config.exists():
        raise SystemExit(f"Data YAML not found: {data_config}")

    source_hint = str(data_config).lower()
    if "global_potholes" in source_hint:
        raise SystemExit(
            "STOP: Global_Potholes_Dataset-image is unlabeled. "
            "Train on RDD2022/RDD2024 after convert_rdd_voc.py (data strategy A)."
        )

    try:
        import torch
        has_cuda = torch.cuda.is_available()
    except ImportError:
        has_cuda = False

    if not has_cuda and not allow_cpu:
        raise SystemExit(
            "No GPU detected. Refusing to start a CPU YOLOv8 run that cannot "
            "finish in a reasonable time. Pass --allow-cpu to override, or run "
            "on a CUDA machine. No metrics will be fabricated."
        )

    device_note = "cuda" if has_cuda else "cpu"
    started = datetime.now(timezone.utc)

    aug_params = _load_augmentation_params(aug_config)
    train_params = _load_training_params(aug_config)

    # CLI arguments override config-file values
    train_params.update({
        "data": str(data_config),
        "epochs": epochs,
        "imgsz": imgsz,
        "seed": seed,
        "project": project,
        "name": f"{agent}{'_ft' if finetune else '_baseline'}",
        "pretrained": True,
        "save": True,
        "save_period": 10,
        "val": True,
        "plots": True,
        "exist_ok": False,
    })
    if batch is not None:
        train_params["batch"] = batch
    if finetune:
        # Lower LR for fine-tuning an already trained road-damage checkpoint.
        train_params["lr0"] = float(train_params.get("lr0", 0.01)) * 0.1
        train_params.setdefault("patience", 20)

    # Merge augmentation params
    train_params.update(aug_params)

    print(f"\n{'='*60}")
    print(f"  Agent:     {agent}")
    print(f"  Classes:   {classes}")
    print(f"  Weights:   {weights}")
    print(f"  Data:      {data_config}")
    print(f"  Epochs:    {epochs}")
    print(f"  Imgsz:     {imgsz}")
    print(f"  Batch:     {train_params.get('batch')}")
    print(f"  Optimizer: {train_params.get('optimizer')}")
    print(f"  LR0:       {train_params.get('lr0')}")
    print(f"  Seed:      {seed}")
    print(f"  Device:    {device_note}")
    print(f"  Finetune:  {finetune}")
    print(f"{'='*60}\n")

    if _YOLO is None:
        raise SystemExit("ultralytics is not installed. pip install -r requirements.txt")

    model = _YOLO(weights)
    results = model.train(**train_params)

    # Evaluate on test split
    print(f"\n[train] Running final evaluation on test split…")
    test_results = model.val(data=str(data_config), split="test", imgsz=imgsz)

    run_dir = Path(project) / train_params["name"]
    metrics_dict = {}
    if hasattr(test_results, "results_dict"):
        metrics_dict = test_results.results_dict

    elapsed = (datetime.now(timezone.utc) - started).total_seconds()
    metrics_dict = dict(metrics_dict)
    metrics_dict["training_time_seconds"] = elapsed
    metrics_dict["device"] = device_note
    metrics_dict["imgsz"] = imgsz
    metrics_dict["epochs_requested"] = epochs
    metrics_dict["batch"] = train_params.get("batch")
    metrics_dict["optimizer"] = train_params.get("optimizer")
    metrics_dict["lr0"] = train_params.get("lr0")
    metrics_dict["finetune"] = finetune

    _write_model_card(
        agent=agent,
        data_config=data_config,
        weights=weights,
        run_dir=run_dir,
        results=metrics_dict,
        seed=seed,
    )

    print(f"\n[train] Training complete. Best weights: {run_dir}/weights/best.pt")
    print(f"[train] Next: python -m src.export --weights {run_dir}/weights/best.pt --agent {agent}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Train a TariqMap detection agent")
    parser.add_argument("--agent", required=True, choices=list(AGENTS), help="Agent to train")
    parser.add_argument("--data", type=Path, required=True, help="Path to YOLO data YAML")
    parser.add_argument("--weights", default="yolov8n.pt", help="Starting weights (YOLOv8n by default)")
    parser.add_argument("--epochs", type=int, default=150, help="Max training epochs")
    parser.add_argument("--imgsz", type=int, default=640, help="Input image size")
    parser.add_argument("--seed", type=int, default=42, help="Deterministic seed")
    parser.add_argument(
        "--aug-config",
        type=Path,
        default=Path(__file__).parents[1] / "config" / "augmentation.yaml",
        help="Path to augmentation.yaml",
    )
    parser.add_argument("--project", default="runs", help="Output project directory")
    parser.add_argument(
        "--allow-cpu",
        action="store_true",
        help="Allow training without CUDA (very slow; still will not invent metrics)",
    )
    parser.add_argument(
        "--finetune",
        action="store_true",
        help="Fine-tune mode: lower LR, expect --weights to be a previous best.pt",
    )
    parser.add_argument("--batch", type=int, default=None, help="Override batch size")
    args = parser.parse_args()

    train(
        agent=args.agent,
        data_config=args.data,
        weights=args.weights,
        epochs=args.epochs,
        imgsz=args.imgsz,
        seed=args.seed,
        aug_config=args.aug_config,
        project=args.project,
        allow_cpu=args.allow_cpu,
        finetune=args.finetune,
        batch=args.batch,
    )


if __name__ == "__main__":
    main()
