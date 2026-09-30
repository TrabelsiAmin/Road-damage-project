import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../models/observation.dart';

// ---------------------------------------------------------------------------
// Color helpers — convert Flutter Color to img.ColorRgb8
// ---------------------------------------------------------------------------

img.ColorRgb8 _classColor(String classCode) {
  final c = AppColors.forClassCode(classCode);
  return img.ColorRgb8(
    (c.r * 255.0).round().clamp(0, 255),
    (c.g * 255.0).round().clamp(0, 255),
    (c.b * 255.0).round().clamp(0, 255),
  );
}

// ---------------------------------------------------------------------------
// Top-level constants (accessible inside compute() isolate)
// ---------------------------------------------------------------------------

const int _borderThick = 4;
const int _fillAlpha   = 55;   // 0-255

// ---------------------------------------------------------------------------
// Isolate payload
// ---------------------------------------------------------------------------

class _AnnotateArgs {
  const _AnnotateArgs({
    required this.inputPath,
    required this.outputPath,
    required this.detections,
  });
  final String inputPath;
  final String outputPath;
  final List<Detection> detections;
}

// ---------------------------------------------------------------------------
// FrameAnnotator
// ---------------------------------------------------------------------------

/// Burns YOLO bounding boxes and class labels onto JPEG frames as pixel data.
///
/// Uses the [image] package (pure Dart) via [compute()] so rendering never
/// blocks the UI thread.
class FrameAnnotator {
  const FrameAnnotator();

  /// Annotates [frameFile] with [detections] and saves the result next to it
  /// with an `ann_` prefix. Returns the annotated [File], or the original on error.
  Future<File> annotateFrame(File frameFile, List<Detection> detections) async {
    if (detections.isEmpty) return frameFile;
    try {
      return await compute(_annotateInIsolate, _AnnotateArgs(
        inputPath:  frameFile.path,
        outputPath: '${frameFile.parent.path}/ann_${frameFile.uri.pathSegments.last}',
        detections: detections,
      ));
    } catch (e) {
      debugPrint('[FrameAnnotator] error: $e');
      return frameFile;
    }
  }
}

// ---------------------------------------------------------------------------
// Pixel drawing — runs in compute() isolate (no Flutter/UI imports)
// ---------------------------------------------------------------------------

File _annotateInIsolate(_AnnotateArgs args) {
  final bytes = File(args.inputPath).readAsBytesSync();
  final src   = img.decodeImage(bytes);
  if (src == null) return File(args.inputPath);

  final canvas = img.Image.from(src);
  final W = canvas.width;
  final H = canvas.height;

  for (final d in args.detections) {
    final color = _classColor(d.classCode);

    final x1 = (d.box.x * W).clamp(0.0, W - 1.0).toInt();
    final y1 = (d.box.y * H).clamp(0.0, H - 1.0).toInt();
    final x2 = ((d.box.x + d.box.width)  * W).clamp(0.0, W - 1.0).toInt();
    final y2 = ((d.box.y + d.box.height) * H).clamp(0.0, H - 1.0).toInt();

    // Semi-transparent fill
    _drawFilledRect(canvas, x1, y1, x2, y2, color);

    // Solid border (thick)
    for (var t = 0; t < _borderThick; t++) {
      _drawRectBorder(
        canvas,
        (x1 - t).clamp(0, W - 1),
        (y1 - t).clamp(0, H - 1),
        (x2 + t).clamp(0, W - 1),
        (y2 + t).clamp(0, H - 1),
        color,
      );
    }

    // Corner L-shaped accents
    _drawCornerAccents(canvas, x1, y1, x2, y2, color);

    // Label pill above the box
    final label =
        '${TariqMapConstants.labelFor(d.classCode)} '
        '${(d.confidence * 100).toStringAsFixed(0)}%';
    _drawLabelPill(canvas, x1, y1, label, color);
  }

  final outBytes = img.encodeJpg(canvas, quality: 90);
  return File(args.outputPath)..writeAsBytesSync(outBytes);
}

