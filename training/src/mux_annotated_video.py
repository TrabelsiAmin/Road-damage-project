"""CLI: mux a directory of JPEG frames into a verified H.264 MP4."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from src.ffmpeg_tools import find_ffmpeg, frame_durations_sec, mux_jpeg_sequence


def main() -> None:
    parser = argparse.ArgumentParser(description="Mux JPEG frames to MP4 with FFmpeg")
    parser.add_argument("--frames-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fps", type=float, default=2.0)
    args = parser.parse_args()
    if find_ffmpeg() is None:
        print(json.dumps({"status": "FFMPEG_MISSING", "reason": "ffmpeg is not on PATH"}, indent=2))
        raise SystemExit(2)
    frames = sorted(
        p for p in args.frames_dir.iterdir() if p.suffix.lower() in {".jpg", ".jpeg"}
    )
    if not frames:
        print(json.dumps({"status": "FAILED", "reason": "no JPEG frames"}, indent=2))
        raise SystemExit(2)
    duration_ms = int(round(len(frames) / args.fps * 1000))
    timestamps = [int(round(i * 1000 / args.fps)) for i in range(len(frames))]
    durations = frame_durations_sec(timestamps, duration_ms)
    report = mux_jpeg_sequence(list(zip(frames, durations)), args.output)
    print(json.dumps(report, indent=2))
    if report.get("status") != "OK":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
    sys.exit(0)
