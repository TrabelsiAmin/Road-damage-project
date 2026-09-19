import 'dart:math' as math;
import '../models/observation.dart';

// ---------------------------------------------------------------------------
// IoU calculation — pure Dart, no Flutter dependency, fully unit-testable
// ---------------------------------------------------------------------------

/// Computes Intersection over Union for two axis-aligned bounding boxes.
/// Boxes are in normalised [0, 1] coordinate space (x, y = top-left corner).
double computeIou(BoundingBox a, BoundingBox b) {
  final ix1 = math.max(a.x, b.x);
  final iy1 = math.max(a.y, b.y);
  final ix2 = math.min(a.x + a.width,  b.x + b.width);
  final iy2 = math.min(a.y + a.height, b.y + b.height);

  final iw = (ix2 - ix1).clamp(0.0, double.infinity);
  final ih = (iy2 - iy1).clamp(0.0, double.infinity);
  final intersection = iw * ih;
  if (intersection == 0) return 0;

  final aArea = a.width * a.height;
  final bArea = b.width * b.height;
  final unionArea = aArea + bArea - intersection;
  if (unionArea <= 0) return 0;
  return intersection / unionArea;
}

// ---------------------------------------------------------------------------
// Non-Maximum Suppression
// ---------------------------------------------------------------------------

/// Applies class-agnostic NMS and returns the kept detections.
///
/// [detections] is sorted by confidence descending before processing.
/// Boxes with IoU > [iouThreshold] against a higher-confidence box are removed.
/// [minConfidence] filters detections below the threshold before NMS.
List<Detection> applyNms(
  List<Detection> detections, {
  double iouThreshold = 0.45,
  double minConfidence = 0.0,
}) {
  // 1. Filter by confidence
  final candidates = detections
      .where((d) => d.confidence >= minConfidence)
      .toList()
    ..sort((a, b) => b.confidence.compareTo(a.confidence));

  final kept = <Detection>[];
  final suppressed = <int>{};

  for (var i = 0; i < candidates.length; i++) {
    if (suppressed.contains(i)) continue;
    kept.add(candidates[i]);
    for (var j = i + 1; j < candidates.length; j++) {
      if (suppressed.contains(j)) continue;
      if (computeIou(candidates[i].box, candidates[j].box) > iouThreshold) {
        suppressed.add(j);
      }
    }
  }
  return kept;
}

// ---------------------------------------------------------------------------
// Per-class NMS (suppresses only within same class)
// ---------------------------------------------------------------------------

/// Applies NMS per class independently, then returns all kept detections
/// sorted by confidence descending.
List<Detection> applyClassAwareNms(
  List<Detection> detections, {
  double iouThreshold = 0.45,
  double minConfidence = 0.0,
}) {
  // Group by class code
  final byClass = <String, List<Detection>>{};
  for (final d in detections) {
    (byClass[d.classCode] ??= []).add(d);
  }

  final result = <Detection>[];
  for (final classDetections in byClass.values) {
    result.addAll(applyNms(
      classDetections,
      iouThreshold: iouThreshold,
      minConfidence: minConfidence,
    ));
  }

  result.sort((a, b) => b.confidence.compareTo(a.confidence));
  return result;
}
