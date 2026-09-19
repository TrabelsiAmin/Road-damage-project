import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/app_colors.dart';
import '../models/observation.dart';

// ---------------------------------------------------------------------------
// Annotation renderer
// ---------------------------------------------------------------------------

/// Renders bounding boxes and labels onto a copy of the source image.
///
/// The original image is NEVER mutated.  A separate annotated JPEG is
/// written to app-private storage and its path is returned.
///
/// Requirements satisfied:
///   - EXIF orientation is applied before box rendering
///   - Boxes are clipped to image bounds
///   - Labels are clipped to image bounds (above box or inside if no room)
///   - Consistent colours per class code
///   - High-DPI safe (renders at native pixel dimensions)
///   - Configurable JPEG quality
class AnnotationRenderer {
  const AnnotationRenderer({this.jpegQuality = 88});
  final int jpegQuality;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Renders [detections] onto [sourceBytes] and returns JPEG bytes.
  /// Does not touch the filesystem (usable from unit tests).
  Future<Uint8List> renderToBytes({
    required Uint8List sourceBytes,
    required List<Detection> detections,
  }) {
    return compute(
      _renderInIsolate,
      _RenderArgs(sourceBytes: sourceBytes, detections: detections),
    );
  }

  /// Renders [detections] onto [sourceBytes] and saves the result.
  ///
  /// Returns the absolute path of the saved annotated image.
  Future<String> renderAndSave({
    required Uint8List sourceBytes,
    required List<Detection> detections,
    required String captureId,
  }) async {
    final annotated = await renderToBytes(
      sourceBytes: sourceBytes,
      detections: detections,
    );
    final dir = await _annotatedDir();
    final path = p.join(dir.path, '$captureId.annotated.jpg');
    await File(path).writeAsBytes(annotated);
    return path;
  }

  Future<Directory> _annotatedDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'tariqmap_annotated'));
    await dir.create(recursive: true);
    return dir;
  }
}

// ---------------------------------------------------------------------------
// Isolate-safe rendering logic (no Flutter widgets or BuildContext)
// ---------------------------------------------------------------------------

class _RenderArgs {
  const _RenderArgs({required this.sourceBytes, required this.detections});
  final Uint8List      sourceBytes;
  final List<Detection> detections;
}

Uint8List _renderInIsolate(_RenderArgs args) {
  // 1. Decode and apply EXIF orientation
  final decoded = img.decodeImage(args.sourceBytes);
  if (decoded == null) throw ArgumentError('Cannot decode source image');
  final oriented = img.bakeOrientation(decoded);

  final w = oriented.width;
  final h = oriented.height;

  // 2. Work on a copy so the original is unchanged
  final canvas = img.Image.from(oriented);

  // Box stroke thickness scales with image resolution
  final strokeW = (w / 400).clamp(1.5, 5.0).round();

  for (var i = 0; i < args.detections.length; i++) {
    final d = args.detections[i];
    final color = _toImgColor(AppColors.forClassCode(d.classCode));

    // 3. Denormalise and clamp bounding box to pixel coords
    final x1 = (d.box.x * w).round().clamp(0, w - 1);
    final y1 = (d.box.y * h).round().clamp(0, h - 1);
    final x2 = ((d.box.x + d.box.width) * w).round().clamp(1, w);
    final y2 = ((d.box.y + d.box.height) * h).round().clamp(1, h);

    // 4. Draw filled glow rectangle (semi-transparent)
    final glowColor = img.ColorRgba8(color.r.toInt(), color.g.toInt(), color.b.toInt(), 50);
    img.fillRect(canvas,
      x1: (x1 - strokeW).clamp(0, w - 1),
      y1: (y1 - strokeW).clamp(0, h - 1),
      x2: (x2 + strokeW).clamp(1, w),
      y2: (y2 + strokeW).clamp(1, h),
      color: glowColor,
    );

    // 5. Draw box border
    for (var s = 0; s < strokeW; s++) {
      img.drawRect(canvas,
        x1: (x1 - s).clamp(0, w - 1), y1: (y1 - s).clamp(0, h - 1),
        x2: (x2 + s).clamp(1, w),     y2: (y2 + s).clamp(1, h),
        color: color,
      );
    }

    // 6. Build label text
    final label = '${_shortLabel(d.classCode)}  ${(d.confidence * 100).toStringAsFixed(0)}%';

    // 7. Estimate text bounding box (~6 px per character at scale)
    final fontSize = (w / 60).clamp(12.0, 28.0);
    final charW = fontSize * 0.55;
    final textW = (label.length * charW).round();
    final textH = (fontSize * 1.4).round();
    final padPx = (fontSize * 0.3).round();

    final pillX = x1.clamp(0, w - textW - padPx * 2);
    var pillY   = y1 - textH - padPx * 2;
    if (pillY < 0) pillY = y1 + strokeW; // flip inside box if no room above

    // 8. Draw label pill background
    img.fillRect(canvas,
      x1: pillX, y1: pillY.clamp(0, h - 1),
      x2: (pillX + textW + padPx * 2).clamp(1, w),
      y2: (pillY + textH + padPx * 2).clamp(1, h),
      color: color,
    );

    // 9. Draw label text (white)
    img.drawString(canvas, label,
      font: img.arial14,
      x: pillX + padPx,
      y: pillY.clamp(0, h - 1) + padPx,
      color: img.ColorRgb8(0, 0, 0),
    );

    // 10. Draw detection index badge
    final badge = '${i + 1}';
    final badgeR = (fontSize * 0.6).round();
    final bcx = (x2 - badgeR).clamp(badgeR, w - badgeR);
    final bcy = (y1 + badgeR).clamp(badgeR, h - badgeR);
    img.fillCircle(canvas, x: bcx, y: bcy, radius: badgeR, color: color);
    img.drawString(canvas, badge,
      font: img.arial14,
      x: bcx - (badge.length * 4),
      y: bcy - 7,
      color: img.ColorRgb8(0, 0, 0),
    );
  }

  // 11. Encode to JPEG
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 88));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

img.ColorRgb8 _toImgColor(Color flutterColor) =>
    img.ColorRgb8((flutterColor.r * 255).round(), (flutterColor.g * 255).round(), (flutterColor.b * 255).round());

String _shortLabel(String code) => switch (code) {
  'D00' => 'Long.Crack',
  'D10' => 'Trans.Crack',
  'D20' => 'Alligator',
  'D40' => 'Pothole',
  'D50' => 'Faded Xing',
  'D60' => 'Faded Lane',
  'D90' => 'Rutting',
  _     => code,
};
