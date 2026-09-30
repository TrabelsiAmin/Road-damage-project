"""Download / locate a labeled RDD dump. Never fetches the unlabeled pothole set.

Official CRDDC'2022 dump (Figshare article 21431547):
  https://figshare.com/articles/dataset/RDD2022_-_The_multi-national_Road_Damage_Dataset_released_through_CRDDC_2022/21431547

The zip is 13,264,172,619 bytes (~13.3 GB). This script:
  - locates a local extract
  - probes Figshare and can fetch metadata (label map, directory listing, file list)
  - downloads the zip when --download-zip is passed AND disk is sufficient
  - never scrapes Global Potholes

User must accept the RDD license before downloading images.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from src.fsutil import disk_free_bytes
from src.summarize_file_list import summarize as summarize_file_list

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
    "File_List_CRDDC_RDD2022.txt": "38030826",
}

EXPECTED_ZIP_BYTES = 13_264_172_619
ZIP_FILE_ID = "38030910"
ZIP_NAME = "RDD2022_released_through_CRDDC2022.zip"
ZIP_URL = f"https://ndownloader.figshare.com/files/{ZIP_FILE_ID}"
DISK_SLACK_BYTES = 2 * 1024 ** 3


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


def _http_bytes(url: str, timeout: int = 60) -> tuple[int, bytes | None, str | None]:
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


def _sha256_prefix(path: Path, nbytes: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        h.update(fh.read(nbytes))
    return h.hexdigest()


def can_download(free_bytes: int, remaining_bytes: int, slack: int = DISK_SLACK_BYTES) -> bool:
    return remaining_bytes <= 0 or free_bytes >= remaining_bytes + slack


def download_zip(
    dest_zip: Path,
    expected_size: int = EXPECTED_ZIP_BYTES,
    url: str = ZIP_URL,
) -> dict:
    dest_zip.parent.mkdir(parents=True, exist_ok=True)
    existing = dest_zip.stat().st_size if dest_zip.exists() else 0
    free = disk_free_bytes(dest_zip.parent)
    remaining = max(0, expected_size - existing)
    report: dict = {
        "url": url,
        "dest": str(dest_zip),
        "expected_size_bytes": expected_size,
        "bytes_before": existing,
        "disk_free_bytes": free,
        "ok": False,
    }
    if existing == expected_size:
        report["ok"] = True
        report["skipped"] = "already complete"
        report["bytes_after"] = existing
        return report
    if not can_download(free, remaining):
        report["error"] = (
            f"insufficient disk: free={free} bytes, remaining download={remaining} bytes, "
            f"need remaining+{DISK_SLACK_BYTES} slack"
        )
        return report
    wget = shutil.which("wget")
    if wget is None:
        report["error"] = "wget not found; cannot stream the 13 GB zip"
        return report
    cmd = [
        wget,
        "-c",
        "--progress=dot:giga",
        "--timeout=60",
        "--tries=0",
        "--retry-connrefused",
        "--waitretry=8",
        "--user-agent=TariqMap-download_rdd/1.0",
        "-O",
        str(dest_zip),
        url,
    ]
    proc = subprocess.run(cmd, check=False)
    after = dest_zip.stat().st_size if dest_zip.exists() else 0
    report["bytes_after"] = after
    report["wget_returncode"] = proc.returncode
    if after == expected_size:
        report["ok"] = True
        report["sha256_first_1MiB"] = _sha256_prefix(dest_zip)
    else:
        report["error"] = (
            f"size mismatch after wget rc={proc.returncode}: got {after} expected {expected_size}"
        )
    return report


def extract_zip(zip_path: Path, dest: Path) -> dict:
    dest.mkdir(parents=True, exist_ok=True)
    free = disk_free_bytes(dest)
    zsize = zip_path.stat().st_size if zip_path.exists() else 0
    report: dict = {
        "zip": str(zip_path),
        "dest": str(dest),
        "zip_bytes": zsize,
        "disk_free_bytes": free,
        "ok": False,
        "nested_zips": [],
    }
    if not zip_path.exists():
        report["error"] = f"zip not found: {zip_path}"
        return report
    if free < zsize:
        report["error"] = f"insufficient disk to extract: free={free} zip={zsize}"
        return report
    first = _unzip_one(zip_path, dest)
    report["outer_unzip"] = first
    if not first.get("ok"):
        report["error"] = first.get("error")
        return report
    xml = list(dest.rglob("*.xml"))
    nested = sorted(p for p in dest.rglob("*.zip") if p.is_file())
    if not xml and nested:
        # Figshare 21431547 is a zip of per-country zips.
        for nz in nested:
            inner = _unzip_one(nz, dest)
            inner["nested_zip"] = str(nz)
            report["nested_zips"].append(inner)
            if not inner.get("ok"):
                report["error"] = f"nested unzip failed: {nz}: {inner.get('error')}"
                return report
        xml = list(dest.rglob("*.xml"))
    report["ok"] = len(xml) > 0
    report["xml_count"] = len(xml)
    if not report["ok"]:
        report["error"] = (
            f"extract finished but no XML under {dest}. "
            f"nested_zips_found={len(nested)}"
        )
    return report


def _unzip_one(zip_path: Path, dest: Path) -> dict:
    dest.mkdir(parents=True, exist_ok=True)
    unzip = shutil.which("unzip")
    if unzip:
        proc = subprocess.run(
            [unzip, "-qo", str(zip_path), "-d", str(dest)],
            check=False,
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            return {
                "ok": False,
                "error": proc.stderr.strip() or f"unzip failed rc={proc.returncode}",
                "unzip_returncode": proc.returncode,
            }
        return {"ok": True, "unzip_returncode": 0}
    try:
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(dest)
    except (zipfile.BadZipFile, OSError) as exc:
        return {"ok": False, "error": str(exc)}
    return {"ok": True, "method": "zipfile"}


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
        help="Download label_map, directory structure, and file list (not the 13GB zip)",
    )
    parser.add_argument(
        "--download-zip",
        action="store_true",
        help="Download the full RDD2022 zip if disk is sufficient.",
    )
    parser.add_argument(
        "--zip-path",
        type=Path,
        default=None,
        help="Where to store/read the zip (default: <dest.parent>/RDD2022_released_through_CRDDC2022.zip)",
    )
    parser.add_argument(
        "--extract",
        action="store_true",
        help="Extract the zip into --dest after a successful download or if the zip already exists.",
    )
    args = parser.parse_args()

    local = locate(args.dest)
    remote = probe_figshare()
    metadata = []
    file_list_inventory = None
    meta_dir = Path(__file__).resolve().parents[1] / "reports" / "rdd2022_meta"
    if args.fetch_metadata:
        metadata = fetch_metadata(meta_dir)
        file_list = meta_dir / "File_List_CRDDC_RDD2022.txt"
        if file_list.exists():
            file_list_inventory = summarize_file_list(file_list)
            inv_path = Path(__file__).resolve().parents[1] / "reports" / "rdd2022_file_list_inventory.json"
            inv_path.write_text(json.dumps(file_list_inventory, indent=2))

    zip_info = remote.get("zip") or {}
    zip_bytes = zip_info.get("size_bytes") or EXPECTED_ZIP_BYTES
    zip_path = args.zip_path or (args.dest.parent / ZIP_NAME)
    download_result = None
    extract_result = None
    if args.download_zip:
        download_result = download_zip(zip_path, expected_size=int(zip_bytes), url=ZIP_URL)
    elif zip_path.exists():
        download_result = {
            "dest": str(zip_path),
            "bytes_after": zip_path.stat().st_size,
            "ok": zip_path.stat().st_size == int(zip_bytes),
            "skipped": "existing zip, --download-zip not passed",
        }
    if args.extract:
        extract_result = extract_zip(zip_path, args.dest)
        local = locate(args.dest)

    zip_ok = bool(download_result and download_result.get("ok"))
    report = {
        "probed_at_utc": datetime.now(timezone.utc).isoformat(),
        "local": local,
        "remote": remote,
        "metadata_files": metadata,
        "file_list_inventory": file_list_inventory,
        "zip_path": str(zip_path),
        "download": download_result,
        "extract": extract_result,
        "zip_downloaded": zip_ok,
        "note": (
            "RDD2022 is reachable on Figshare (article 21431547). "
            f"The labeled zip is {zip_bytes} bytes (~13.3 GB). "
            "Official CRDDC label_map lists D00/D10/D20/D40 only; "
            "D43→D60 and D44→D50 remain conditional if those names appear in XML. "
            "D90 is absent."
        ),
    }

    write_access_report(args.report, report)
    print(json.dumps(report, indent=2))
    if args.download_zip and download_result and not download_result.get("ok"):
        sys.exit(3)
    if args.extract and extract_result and not extract_result.get("ok"):
        sys.exit(4)
    if not local["usable"]:
        sys.exit(2)


if __name__ == "__main__":
    main()
