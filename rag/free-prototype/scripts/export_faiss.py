"""Export a FAISS IndexFlatIP index without modifying it.

The real Colab files are not in this repository. Point --index and --chunks
at local copies. This script only reads them and writes a new JSON file.
"""

from __future__ import annotations

import argparse
import json
import pickle
from pathlib import Path


def chunk_record(item, position):
    if isinstance(item, dict):
        text = item.get("text") or item.get("page_content") or item.get("chunk")
        source = item.get("source") or item.get("file") or item.get("metadata", {}).get("source")
    elif isinstance(item, (list, tuple)) and len(item) >= 2:
        text, source = item[0], item[1]
    else:
        raise SystemExit(f"chunk {position} has an unsupported shape")
    if not isinstance(text, str) or not isinstance(source, str):
        raise SystemExit(f"chunk {position} is missing text or source")
    return text, source


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", required=True, type=Path)
    parser.add_argument("--chunks", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    if not args.index.is_file() or not args.chunks.is_file():
        raise SystemExit("index or chunks file is missing; nothing was written")

    import faiss
    import numpy as np

    index = faiss.read_index(str(args.index))
    with args.chunks.open("rb") as handle:
        raw_chunks = pickle.load(handle)
    if isinstance(raw_chunks, dict) and "chunks" in raw_chunks:
        raw_chunks = raw_chunks["chunks"]
    if len(raw_chunks) != index.ntotal:
        raise SystemExit(
            f"chunk count {len(raw_chunks)} does not match index.ntotal {index.ntotal}"
        )

    vectors = np.vstack([index.reconstruct(i) for i in range(index.ntotal)]).astype("float32")
    norms = np.linalg.norm(vectors, axis=1)
    records = []
    for position, item in enumerate(raw_chunks):
        text, source = chunk_record(item, position)
        records.append({
            "id": position,
            "source": source,
            "text": text,
            "vector": vectors[position].tolist(),
        })

    payload = {
        "model": "BAAI/bge-m3",
        "dimension": int(index.d),
        "metric": "inner_product",
        "normalized": bool(np.max(np.abs(norms - 1)) <= 1e-3),
        "maxAbsNormError": float(np.max(np.abs(norms - 1))),
        "chunks": records,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload), encoding="utf-8")
    print(json.dumps({
        "wrote": str(args.out),
        "chunks": len(records),
        "dimension": payload["dimension"],
        "normalized": payload["normalized"],
        "maxAbsNormError": payload["maxAbsNormError"],
        "bytes": args.out.stat().st_size,
    }))


if __name__ == "__main__":
    main()
