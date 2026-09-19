"""FFmpeg helpers for annotated output video.

Uses the system FFmpeg CLI. Does not fake a muxer: if ffmpeg/ffprobe are
missing, status is FFMPEG_MISSING. OK is returned only after ffprobe sees a
video stream and ffmpeg can decode the file.
"""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any


def find_ffmpeg() -> Path | None:
    found = shutil.which("ffmpeg")
    return Path(found) if found else None


def find_ffprobe() -> Path | None:
    found = shutil.which("ffprobe")
    return Path(found) if found else None


def _run(cmd: list[str], timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _escape_concat_path(path: Path) -> str:
    # concat demuxer single-quoted paths: escape embedded quotes
    return str(path.resolve()).replace("'", r"'\''")


def frame_durations_sec(
    timestamps_ms: list[int],
    source_duration_ms: int,
    min_duration: float = 0.04,
) -> list[float]:
    if not timestamps_ms:
        return []
    out: list[float] = []
    for i, t in enumerate(timestamps_ms):
        if i + 1 < len(timestamps_ms):
            nxt = timestamps_ms[i + 1]
        elif source_duration_ms > t:
            nxt = source_duration_ms
        elif i > 0:
            nxt = t + (t - timestamps_ms[i - 1])
        else:
            nxt = t + 1000
        dur = (nxt - t) / 1000.0
        out.append(min_duration if dur <= 0 else dur)
    return out


def write_concat_list(
    frames: list[tuple[Path, float]],
    list_path: Path,
) -> None:
    """Write an FFmpeg concat demuxer file with per-frame durations."""
    if not frames:
        raise ValueError("No frames to mux")
    lines: list[str] = []
    for path, duration in frames:
        if not path.exists():
            raise FileNotFoundError(path)
        lines.append(f"file '{_escape_concat_path(path)}'")
        lines.append(f"duration {duration:.4f}")
    # concat demuxer requires the last file to be listed again without duration
    last = frames[-1][0]
    lines.append(f"file '{_escape_concat_path(last)}'")
    list_path.write_text("\n".join(lines) + "\n")


def mux_jpeg_sequence(
    frames: list[tuple[Path, float]],
    output: Path,
    *,
    ffmpeg: Path | None = None,
) -> dict[str, Any]:
    ffmpeg_bin = ffmpeg or find_ffmpeg()
    report: dict[str, Any] = {
        "status": "FAILED",
        "output": str(output),
        "ffmpeg": str(ffmpeg_bin) if ffmpeg_bin else None,
        "frame_count": len(frames),
        "size_bytes": None,
        "ffprobe": None,
        "decode_ok": False,
        "reason": None,
    }
    if ffmpeg_bin is None:
        report["status"] = "FFMPEG_MISSING"
        report["reason"] = "ffmpeg is not on PATH"
        return report
    if not frames:
        report["reason"] = "No JPEG frames to mux"
        return report

    output.parent.mkdir(parents=True, exist_ok=True)
    concat = output.with_suffix(".concat.txt")
    try:
        write_concat_list(frames, concat)
        cmd = [
            str(ffmpeg_bin),
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat),
            "-vf",
            "scale=trunc(iw/2)*2:trunc(ih/2)*2",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-fps_mode",
            "vfr",
            "-movflags",
            "+faststart",
            str(output),
        ]
        proc = _run(cmd, timeout=180)
        if proc.returncode != 0 or not output.exists() or output.stat().st_size == 0:
            report["reason"] = (proc.stderr or proc.stdout or "ffmpeg mux failed").strip()
            return report
        verified = verify_video(output)
        report.update(verified)
        return report
    except FileNotFoundError:
        report["status"] = "FFMPEG_MISSING"
        report["reason"] = f"ffmpeg binary not found: {ffmpeg_bin}"
        return report
    except subprocess.TimeoutExpired:
        report["reason"] = "ffmpeg mux timed out"
        return report
    finally:
        try:
            concat.unlink(missing_ok=True)
        except OSError:
            pass


