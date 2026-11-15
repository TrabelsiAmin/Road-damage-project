"""Build a temporary FAISS index and compare it with the JavaScript search.

Nothing here reads or writes the Colab corpus. The real index is still absent
from this machine, so this check proves the math, not the notebook's answers.
"""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

import faiss
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
NODE = r"""
import { readFileSync } from 'node:fs';
import { search } from './src/search.mjs';
const payload = JSON.parse(readFileSync(process.argv[1], 'utf8'));
const queries = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const found = queries.map((query) => search(payload, query.vector, query.k).map((item) => ({
  id: item.index,
  score: item.score,
})));
process.stdout.write(JSON.stringify(found));
"""


def main():
    dimension = 1024
    count = 48
    rng = np.random.default_rng(15)
    matrix = rng.normal(size=(count, dimension)).astype("float32")
    matrix /= np.linalg.norm(matrix, axis=1, keepdims=True)
    index = faiss.IndexFlatIP(dimension)
    index.add(matrix)

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        index_path = folder / "index.faiss"
        chunks_path = folder / "chunks.pkl"
        export_path = folder / "export.json"
        faiss.write_index(index, str(index_path))
        import pickle
        chunks = [
            {"text": f"chunk {i}", "source": f"source-{i}.txt"}
            for i in range(count)
        ]
        with chunks_path.open("wb") as handle:
            pickle.dump(chunks, handle)
        exported = subprocess.run(
            ["python3", str(ROOT / "scripts" / "export_faiss.py"),
             "--index", str(index_path), "--chunks", str(chunks_path), "--out", str(export_path)],
            check=True, capture_output=True, text=True,
        )
        export_summary = json.loads(exported.stdout)

        queries = []
        expected = []
        for seed in (0, 7, 21):
            query = matrix[seed].copy()
            scores, ids = index.search(query.reshape(1, -1), 5)
            queries.append({"vector": query.tolist(), "k": 5})
            expected.append([
                {"id": int(ids[0][pos]), "score": float(scores[0][pos])}
                for pos in range(5)
            ])
        query_path = folder / "queries.json"
        query_path.write_text(json.dumps(queries), encoding="utf-8")
        completed = subprocess.run(
            ["node", "--input-type=module", "-e", NODE, str(export_path), str(query_path)],
            check=True, capture_output=True, text=True, cwd=ROOT,
        )
        actual = json.loads(completed.stdout)

    mismatches = 0
    max_score_gap = 0.0
    for left, right in zip(expected, actual):
        for item, other in zip(left, right):
            max_score_gap = max(max_score_gap, abs(item["score"] - other["score"]))
            if item["id"] != other["id"]:
                mismatches += 1
    print(json.dumps({
        "export": export_summary,
        "queries": len(expected),
        "idMismatches": mismatches,
        "maxScoreGap": max_score_gap,
    }))
    if mismatches or max_score_gap > 1e-5:
        raise SystemExit("JavaScript search diverges from FAISS")


if __name__ == "__main__":
    main()
