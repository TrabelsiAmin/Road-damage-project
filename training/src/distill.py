"""Knowledge distillation pipeline stub for TariqMap.

Validated ML path (must remain):
    baseline (YOLOv8n, per agent)
      → teacher (larger YOLO when VRAM allows)
      → knowledge distillation
      → student (YOLOv8n)
      → quantization (float16, then int8)
      → TFLite deploy (three agent runners)

This module does NOT invent metrics. It refuses to run a KD loop until a
real teacher checkpoint exists. A sibling training agent may be producing
the WP3 pavement baseline — do not start another full train from here.

Usage:
    python -m src.distill --agent pavement --plan-only
    python -m src.distill --agent pavement \\
        --teacher runs/pavement_teacher/weights/best.pt \\
        --student yolov8n.pt \\
        --data config/pavement.yaml --output reports/distill_pavement.json

WP3 (pavement, D20/D40) is the distillation priority. WP2/WP4 follow the
same recipe once their baselines exist. Do not distill a unified 7-class
YOLO for deployment — keep three student bundles.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

AGENTS: dict[str, list[str]] = {
    "cracks": ["D00", "D10"],       # WP2
    "pavement": ["D20", "D40"],     # WP3 PRIORITY
    "surface": ["D50", "D60", "D90"],  # WP4
}

PRIORITY_AGENT = "pavement"

# Recipe only. These numbers are hyperparameters, not evaluation results.
KD_RECIPE: dict[str, Any] = {
    "path": [
        "baseline",
        "teacher",
        "distill",
        "student",
        "quantize",
        "deploy",
    ],
    "teacher_default": "yolov8s.pt",
    "student_default": "yolov8n.pt",
    "imgsz": 640,
    "temperature": 4.0,
    "alpha_kd": 0.7,
    "alpha_gt": 0.3,
    "epochs": 80,
    "seed": 42,
    "quantize_after": ["float16", "int8"],
    "no_depth_estimation": True,
    "small_object_eval_classes": ["D20", "D40"],
    "deploy_as": "three_independent_tflite_runners",
}


def plan(
    agent: str,
    teacher: Path,
    student: Path,
    data: Path,
    output: Path,
) -> dict[str, Any]:
    """Write a KD plan. Never fabricates mAP / precision / recall."""
    if agent not in AGENTS:
        raise SystemExit(f"Unknown agent: {agent}. Choose from {list(AGENTS)}")

    report: dict[str, Any] = {
        "status": "NOT_RUN",
        "pipeline": "teacher_kd_student_quant_deploy",
        "agent": agent,
        "classes": AGENTS[agent],
        "priority_agent": PRIORITY_AGENT,
        "is_priority_agent": agent == PRIORITY_AGENT,
        "teacher": str(teacher),
        "student": str(student),
        "data": str(data),
        "recipe": KD_RECIPE,
        "metrics": None,
        "planned_at_utc": datetime.now(timezone.utc).isoformat(),
        "reason": None,
        "next_steps": [
            "Train a WP3 pavement baseline (YOLOv8n, 640) if not already running.",
            "Optionally train a teacher (YOLOv8s/960) on the same pavement split.",
            "Re-run this command once teacher weights exist; then implement the KD loop.",
            "Export the student with src.export (float16, then int8) and src.verify_tflite.",
            "Install pavement.tflite, then cracks.tflite, then surface.tflite — never a mixed 7-class deploy model.",
        ],
    }

    missing: list[str] = []
    if not teacher.exists():
        missing.append(f"teacher weights missing: {teacher}")
    if str(student).endswith(".pt") and not Path(student).exists() and student.name != "yolov8n.pt":
        missing.append(f"student checkpoint missing: {student}")
    if not data.exists():
        missing.append(f"data YAML missing: {data}")

    if missing:
        report["reason"] = (
            "KD cannot run yet. "
            + "; ".join(missing)
            + ". Stub only — no student mAP is claimed."
        )
    else:
        report["reason"] = (
            "Teacher path exists, but the KD training loop is not implemented "
            "in this stub. Do not claim distilled accuracy. "
            "Introduce the loop here later (logit KD + GT detection loss) "
            "without collapsing WP2/WP3/WP4."
        )
        report["status"] = "STUB_READY"

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(
        description="TariqMap KD stub (no fabricated metrics, no silent train)",
    )
    parser.add_argument(
        "--agent",
        default=PRIORITY_AGENT,
        choices=list(AGENTS),
        help="Agent to distill. Default: pavement (WP3 priority).",
    )
    parser.add_argument(
        "--teacher",
        type=Path,
        default=Path("runs/pavement_teacher/weights/best.pt"),
        help="Teacher checkpoint (must exist before a real KD run)",
    )
    parser.add_argument(
        "--student",
        type=Path,
        default=Path("yolov8n.pt"),
        help="Student init weights (YOLOv8n)",
    )
    parser.add_argument(
        "--data",
        type=Path,
        default=Path("config/pavement.yaml"),
        help="YOLO data YAML for this agent only",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("reports/distill_plan.json"),
        help="JSON plan/report path",
    )
    parser.add_argument(
        "--plan-only",
        action="store_true",
        help="Write the recipe even when weights are missing (default behaviour)",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Reserved. The KD loop is not implemented; still writes NOT_RUN/STUB_READY.",
    )
    args = parser.parse_args()

    if args.execute:
        print(
            "[distill] --execute is a no-op until the KD loop is implemented. "
            "Will not start YOLOv8 training (avoids colliding with an in-progress baseline)."
        )

    plan(
        agent=args.agent,
        teacher=args.teacher,
        student=args.student,
        data=args.data,
        output=args.output,
    )


if __name__ == "__main__":
    main()