// ---------------------------------------------------------------------------
// Drawing primitives
// ---------------------------------------------------------------------------

void _drawFilledRect(
  img.Image canvas, int x1, int y1, int x2, int y2, img.ColorRgb8 color,
) {
  final alpha = _fillAlpha / 255.0;
  final minY = y1.clamp(0, canvas.height - 1);
  final maxY = y2.clamp(0, canvas.height - 1);
  final minX = x1.clamp(0, canvas.width  - 1);
  final maxX = x2.clamp(0, canvas.width  - 1);
  for (var py = minY; py <= maxY; py++) {
    for (var px = minX; px <= maxX; px++) {
      final src = canvas.getPixel(px, py);
      final r = (src.r * (1 - alpha) + color.r * alpha).round().clamp(0, 255);
      final g = (src.g * (1 - alpha) + color.g * alpha).round().clamp(0, 255);
      final b = (src.b * (1 - alpha) + color.b * alpha).round().clamp(0, 255);
      canvas.setPixelRgb(px, py, r, g, b);
    }
  }
}

void _drawRectBorder(
  img.Image canvas, int x1, int y1, int x2, int y2, img.ColorRgb8 color,
) {
  for (var x = x1; x <= x2; x++) {
    canvas.setPixelRgb(x, y1, color.r, color.g, color.b);
    canvas.setPixelRgb(x, y2, color.r, color.g, color.b);
  }
  for (var y = y1; y <= y2; y++) {
    canvas.setPixelRgb(x1, y, color.r, color.g, color.b);
    canvas.setPixelRgb(x2, y, color.r, color.g, color.b);
  }
}

void _drawCornerAccents(
  img.Image canvas, int x1, int y1, int x2, int y2, img.ColorRgb8 color,
) {
  final len   = math.min(20, (math.min(x2 - x1, y2 - y1) / 4).toInt());
  const thick = 3;

  final corners = [
    (x1, y1,  1,  1),
    (x2, y1, -1,  1),
    (x1, y2,  1, -1),
    (x2, y2, -1, -1),
  ];
  for (final (cx, cy, dx, dy) in corners) {
    for (var i = 0; i < len; i++) {
      for (var t = 0; t < thick; t++) {
        final px = (cx + dx * i).clamp(0, canvas.width  - 1);
        final py = (cy + t * dy).clamp(0, canvas.height - 1);
        canvas.setPixelRgb(px, py, color.r, color.g, color.b);
      }
    }
    for (var i = 0; i < len; i++) {
      for (var t = 0; t < thick; t++) {
        final px = (cx + t * dx).clamp(0, canvas.width  - 1);
        final py = (cy + dy * i).clamp(0, canvas.height - 1);
        canvas.setPixelRgb(px, py, color.r, color.g, color.b);
      }
    }
  }
}

void _drawLabelPill(
  img.Image canvas, int x1, int y1, String label, img.ColorRgb8 bgColor,
) {
  const charW = 7;
  const charH = 13;
  const padX  = 6;
  const padY  = 4;

  final pillW = label.length * charW + padX * 2;
  final pillH = charH + padY * 2;
  // .toInt() needed because clamp() on int vs num returns num in Dart
  final pillX = x1.clamp(0, math.max(0, canvas.width  - pillW)).toInt();
  final pillY = (y1 - pillH - 2).clamp(0, math.max(0, canvas.height - pillH)).toInt();

  img.fillRect(
    canvas,
    x1: pillX,
    y1: pillY,
    x2: pillX + pillW,
    y2: pillY + pillH,
    color: bgColor,
  );

  img.drawString(
    canvas,
    label,
    font:  img.arial14,
    x:     pillX + padX,
    y:     pillY + padY,
    color: img.ColorRgb8(255, 255, 255),
  );
}
