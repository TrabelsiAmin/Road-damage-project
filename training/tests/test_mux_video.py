import json
import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.ffmpeg_tools import (
    extract_frames_ffmpeg,
    find_ffmpeg,
    find_ffprobe,
    frame_durations_sec,
    mux_jpeg_sequence,
    synthesize_test_clip,
    verify_video,
)
from src.process_video import process_video


class DurationMathTests(unittest.TestCase):
    def test_uses_timestamp_deltas_and_source_tail(self):
        durs = frame_durations_sec([0, 500, 1000], 1500)
        self.assertEqual(len(durs), 3)
        self.assertAlmostEqual(durs[0], 0.5)
        self.assertAlmostEqual(durs[1], 0.5)
        self.assertAlmostEqual(durs[2], 0.5)

    def test_empty(self):
        self.assertEqual(frame_durations_sec([], 1000), [])


@unittest.skipUnless(find_ffmpeg() and find_ffprobe(), "ffmpeg/ffprobe not installed")
class FfmpegMuxRoundTripTests(unittest.TestCase):
    def test_missing_ffmpeg_path_is_honest(self):
        with tempfile.TemporaryDirectory() as td:
            jpg = Path(td) / "a.jpg"
            jpg.write_bytes(b"not-a-jpeg")
            report = mux_jpeg_sequence(
                [(jpg, 0.2)],
                Path(td) / "out.mp4",
                ffmpeg=Path("/no/such/ffmpeg"),
            )
            # shutil.which is bypassed; the given binary will fail to run
            self.assertIn(report["status"], {"FAILED", "FFMPEG_MISSING"})
            self.assertFalse(report["decode_ok"])

    def test_synthesize_extract_mux_verify_playable(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            src = root / "src.mp4"
            syn = synthesize_test_clip(src, duration_sec=1.0, fps=10)
            self.assertEqual(syn["status"], "OK", syn)
            self.assertTrue(syn["decode_ok"])
            self.assertEqual(syn["codec"], "h264")

            frames_dir = root / "frames"
            extracted = extract_frames_ffmpeg(src, frames_dir, fps=5)
            self.assertEqual(extracted["status"], "OK", extracted)
            self.assertGreaterEqual(len(extracted["frames"]), 3)

            out = root / "annotated.mp4"
            report = process_video(src, out, fps=5, work_dir=frames_dir)
            self.assertEqual(report["status"], "OK", report)
            self.assertTrue(report["decode_ok"])
            self.assertEqual(report["codec"], "h264")
            self.assertGreater(report["size_bytes"], 1000)
            self.assertGreater(report["duration_sec"], 0.2)
            self.assertTrue(out.exists())

            again = verify_video(out)
            self.assertEqual(again["status"], "OK", again)
            self.assertTrue(again["decode_ok"])

            # Persist a copy of the probe for humans; tests must not invent metrics.
            (root / "probe.json").write_text(json.dumps(again, indent=2))


if __name__ == "__main__":
    unittest.main()
