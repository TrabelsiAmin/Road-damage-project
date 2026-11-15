"""Read-only check for the historical 479-vector Colab index.

Prints counts, sizes, and the maximum norm error. Does not print chunk
text or vectors, and does not write or recompute embeddings.
"""

from __future__ import annotations

import argparse
import json
import pickle
import sys
from pathlib import Path

EXPECTED_CHUNKS = 479
EXPECTED_DIMENSION = 1024
EXPECTED_SOURCES = {
    "ArticleOuargla_contenu_organise.txt",
    "Cours_Pathologies_Entretien_Routes_Ouvrages_contenu_organise.txt",
    "Distress_Identification_Manual_contenu_organise.txt",
    "Manuel_identification_degradations_chaussees_flexibles_contenu_organise.txt",
    "Pathologie_des_routes_contenu_organise.txt",
    "RDD2022_contenu_organise.txt",
}


def load_chunks(path: Path):
    with path.open("rb") as handle:
        raw = pickle.load(handle)
    if isinstance(raw, dict) and "chunks" in raw:
        raw = raw["chunks"]
    if not isinstance(raw, list):
        raise SystemExit("chunks.pkl is not a list; nothing was written")
    return raw


def inspect_index(index_path: Path, chunks_path: Path, config_path: Path) -> dict:
    report = {
        "accepted": False,
        "indexBytes": index_path.stat().st_size if index_path.is_file() else None,
        "chunksBytes": chunks_path.stat().st_size if chunks_path.is_file() else None,
        "configBytes": config_path.stat().st_size if config_path.is_file() else None,
    }
    missing = [
        name
        for name, path in (
            ("index.faiss", index_path),
            ("chunks.pkl", chunks_path),
            ("config.json", config_path),
        )
        if not path.is_file()
    ]
    if missing:
        report["reason"] = "missing:" + ",".join(missing)
        return report

    import faiss
    import numpy as np

    index = faiss.read_index(str(index_path))
    chunks = load_chunks(chunks_path)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    vectors = np.vstack([index.reconstruct(i) for i in range(index.ntotal)]).astype("float32")
    norms = np.linalg.norm(vectors, axis=1)
    sources = []
    for position, item in enumerate(chunks):
        if not isinstance(item, dict) or not isinstance(item.get("source"), str):
            report["reason"] = f"chunk {position} has no source"
            return report
        if not isinstance(item.get("text"), str):
            report["reason"] = f"chunk {position} has no text"
            return report
        sources.append(item["source"])
    counts = {name: sources.count(name) for name in sorted(set(sources))}
    kind = type(index).__name__
    report.update({
        "indexType": kind,
        "chunks": int(index.ntotal),
        "chunkRecords": len(chunks),
        "dimension": int(index.d),
        "maxAbsNormError": float(np.max(np.abs(norms - 1))),
        "sourceCounts": counts,
        "configChunks": config.get("num_chunks"),
        "configDimension": config.get("embedding_dimension"),
        "configModel": config.get("embedding_model"),
    })
    reasons = []
    if kind != "IndexFlatIP":
        reasons.append("index_type")
    if index.ntotal != EXPECTED_CHUNKS or len(chunks) != EXPECTED_CHUNKS:
        reasons.append("chunk_count")
    if index.d != EXPECTED_DIMENSION:
        reasons.append("dimension")
    if report["maxAbsNormError"] > 1e-3:
        reasons.append("normalization")
    if set(counts) != EXPECTED_SOURCES:
        reasons.append("sources")
    if config.get("num_chunks") != EXPECTED_CHUNKS:
        reasons.append("config_chunks")
    if config.get("embedding_dimension") != EXPECTED_DIMENSION:
        reasons.append("config_dimension")
    if config.get("embedding_model") != "BAAI/bge-m3":
        reasons.append("config_model")
    report["accepted"] = not reasons
    report["reason"] = "ok" if report["accepted"] else ",".join(reasons)
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", required=True, type=Path)
    parser.add_argument("--chunks", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    args = parser.parse_args()
    report = inspect_index(args.index, args.chunks, args.config)
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report["accepted"] else 1


if __name__ == "__main__":
    sys.exit(main())
