import '../models/observation.dart';
import 'nms.dart';

/// Decodes a legacy `road_damage.tflite` output buffer.
///
/// Measured interpreter layout (float32): `[1, 8, 8400]`.
/// Index as `output[0][channel][anchor]`:
/// channels 0..3 are cx, cy, w, h in normalized stretched-canvas space;
/// channels 4..7 are class scores for indices 0..3.
/// This is not the RoadSense layout `[1, 9, 8400]`.
///
/// Boxes are converted from center format to top-left and clamped to `[0, 1]`.
/// No letterbox unscale is applied, because the matching preprocess is stretch.
/// Class-aware NMS uses [iouThreshold].
List<Detection> decodeLegacyYoloOutput({
  required List<dynamic> output,
  required Map<int, String> classNames,
  required List<String> agentClasses,
  required Map<String, double> classThresholds,
  double iouThreshold = 0.45,
  double fallbackThreshold = 0.35,
  double? d40ThresholdOverride,
  bool onlyD40 = false,
  String agentName = 'road_damage',
}) {
  final numClasses = classNames.length;
  final numAnchors = (output[0][0] as List).length;
  final rawDetections = <Detection>[];

  for (var anchor = 0; anchor < numAnchors; anchor++) {
    double bestScore = 0;
    var bestClass = -1;

    for (var c = 0; c < numClasses; c++) {
      final score = (output[0][4 + c][anchor] as num).toDouble();
      if (score > bestScore) {
        bestScore = score;
        bestClass = c;
      }
    }

    if (bestClass == -1) continue;
    final className = classNames[bestClass];
    if (className == null) continue;

    if (onlyD40 && className != 'D40') continue;
    final thresh = (className == 'D40' && d40ThresholdOverride != null)
        ? d40ThresholdOverride
        : (classThresholds[className] ?? fallbackThreshold);
    if (bestScore < thresh) continue;
    if (!agentClasses.contains(className)) continue;

    final cx = (output[0][0][anchor] as num).toDouble().clamp(0.0, 1.0);
    final cy = (output[0][1][anchor] as num).toDouble().clamp(0.0, 1.0);
    final bw = (output[0][2][anchor] as num).toDouble().clamp(0.0, 1.0);
    final bh = (output[0][3][anchor] as num).toDouble().clamp(0.0, 1.0);

    rawDetections.add(Detection(
      agent: agentName,
      classCode: className,
      confidence: bestScore,
      box: BoundingBox(
        x: (cx - bw / 2).clamp(0.0, 1.0),
        y: (cy - bh / 2).clamp(0.0, 1.0),
        width: bw,
        height: bh,
      ),
    ));
  }

  return applyClassAwareNms(rawDetections, iouThreshold: iouThreshold);
}

/// Shape gate used by the legacy runner. RoadSense `[1, 9, 8400]` must fail.
bool isLegacyRoadDamageOutputShape(List<int> shape) {
  return shape.length == 3 &&
      shape[0] == 1 &&
      shape[1] == 8 &&
      shape[2] == 8400;
}
