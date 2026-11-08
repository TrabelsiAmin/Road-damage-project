"""Synthetic split fixtures. Not a split of the 29,120 images."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from evaluation.android_model_audit.scripts.assign_splits import assign_splits, class_distribution

SCRIPT = Path(__file__).resolve().parent / "assign_splits.py"


class AssignSplitsTest(unittest.TestCase):
    def test_duplicates_stay_together_and_seed_is_stable(self) -> None:
        records = [
            {"id": "a", "content_hash": "same"},
            {"id": "b", "content_hash": "same"},
            {"id": "c", "content_hash": "other"},
            {"id": "d", "content_hash": "third"},
        ]
        first = assign_splits(records, seed=7)
        second = assign_splits(records, seed=7)
        self.assertEqual(first, second)
        self.assertIsNone(first["class_distribution"])
        splits = first["splits"]
        homes = []
        for name, ids in splits.items():
            if "a" in ids:
                homes.append(name)
                self.assertIn("b", ids)
        self.assertEqual(len(homes), 1)

    def test_class_counts_stay_hidden_until_verified(self) -> None:
        records = [{"id": "a", "content_hash": "h", "category_name": "synthetic-fixture"}]
        self.assertIsNone(class_distribution(records, verified=False))
        self.assertEqual(class_distribution(records, verified=True), {"synthetic-fixture": 1})

    def test_cli_refuses_the_real_dataset_path(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--records",
                "/tmp/Road-damage-project/Global_Potholes_Dataset-image/images",
                "--seed",
                "1",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("refusing", completed.stderr)

    def test_cli_synthetic_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "synthetic-records.json"
            path.write_text(
                json.dumps(
                    [
                        {"id": "s1", "content_hash": "dup"},
                        {"id": "s2", "content_hash": "dup"},
                    ]
                ),
                encoding="utf-8",
            )
            completed = subprocess.run(
                [sys.executable, str(SCRIPT), "--records", str(path), "--seed", "3"],
                check=False,
                capture_output=True,
                text=True,
            )
        report = json.loads(completed.stdout)
        self.assertEqual(completed.returncode, 0)
        self.assertIsNone(report["class_distribution"])
        self.assertEqual(report["group_count"], 1)


if __name__ == "__main__":
    unittest.main()
