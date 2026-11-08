"""EXIF orientation geometry for the capture path.

Flutter and Dart are not installed in this environment, so the app function
in preprocessing.dart is not executed here. These tests check the geometry
the app is written to apply, and that the Dart source still bakes only when
the image is not already upright. Stretch stays a plain resize.
"""
from __future__ import annotations

import io
import unittest
from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[3]
PREPROCESS = ROOT / "app" / "lib" / "inference" / "preprocessing.dart"


def _jpeg(orientation: int | None) -> bytes:
    image = Image.new("RGB", (8, 4), (10, 20, 30))
    image.putpixel((0, 0), (255, 0, 0))
    image.putpixel((7, 3), (0, 0, 255))
    buffer = io.BytesIO()
    save_args = {"format": "JPEG", "quality": 100, "subsampling": 0}
    if orientation is not None:
        exif = image.getexif()
        exif[274] = orientation
        image.save(buffer, exif=exif, **save_args)
    else:
        image.save(buffer, **save_args)
    return buffer.getvalue()


def _is_red(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    return red > 200 and green < 40 and blue < 40


def _is_blue(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    return blue > 200 and red < 40 and green < 40


def _oriented(raw: bytes) -> Image.Image:
    with Image.open(io.BytesIO(raw)) as image:
        orientation = image.getexif().get(274)
        if orientation in (None, 1) or not isinstance(orientation, int) or not 1 <= orientation <= 8:
            return image.copy()
        try:
            return ImageOps.exif_transpose(image)
        except Exception:
            return image.copy()


class ExifOrientationTests(unittest.TestCase):
    def test_upright_keeps_size_and_the_corner_pixel(self):
        raw = _jpeg(1)
        oriented = _oriented(raw)
        self.assertEqual(oriented.size, (8, 4))
        self.assertTrue(_is_red(oriented.getpixel((0, 0))))
        self.assertTrue(raw.startswith(b"\xff\xd8"))

    def test_missing_exif_is_unchanged(self):
        raw = _jpeg(None)
        oriented = _oriented(raw)
        self.assertEqual(oriented.size, (8, 4))
        self.assertTrue(_is_red(oriented.getpixel((0, 0))))

    def test_orientation_3_keeps_the_canvas_and_rotates_pixels(self):
        oriented = _oriented(_jpeg(3))
        self.assertEqual(oriented.size, (8, 4))
        self.assertTrue(_is_red(oriented.getpixel((7, 3))))

    def test_orientation_6_and_8_swap_width_and_height(self):
        turned_6 = _oriented(_jpeg(6))
        turned_8 = _oriented(_jpeg(8))
        self.assertEqual(turned_6.size, (4, 8))
        self.assertEqual(turned_8.size, (4, 8))
        self.assertTrue(_is_red(turned_6.getpixel((3, 0))))
        self.assertTrue(_is_blue(turned_6.getpixel((0, 7))))
        self.assertTrue(_is_red(turned_8.getpixel((0, 7))))
        self.assertTrue(_is_blue(turned_8.getpixel((3, 0))))

    def test_malformed_orientation_does_not_raise(self):
        raw = _jpeg(1)
        image = Image.open(io.BytesIO(raw))
        image.getexif()[274] = 99
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", exif=image.getexif())
        oriented = _oriented(buffer.getvalue())
        self.assertEqual(oriented.size, (8, 4))

    def test_dart_source_bakes_once_and_does_not_change_stretch(self):
        source = PREPROCESS.read_text(encoding="utf-8")
        self.assertIn("if (orientation == null || orientation == 1) return bytes;", source)
        self.assertIn("img.encodeJpg(oriented, quality: 95)", source)
        self.assertIn("return img.copyResize(source, width: inputSize, height: inputSize);", source)
        self.assertEqual(source.count("img.bakeOrientation("), 2)


if __name__ == "__main__":
    unittest.main()
