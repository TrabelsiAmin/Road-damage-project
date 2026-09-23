"""TariqMap YOLOv8 training entry point.

Trains one agent at a time with:
- Selectable backbone size (n / s / m) via --model-size
- Deterministic seed
- Cosine LR scheduling
- Augmentation from augmentation.yaml
- Early stopping
- Best-checkpoint saving
- Per-class validation metrics on test split
- Model card generation

Usage:
    # Small model (recommended — good accuracy/mobile balance)
    python -m src.train --agent cracks --data config/cracks.yaml

    # Explicitly choose backbone size
    python -m src.train --agent cracks --data config/cracks.yaml --model-size s
    python -m src.train --agent cracks --data config/cracks.yaml --model-size m

    # Legacy nano (smallest, fastest)
    python -m src.train --agent cracks --data config/cracks.yaml --model-size n
"""
from __future__ import annotations

import argparse
import json
import random
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import yaml
from ultralytics import YOLO


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

AGENTS: dict[str, list[str]] = {
    "cracks":   ["D00", "D10"],
    "pavement": ["D20", "D40"],
    "surface":  ["D50", "D60", "D90"],
}

# Available backbone sizes → YOLO model name
MODEL_SIZES: dict[str, str] = {
    "n": "yolov8n.pt",   # Nano   — ~6 MB TFLite, fastest, lowest accuracy
    "s": "yolov8s.pt",   # Small  — ~22 MB TFLite, balanced (DEFAULT)
    "m": "yolov8m.pt",   # Medium — ~52 MB TFLite, highest accuracy
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
    # Remove non-ultralytics keys before passing to model.train()
    params.pop("class_confidence_thresholds", None)
    params.pop("negative_sample_fraction", None)
    return params


# ---------------------------------------------------------------------------
# Per-class AP extractor
# ---------------------------------------------------------------------------

def _extract_per_class_ap(val_results) -> dict[str, float]:
    """Extract per-class AP50 from Ultralytics validation results."""
    per_class: dict[str, float] = {}
    try:
        # ultralytics >= 8.0: results.ap_class_index + results.box.ap50
        if hasattr(val_results, "box") and hasattr(val_results.box, "ap50"):
            ap50_array = val_results.box.ap50
            class_indices = val_results.box.ap_class_index
            names = val_results.names
            for idx, ap in zip(class_indices, ap50_array):
                class_name = names.get(int(idx), f"class_{idx}")
                per_class[class_name] = float(ap)
    except Exception as exc:
        print(f"[train] WARNING: Could not extract per-class AP: {exc}")
    return per_class


# ---------------------------------------------------------------------------
# Model card generator
# ---------------------------------------------------------------------------

def _write_model_card(
    agent: str,
    data_config: Path,
    weights: str,
    run_dir: Path,
    results: dict,
    per_class_ap: dict[str, float],
    seed: int,
    model_size: str,
) -> None:
    card = {
        "agent": agent,
        "classes": AGENTS[agent],
        "base_model": weights,
        "model_size": model_size,
        "data_config": str(data_config),
        "training_seed": seed,
        "trained_at_utc": datetime.now(timezone.utc).isoformat(),
        "run_directory": str(run_dir),
        "metrics": results,
        "per_class_ap50": per_class_ap,
        "limitations": [
            "D90 (rutting) is visual-only — no depth measurement from 2D image.",
            "Performance may degrade on images outside the training domain (different countries, cameras).",
            "Minimum object size: ~32×32 pixels at 640 input resolution.",
            "Night-time / very dark images not well represented in training data.",
        ],
        "mobile_deployment": {
            "target_format": "TFLite",
            "input_size": "640x640",
            "precision": "float16 (recommended) or int8 with calibration data",
            "note": "Export with src.export after training completes.",
        },
    }
    card_path = run_dir / "model_card.json"
    card_path.write_text(json.dumps(card, indent=2))
    print(f"[train] Model card → {card_path}")
    if per_class_ap:
        print("[train] Per-class AP50:")
        for cls, ap in per_class_ap.items():
            print(f"         {cls}: {ap:.4f}")


# ---------------------------------------------------------------------------
# Main training function
# ---------------------------------------------------------------------------

def train(
    agent: str,
    data_config: Path,
    model_size: str,
    epochs: int,
    imgsz: int,
    seed: int,
    aug_config: Path,
    project: str = "runs",
) -> None:
    classes = AGENTS.get(agent)
    if classes is None:
        raise SystemExit(f"Unknown agent: {agent}. Choose from {list(AGENTS)}")

    weights = MODEL_SIZES[model_size]
    _set_seeds(seed)

    aug_params   = _load_augmentation_params(aug_config)
    train_params = _load_training_params(aug_config)

    # CLI arguments override config-file values
    train_params.update({
        "data":        str(data_config),
        "epochs":      epochs,
        "imgsz":       imgsz,
        "seed":        seed,
        "project":     project,
        "name":        agent,
        "pretrained":  True,
        "save":        True,
        "save_period": 10,
        "val":         True,
        "plots":       True,
        "exist_ok":    False,
    })

    # Merge augmentation params (augmentation.yaml values, already has cos_lr etc.)
    train_params.update(aug_params)

    print(f"\n{'='*60}")
    print(f"  Agent:      {agent}")
    print(f"  Classes:    {classes}")
    print(f"  Backbone:   {weights}  (size={model_size})")
    print(f"  Data:       {data_config}")
    print(f"  Epochs:     {epochs}  (patience={train_params.get('patience', '—')})")
    print(f"  cos_lr:     {train_params.get('cos_lr', False)}")
    print(f"  Seed:       {seed}")
    print(f"{'='*60}\n")

    model = YOLO(weights)
    model.train(**train_params)

    # Evaluate on test split
    print(f"\n[train] Running final evaluation on test split…")
    test_results = model.val(data=str(data_config), split="test", imgsz=imgsz)

    run_dir = Path(project) / agent
    metrics_dict = {}
    if hasattr(test_results, "results_dict"):
        metrics_dict = test_results.results_dict

    per_class_ap = _extract_per_class_ap(test_results)

    _write_model_card(
        agent=agent,
        data_config=data_config,
        weights=weights,
        run_dir=run_dir,
        results=metrics_dict,
        per_class_ap=per_class_ap,
        seed=seed,
        model_size=model_size,
    )

    print(f"\n[train] Training complete. Best weights: {run_dir}/weights/best.pt")
    print(
        f"[train] Next: python -m src.export"
        f" --weights {run_dir}/weights/best.pt --agent {agent}"
        f" --precision float16"
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Train a TariqMap detection agent")
    parser.add_argument("--agent", required=True, choices=list(AGENTS), help="Agent to train")
    parser.add_argument("--data", type=Path, required=True, help="Path to YOLO data YAML")
    parser.add_argument(
        "--model-size",
        default="s",
        choices=list(MODEL_SIZES),
        help="YOLOv8 backbone size: n (nano), s (small, default), m (medium)",
    )
    # --weights kept for backward compatibility; --model-size takes precedence
    parser.add_argument(
        "--weights",
        default=None,
        help="[Deprecated] Direct path to .pt weights. Use --model-size instead.",
    )
    parser.add_argument("--epochs", type=int, default=None,
                        help="Max training epochs (default: from augmentation.yaml)")
    parser.add_argument("--imgsz", type=int, default=640, help="Input image size")
    parser.add_argument("--seed",  type=int, default=42,  help="Deterministic seed")
    parser.add_argument(
        "--aug-config",
        type=Path,
        default=Path(__file__).parents[1] / "config" / "augmentation.yaml",
        help="Path to augmentation.yaml",
    )
    parser.add_argument("--project", default="runs", help="Output project directory")
    args = parser.parse_args()

    # If legacy --weights provided, reverse-map to model size
    if args.weights and args.model_size == "s":
        w = args.weights.lower()
        if "yolov8n" in w:
            args.model_size = "n"
        elif "yolov8m" in w:
            args.model_size = "m"
        print(f"[train] INFO: --weights is deprecated; resolved to --model-size={args.model_size}")

    # Load default epochs from config if not overridden on CLI
    cfg_path = args.aug_config
    default_epochs = 200
    if cfg_path.exists():
        cfg = yaml.safe_load(cfg_path.read_text())
        default_epochs = cfg.get("training", {}).get("epochs", 200)
    epochs = args.epochs if args.epochs is not None else default_epochs

    train(
        agent=args.agent,
        data_config=args.data,
        model_size=args.model_size,
        epochs=epochs,
        imgsz=args.imgsz,
        seed=args.seed,
        aug_config=args.aug_config,
        project=args.project,
    )


if __name__ == "__main__":
    main()
