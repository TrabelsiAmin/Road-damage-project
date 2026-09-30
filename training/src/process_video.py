"""Desktop video pipeline: extract JPEG frames, optionally mux annotated MP4.

This is the verified FFmpeg path. The Flutter app uses the same concat+H.264
recipe when `ffmpeg` is on PATH (Linux/desktop). Stock Android/iOS do not
ship FFmpeg; those builds keep the contact sheet.

Usage:
    python -m src.process_video --input clip.mp4 --output out/annotated.mp4 --fps 2
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from src.ffmpeg_tools import (
    extract_frames_ffmpeg,
    find_ffmpeg,
    frame_durations_sec,
    mux_jpeg_sequence,
    verify_video,
)


def process_video(
    input_video: Path,
    output_video: Path,
    fps: float,
    work_dir: Path | None = None,
) -> dict:
    ffmpeg = find_ffmpeg()
    if ffmpeg is None:
        report = {
            "status": "FFMPEG_MISSING",
            "reason": "ffmpeg is not on PATH. Install FFmpeg to encode annotated MP4.",
            "input": str(input_video),
        }
        print(json.dumps(report, indent=2))
        return report

    work = work_dir or (output_video.parent / f"{output_video.stem}_frames")
    extracted = extract_frames_ffmpeg(input_video, work, fps=fps, ffmpeg=ffmpeg)
    if extracted["status"] != "OK":
        print(json.dumps(extracted, indent=2))
        return extracted

    frame_paths = [Path(p) for p in extracted["frames"]]
    # Constant-fps montage: each JPEG is shown for 1/fps seconds.
    duration_ms = int(round(len(frame_paths) / fps * 1000))
    timestamps = [int(round(i * 1000 / fps)) for i in range(len(frame_paths))]
    durations = frame_durations_sec(timestamps, duration_ms)
    pairs = list(zip(frame_paths, durations))
    muxed = mux_jpeg_sequence(pairs, output_video, ffmpeg=ffmpeg)
    muxed["extracted_frames"] = len(frame_paths)
    muxed["extract_fps"] = fps
    print(json.dumps(muxed, indent=2))
    return muxed


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract frames and mux an H.264 MP4 with FFmpeg")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fps", type=float, default=2.0, help="JPEG sample rate for the output montage")
    parser.add_argument("--verify-only", type=Path, default=None, help="Only ffprobe+decode an existing MP4")
    args = parser.parse_args()
    if args.verify_only is not None:
        report = verify_video(args.verify_only)
        print(json.dumps(report, indent=2))
        if report["status"] != "OK":
            raise SystemExit(2)
        return
    report = process_video(args.input, args.output, args.fps)
    if report.get("status") != "OK":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
    sys.exit(0)
