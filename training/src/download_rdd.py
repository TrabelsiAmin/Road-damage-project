"""Download / locate a labeled RDD dump. Never fetches the unlabeled pothole set.

Official CRDDC'2022 dump (Figshare article 21431547):
  https://figshare.com/articles/dataset/RDD2022_-_The_multi-national_Road_Damage_Dataset_released_through_CRDDC_2022/21431547

The zip is ~13.3 GB. This script:
  - locates a local extract
  - probes Figshare and can fetch *metadata* (label map, directory listing)
  - does **not** download the zip unless --download-zip is passed
  - never scrapes Global Potholes

User must accept the RDD license before downloading images.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

FIGSHARE_ARTICLE_ID = 21431547
FIGSHARE_HTML = (
    "https://figshare.com/articles/dataset/"
    "RDD2022_-_The_multi-national_Road_Damage_Dataset_released_through_CRDDC_2022/"
    f"{FIGSHARE_ARTICLE_ID}"
)
FIGSHARE_API = f"https://api.figshare.com/v2/articles/{FIGSHARE_ARTICLE_ID}"

OFFICIAL = {
    "rdd2022_figshare": FIGSHARE_HTML,
    "rdd2022_figshare_api": FIGSHARE_API,
    "rdd2022_paper": "https://arxiv.org/abs/2209.08538",
    "github": "https://github.com/sekilab/RoadDamageDetector",
}

METADATA_FILES = {
    "label_map.pbtxt": "38030820",
    "Directory_Structure_CRDDC_RDD2022.txt": "38030823",
}


def locate(root: Path) -> dict:
    xml = list(root.rglob("*.xml")) if root.exists() else []
    images = [
        p
        for p in (root.rglob("*") if root.exists() else [])
        if p.suffix.lower() in {".jpg", ".jpeg", ".png"}
    ]
    return {
        "path": str(root),
        "exists": root.exists(),
        "xml_count": len(xml),
        "image_count": len(images),
        "usable": len(xml) > 0,
        "official_sources": OFFICIAL,
        "note": (
            "Labeled RDD VOC XML found."
            if xml
            else "Place an RDD2022/RDD2024 extract here (JPEG + XML). "
            "Do not point this tool at Global_Potholes_Dataset-image."
        ),
    }


def _http_json(url: str, timeout: int = 30) -> tuple[int, dict | None, str | None]:
    req = urllib.request.Request(url, headers={"User-Agent": "TariqMap-download_rdd/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
            return resp.status, json.loads(body.decode("utf-8")), None
    except urllib.error.HTTPError as exc:
        return exc.code, None, str(exc)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        return 0, None, str(exc)


def _http_bytes(url: str, timeout: int = 30) -> tuple[int, bytes | None, str | None]:
    req = urllib.request.Request(url, headers={"User-Agent": "TariqMap-download_rdd/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read(), None
    except urllib.error.HTTPError as exc:
        return exc.code, None, str(exc)
    except (urllib.error.URLError, TimeoutError) as exc:
        return 0, None, str(exc)


def probe_figshare() -> dict:
    status, payload, err = _http_json(FIGSHARE_API)
    report: dict = {
        "article_id": FIGSHARE_ARTICLE_ID,
        "api_url": FIGSHARE_API,
        "html_url": FIGSHARE_HTML,
        "http_status": status,
        "error": err,
        "title": None,
        "files": [],
        "zip": None,
    }
    if not payload:
        return report
    report["title"] = payload.get("title")
    files = []
    for f in payload.get("files") or []:
        entry = {
            "id": f.get("id"),
            "name": f.get("name"),
            "size_bytes": f.get("size"),
            "download_url": f.get("download_url"),
        }
        files.append(entry)
        if str(f.get("name", "")).endswith(".zip"):
            report["zip"] = entry
    report["files"] = files
    return report


def fetch_metadata(dest: Path) -> list[dict]:
    dest.mkdir(parents=True, exist_ok=True)
    results = []
    for name, file_id in METADATA_FILES.items():
        url = f"https://ndownloader.figshare.com/files/{file_id}"
        status, data, err = _http_bytes(url)
        out = dest / name
        item = {"name": name, "http_status": status, "error": err, "path": str(out)}
        if data and status and status < 400:
            out.write_bytes(data)
            item["bytes"] = len(data)
        results.append(item)
    return results


def write_access_report(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dest",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "data" / "raw" / "rdd2022",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "reports" / "rdd_access.json",
    )
    parser.add_argument(
        "--fetch-metadata",
        action="store_true",
        help="Download label_map.pbtxt and directory structure (not the 13GB zip)",
    )
    parser.add_argument(
        "--download-zip",
        action="store_true",
        help="Download the full RDD2022 zip (≈13 GB). Off by default.",
    )
    args = parser.parse_args()

    local = locate(args.dest)
    remote = probe_figshare()
    metadata = []
    if args.fetch_metadata:
        meta_dir = Path(__file__).resolve().parents[1] / "reports" / "rdd2022_meta"
        metadata = fetch_metadata(meta_dir)

    zip_info = remote.get("zip") or {}
    zip_bytes = zip_info.get("size_bytes")
    report = {
        "probed_at_utc": datetime.now(timezone.utc).isoformat(),
        "local": local,
        "remote": remote,
        "metadata_files": metadata,
        "zip_downloaded": False,
        "note": (
            "RDD2022 is reachable on Figshare (article 21431547). "
            f"The labeled zip is {zip_bytes} bytes (~13.3 GB). "
            "This environment did not download the images. "
            "Official CRDDC label_map lists D00/D10/D20/D40 only; "
            "D43→D60 and D44→D50 remain conditional if those names appear in XML. "
            "D90 is absent."
        ),
    }
    if args.download_zip:
        report["zip_downloaded"] = False
        report["note"] += (
            " --download-zip was requested but this script refuses to pull 13 GB "
            "on a cloud agent without an explicit local path and free disk; "
            "download manually from Figshare."
        )

    write_access_report(args.report, report)
    print(json.dumps(report, indent=2))
    print("\nTo obtain RDD2022 images:")
    print(f"  1. Download from {OFFICIAL['rdd2022_figshare']}")
    print(f"  2. Extract into {args.dest}")
    print("  3. python -m src.convert_rdd_voc --source <extract> --output data/raw/rdd_yolo")
    print("  4. python -m src.analyze_labeled_dataset --dataset data/raw/rdd_yolo")
    print("  5. python -m src.prepare_dataset --source data/raw/rdd_yolo --output data/processed --class-map config/source-class-map.json")
    if not local["usable"]:
        sys.exit(2)


if __name__ == "__main__":
    main()
