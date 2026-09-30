import '../models/observation.dart';
import 'letterbox_math.dart';

/// One decoded YOLO candidate before NMS, in original-image normalised space.
class YoloCandidate {
  const YoloCandidate({
    required this.classIndex,
    required this.score,
    required this.box,
  });

  final int classIndex;
  final double score;
  final BoundingBox box;
}

/// Interprets a YOLOv8 TFLite output tensor.
///
/// Supported layouts (batch squeezed):
///   - `[4+C, N]`  Ultralytics default (channels-first)
///   - `[N, 4+C]`  channels-last
///
/// Box coordinates may be pixels in letterbox space or already normalised.
/// [LetterboxMeta.boxFromYolo] handles both.
List<YoloCandidate> decodeYoloOutput({
  required List<List<double>> output,
  required LetterboxMeta letterbox,
  required int numClasses,
  required double confidenceThreshold,
  double minBoxArea = 0.0,
}) {
  if (output.isEmpty || output.first.isEmpty) return const [];

  final dim0 = output.length;
  final dim1 = output.first.length;
  final channelsFirst = dim0 == 4 + numClasses;
  final channelsLast = dim1 == 4 + numClasses;

  if (!channelsFirst && !channelsLast) {
    throw FormatException(
      'Unexpected YOLO output layout ${dim0}x$dim1 '
      '(expected 4+$numClasses on one axis)',
    );
  }

  final numAnchors = channelsFirst ? dim1 : dim0;
  final candidates = <YoloCandidate>[];

  double at(int channel, int anchor) =>
      channelsFirst ? output[channel][anchor] : output[anchor][channel];

  for (var anchor = 0; anchor < numAnchors; anchor++) {
    var bestScore = 0.0;
    var bestClass = -1;
    for (var c = 0; c < numClasses; c++) {
      final score = at(4 + c, anchor);
      if (score > bestScore) {
        bestScore = score;
        bestClass = c;
      }
    }
    if (bestScore < confidenceThreshold || bestClass < 0) continue;

    final (x, y, w, h) = letterbox.boxFromYolo(
      at(0, anchor),
      at(1, anchor),
      at(2, anchor),
      at(3, anchor),
    );
    if (w <= 0 || h <= 0) continue;
    if (minBoxArea > 0 && w * h < minBoxArea) continue;

    candidates.add(YoloCandidate(
      classIndex: bestClass,
      score: bestScore,
      box: BoundingBox(x: x, y: y, width: w, height: h),
    ));
  }
  return candidates;
}

/// Flattens a TFLite nested output buffer into `[dim0][dim1]`.
///
/// Accepts `[1, A, B]` or `[A, B]`.
List<List<double>> squeezeYoloOutput(dynamic raw) {
  if (raw is List && raw.isNotEmpty) {
    final first = raw.first;
    if (first is List && first.isNotEmpty && first.first is List) {
      // [1, A, B]
      return (first as List)
          .map<List<double>>((row) =>
              (row as List).map((v) => (v as num).toDouble()).toList())
          .toList();
    }
    if (first is List) {
      return raw
          .map<List<double>>((row) =>
              (row as List).map((v) => (v as num).toDouble()).toList())
          .toList();
    }
  }
  throw FormatException('Cannot interpret YOLO output tensor of type ${raw.runtimeType}');
}