def verify_video(path: Path, *, ffprobe: Path | None = None, ffmpeg: Path | None = None) -> dict[str, Any]:
    probe_bin = ffprobe or find_ffprobe()
    ffmpeg_bin = ffmpeg or find_ffmpeg()
    report: dict[str, Any] = {
        "status": "FAILED",
        "output": str(path),
        "ffmpeg": str(ffmpeg_bin) if ffmpeg_bin else None,
        "size_bytes": path.stat().st_size if path.exists() else None,
        "ffprobe": None,
        "decode_ok": False,
        "reason": None,
    }
    if not path.exists() or path.stat().st_size == 0:
        report["reason"] = "output file missing or empty"
        return report
    if probe_bin is None:
        report["status"] = "FFMPEG_MISSING"
        report["reason"] = "ffprobe is not on PATH; cannot verify the muxed file"
        return report

    probe = _run(
        [
            str(probe_bin),
            "-v",
            "error",
            "-show_entries",
            "format=duration,format_name,nb_streams,size",
            "-show_entries",
            "stream=codec_name,codec_type,width,height,nb_frames,avg_frame_rate",
            "-of",
            "json",
            str(path),
        ]
    )
    if probe.returncode != 0:
        report["reason"] = (probe.stderr or "ffprobe failed").strip()
        return report
    try:
        info = json.loads(probe.stdout or "{}")
    except json.JSONDecodeError:
        report["reason"] = "ffprobe returned non-JSON"
        return report
    report["ffprobe"] = info
    streams = info.get("streams") or []
    video = next((s for s in streams if s.get("codec_type") == "video"), None)
    if video is None:
        report["reason"] = "ffprobe found no video stream"
        return report
    codec = video.get("codec_name")
    if codec not in {"h264", "hevc", "mpeg4", "vp9", "av1"}:
        report["reason"] = f"unexpected video codec: {codec}"
        return report

    decode_ok = False
    decode_err = None
    if ffmpeg_bin is not None:
        dec = _run(
            [
                str(ffmpeg_bin),
                "-v",
                "error",
                "-i",
                str(path),
                "-f",
                "null",
                "-",
            ]
        )
        decode_ok = dec.returncode == 0 and not (dec.stderr or "").strip()
        decode_err = (dec.stderr or "").strip() or None
    else:
        decode_err = "ffmpeg missing; skipped decode round-trip"

    report["decode_ok"] = decode_ok
    report["codec"] = codec
    report["width"] = video.get("width")
    report["height"] = video.get("height")
    try:
        report["duration_sec"] = float((info.get("format") or {}).get("duration") or 0)
    except (TypeError, ValueError):
        report["duration_sec"] = None

    if not decode_ok:
        report["reason"] = decode_err or "decoded with errors"
        return report
    if not report["duration_sec"] or report["duration_sec"] <= 0:
        report["reason"] = "ffprobe duration is zero"
        return report

    report["status"] = "OK"
    report["reason"] = None
    return report


def extract_frames_ffmpeg(
    video: Path,
    output_dir: Path,
    *,
    fps: float = 2.0,
    ffmpeg: Path | None = None,
) -> dict[str, Any]:
    ffmpeg_bin = ffmpeg or find_ffmpeg()
    report: dict[str, Any] = {
        "status": "FAILED",
        "frames": [],
        "ffmpeg": str(ffmpeg_bin) if ffmpeg_bin else None,
        "reason": None,
    }
    if ffmpeg_bin is None:
        report["status"] = "FFMPEG_MISSING"
        report["reason"] = "ffmpeg is not on PATH"
        return report
    if not video.exists():
        report["reason"] = f"video not found: {video}"
        return report
    output_dir.mkdir(parents=True, exist_ok=True)
    pattern = output_dir / "frame_%04d.jpg"
    proc = _run(
        [
            str(ffmpeg_bin),
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(video),
            "-vf",
            f"fps={fps}",
            "-q:v",
            "3",
            str(pattern),
        ]
    )
    if proc.returncode != 0:
        report["reason"] = (proc.stderr or "extract failed").strip()
        return report
    frames = sorted(output_dir.glob("frame_*.jpg"))
    if not frames:
        report["reason"] = "ffmpeg produced no JPEG frames"
        return report
    report["status"] = "OK"
    report["frames"] = [str(p) for p in frames]
    return report


def synthesize_test_clip(output: Path, *, duration_sec: float = 2.0, fps: int = 10) -> dict[str, Any]:
    """Create a tiny testsrc H.264 MP4. Used only for muxer round-trip tests."""
    ffmpeg_bin = find_ffmpeg()
    if ffmpeg_bin is None:
        return {"status": "FFMPEG_MISSING", "reason": "ffmpeg is not on PATH"}
    output.parent.mkdir(parents=True, exist_ok=True)
    proc = _run(
        [
            str(ffmpeg_bin),
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            f"testsrc=duration={duration_sec}:size=320x240:rate={fps}",
            "-pix_fmt",
            "yuv420p",
            "-c:v",
            "libx264",
            str(output),
        ]
    )
    if proc.returncode != 0 or not output.exists():
        return {
            "status": "FAILED",
            "reason": (proc.stderr or "failed to synthesize test clip").strip(),
        }
    return verify_video(output)
