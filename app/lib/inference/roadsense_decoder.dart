import '../core/constants.dart';
import '../models/observation.dart';
import 'nms.dart';
import 'preprocessing.dart';

/// Class names emitted by the RoadSense YOLOv12 model.
///
/// Classes 0..2 (D00, D10, D20) are kept for observations.
/// Class 3 (D40) and Class 4 (Repair) are ignored for road damage observations.
/// Repair boxes are optionally retained solely to filter false potholes.
const roadSenseClassNames = <int, String>{
  0: 'D00',    // Longitudinal crack
  1: 'D10',    // Transverse crack
  2: 'D20',    // Alligator crack
  3: 'D40',    // Pothole (ignored from RoadSense)
  4: 'Repair', // Repaired asphalt (ignored for damage observations)
};

/// Result container returned by [RoadSenseDecoder.decode].
class RoadSenseDecodedResult {
  const RoadSenseDecodedResult({
    required this.crackDetections,
    required this.repairDetections,
    this.rawCandidateCount = 0,
  });

  /// Road damage crack detections (D00, D10, D20) after class-wise NMS.
  final List<Detection> crackDetections;

  /// Road repair detections after class-wise NMS (used to filter false potholes).
  final List<Detection> repairDetections;

  /// Number of raw candidates passing confidence threshold before NMS.
  final int rawCandidateCount;
}

/// Decodes raw [1, 9, 8400] RoadSense model output into [Detection] objects.
///
/// Features:
/// 1. Finds per-anchor max class score across all 5 classes (channels 4..8).
/// 2. Applies class-specific confidence thresholds.
/// 3. Converts normalized letterboxed coordinates back to original image space
///    by undoing scale and padding.
/// 4. Filters to keep only classes 0, 1, 2 (D00, D10, D20), ignoring D40 and Repair
///    for observations.
/// 5. Applies class-wise NMS (default IoU 0.45).
class RoadSenseDecoder {
  const RoadSenseDecoder();

  /// Decodes a 3D output buffer [1, 9, 8400] given the [letterbox] metadata.
  static RoadSenseDecodedResult decode({
    required List<dynamic> output,
    required LetterboxResult letterbox,
    String agentName = 'road_damage_roadsense',
    double d00Threshold = TariqMapConstants.roadSenseD00Threshold,
    double d10Threshold = TariqMapConstants.roadSenseD10Threshold,
    double d20Threshold = TariqMapConstants.roadSenseD20Threshold,
    double repairThreshold = TariqMapConstants.roadSenseRepairThreshold,
    double iouThreshold = TariqMapConstants.defaultIouThreshold,
    bool retainRepairs = true,
  }) {
    final rawCracks = <Detection>[];
    final rawRepairs = <Detection>[];

    // output is [1, 9, 8400]
    final channels = output[0] as List<dynamic>;
    final numAnchors = (channels[0] as List<dynamic>).length;

    for (var a = 0; a < numAnchors; a++) {
      // Find highest scoring class among 0..4
      var bestScore = 0.0;
      var bestClass = -1;

      for (var c = 0; c < 5; c++) {
        final score = (channels[4 + c][a] as num).toDouble();
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }

      if (bestClass == -1) continue;

      // Extract letterbox-normalized coordinates [0..1]
      final cx = (channels[0][a] as num).toDouble();
      final cy = (channels[1][a] as num).toDouble();
      final w = (channels[2][a] as num).toDouble();
      final h = (channels[3][a] as num).toDouble();

      // Check thresholds & map back to original image coordinates
      if (bestClass == 0 && bestScore >= d00Threshold) {
        rawCracks.add(Detection(
          agent: agentName,
          classCode: 'D00',
          confidence: bestScore,
          box: letterbox.toOriginalNormalized(cx, cy, w, h),
        ));
      } else if (bestClass == 1 && bestScore >= d10Threshold) {
        rawCracks.add(Detection(
          agent: agentName,
          classCode: 'D10',
          confidence: bestScore,
          box: letterbox.toOriginalNormalized(cx, cy, w, h),
        ));
      } else if (bestClass == 2 && bestScore >= d20Threshold) {
        rawCracks.add(Detection(
          agent: agentName,
          classCode: 'D20',
          confidence: bestScore,
          box: letterbox.toOriginalNormalized(cx, cy, w, h),
        ));
      } else if (bestClass == 4 && retainRepairs && bestScore >= repairThreshold) {
        rawRepairs.add(Detection(
          agent: agentName,
          classCode: 'Repair',
          confidence: bestScore,
          box: letterbox.toOriginalNormalized(cx, cy, w, h),
        ));
      }
      // Note: class 3 (D40) from RoadSense is ignored.
    }

    final nmsCracks = applyClassAwareNms(rawCracks, iouThreshold: iouThreshold);
    final nmsRepairs = retainRepairs
        ? applyClassAwareNms(rawRepairs, iouThreshold: iouThreshold)
        : const <Detection>[];

    return RoadSenseDecodedResult(
      crackDetections: nmsCracks,
      repairDetections: nmsRepairs,
      rawCandidateCount: rawCracks.length,
    );
  }

  /// Optional helper: drops old-model D40 detections if a RoadSense "Repair"
  /// box overlaps it with IoU > [iouThreshold] (filters patched-asphalt false potholes).
  static List<Detection> filterPotholesOverlappingRepairs(
    List<Detection> potholeDetections,
    List<Detection> repairDetections, {
    double iouThreshold = 0.5,
  }) {
    if (repairDetections.isEmpty) return potholeDetections;

    return potholeDetections.where((pothole) {
      for (final repair in repairDetections) {
        if (computeIou(pothole.box, repair.box) > iouThreshold) {
          return false; // Suppressed by overlapping Repair patch
        }
      }
      return true;
    }).toList();
  }
}
