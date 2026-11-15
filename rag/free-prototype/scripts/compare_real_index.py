"""Compare FAISS IndexFlatIP with the JavaScript ranker.

Reads index.faiss and chunks.pkl. Does not modify them, does not recompute
embeddings, and does not call Cloudflare or Groq. The JSON export contains
vectors and chunk text, so it stays in a gitignored directory.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def compare(index_path: Path, chunks_path: Path, work_dir: Path) -> dict:
    export_path = work_dir / "index.json"
    ranks_path = work_dir / "js-ranks.json"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts" / "export_faiss.py"),
            "--index",
            str(index_path),
            "--chunks",
            str(chunks_path),
            "--out",
            str(export_path),
        ],
        check=True,
    )
    subprocess.run(
        [
            "node",
            str(ROOT / "scripts" / "rank_exported.mjs"),
            str(export_path),
            str(ranks_path),
            "5",
        ],
        check=True,
    )
    import faiss
    import numpy as np

    index = faiss.read_index(str(index_path))
    vectors = np.vstack(
        [index.reconstruct(i) for i in range(index.ntotal)]
    ).astype("float32")
    faiss_scores, ids = index.search(vectors, min(5, index.ntotal))
    js_ranks = json.loads(ranks_path.read_text(encoding="utf-8"))
    mismatches = 0
    max_gap = 0.0
    self_hits = 0
    for row, score_row, js_row in zip(ids, faiss_scores, js_ranks):
        js_ids = [hit["id"] for hit in js_row["hits"]]
        if list(map(int, row)) != js_ids:
            mismatches += 1
        for expected, hit in zip(score_row, js_row["hits"]):
            max_gap = max(max_gap, abs(float(expected) - float(hit["score"])))
        if js_ids and js_ids[0] == js_row["id"]:
            self_hits += 1
    export = json.loads(export_path.read_text(encoding="utf-8"))
    counts: dict[str, int] = {}
    for chunk in export["chunks"]:
        counts[chunk["source"]] = counts.get(chunk["source"], 0) + 1
    return {
        "chunks": int(index.ntotal),
        "dimension": int(index.d),
        "normalized": export["normalized"],
        "maxAbsNormError": export["maxAbsNormError"],
        "sources": counts,
        "queries": len(js_ranks),
        "idMismatches": mismatches,
        "maxScoreGap": max_gap,
        "selfHits": self_hits,
        "exportBytes": export_path.stat().st_size,
    }


def self_check() -> dict:
    import faiss
    import numpy as np

    rng = np.random.default_rng(15)
    count, dimension = 48, 1024
    matrix = rng.standard_normal((count, dimension)).astype("float32")
    matrix /= np.linalg.norm(matrix, axis=1, keepdims=True)
    index = faiss.IndexFlatIP(dimension)
    index.add(matrix)
    chunks = [{"text": f"chunk-{i}", "source": f"doc-{i % 3}.txt"} for i in range(count)]
    with tempfile.TemporaryDirectory() as folder:
        folder_path = Path(folder)
        index_path = folder_path / "index.faiss"
        chunks_path = folder_path / "chunks.pkl"
        faiss.write_index(index, str(index_path))
        import pickle

        with chunks_path.open("wb") as handle:
            pickle.dump(chunks, handle)
        return compare(index_path, chunks_path, folder_path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", type=Path)
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--work-dir", type=Path, default=ROOT / "export" / "real")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        print(json.dumps({"mode": "synthetic", **self_check()}))
        return
    if args.index is None or args.chunks is None:
        raise SystemExit("pass --index and --chunks, or --self-check")
    if not args.index.is_file() or not args.chunks.is_file():
        raise SystemExit("real index or chunks file is missing; nothing was written")
    args.work_dir.mkdir(parents=True, exist_ok=True)
    print(json.dumps({"mode": "real", **compare(args.index, args.chunks, args.work_dir)}))


if __name__ == "__main__":
    main()
