"""Filesystem helpers for large image dumps. No metrics here."""
from __future__ import annotations

import os
import shutil
from pathlib import Path


def disk_free_bytes(path: Path) -> int:
    path.mkdir(parents=True, exist_ok=True)
    return int(shutil.disk_usage(path).free)


def place_file(src: Path, dest: Path, mode: str = "hardlink") -> str:
    """Place src at dest. Prefer hardlink so RDD JPEGs are not duplicated."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        return "exists"
    if mode == "symlink":
        dest.symlink_to(src.resolve())
        return "symlink"
    if mode == "copy":
        shutil.copy2(src, dest)
        return "copy"
    try:
        os.link(src, dest)
        return "hardlink"
    except OSError:
        shutil.copy2(src, dest)
        return "copy"
