import 'dart:math' as math;
import '../models/observation.dart';

/// Tunable constants for Priority Scoring v2.
class PriorityScoringConfig {
  const PriorityScoringConfig._();

  /// Detections below this confidence are ignored as noise.
  static const double minConfidenceThreshold = 0.25;

  /// Confidence below which D40 is barred from reaching HIGH.
  static const double d40HighConfidenceThreshold = 0.50;

  /// Reference box area (10% of image area) at which area factor reaches 1.0.
  static const double areaReference = 0.10;

  /// Multiplier for other detections contributing to count bonus.
  static const double bonusScale = 2.5;

  /// Maximum count bonus across all other detections.
  static const double maxCountBonus = 10.0;

  /// Priority thresholds.
  static const double lowThreshold = 35.0;
  static const double highThreshold = 65.0;

  /// Canonical class weights for Priority Scoring v2.
  static const Map<String, double> classWeights = {
    'D40': 1.00, // Pothole — highest physical road hazard
    'D20': 0.85, // Alligator crack — structural pavement fatigue
    'D10': 0.50, // Transverse crack
    'D00': 0.40, // Longitudinal crack
  };

  static const double defaultClassWeight = 0.40;
}

/// Result returned by [calculatePriorityScoreV2].
class PriorityScoreResult {
  const PriorityScoreResult({
    required this.score,
    required this.label,
    this.worstClassCode,
    this.worstConfidence,
    required this.baseScore,
    required this.countBonus,
  });

  /// Final priority score in range [0..100], rounded to 2 decimal places.
  final double score;

  /// Priority label: 'LOW' (< 35), 'MEDIUM' (35–65), or 'HIGH' (> 65).
  final String label;

  /// Class code of the anchor detection.
  final String? worstClassCode;

  /// Confidence of the anchor detection.
  final double? worstConfidence;

  /// Score derived from the worst detection alone.
  final double baseScore;

  /// Bonus added from other detections (capped at +10.0).
  final double countBonus;
}

/// Pure function implementing Priority Scoring v2.
///
/// Anchored on the WORST detection plus bounded bonuses, strictly capped at 100.
/// Identical logic is implemented in `dashboard/src/utils/priorityScoring.js`.
PriorityScoreResult calculatePriorityScoreV2(List<Detection> detections) {
  // 1. Filter: ignore detections below 0.25 confidence
  final valid = detections
      .where((d) => d.confidence >= PriorityScoringConfig.minConfidenceThreshold)
      .toList();

  if (valid.isEmpty) {
    return const PriorityScoreResult(
      score: 0.0,
      label: 'LOW',
      worstClassCode: null,
      worstConfidence: null,
      baseScore: 0.0,
      countBonus: 0.0,
    );
  }

  // 2. Score each detection to find the worst (anchor) detection
  // Area factor: sqrt(box area / image area), capped, so small boxes don't look severe.
  final scoredDetections = valid.map((d) {
    final weight = PriorityScoringConfig.classWeights[d.classCode] ??
        PriorityScoringConfig.defaultClassWeight;

    // Normalised bounding box area [0..1]
    final area = (d.box.width * d.box.height).clamp(0.0, 1.0);
    final areaFactor = area > 0.0
        ? math.min(1.0, math.sqrt(area / PriorityScoringConfig.areaReference))
        : 0.0;

    final severityScore = weight * d.confidence * areaFactor * 100.0;
    return (
      detection: d,
      weight: weight,
      areaFactor: areaFactor,
      severityScore: severityScore,
    );
  }).toList();

  // Find worst detection (highest individual severity score)
  var worst = scoredDetections.first;
  for (var i = 1; i < scoredDetections.length; i++) {
    if (scoredDetections[i].severityScore > worst.severityScore) {
      worst = scoredDetections[i];
    }
  }

  final baseScore = worst.severityScore;

  // 3. Count bonus: at most +10 across the other detections
  var bonusSum = 0.0;
  var removedWorst = false;
  for (final item in scoredDetections) {
    if (!removedWorst && identical(item.detection, worst.detection)) {
      removedWorst = true;
      continue;
    }
    bonusSum += item.weight * item.detection.confidence * PriorityScoringConfig.bonusScale;
  }
  final countBonus = math.min(PriorityScoringConfig.maxCountBonus, bonusSum);

  var rawScore = math.min(100.0, baseScore + countBonus);

  // 4. Special rule:
  // The pothole model is weak: say so in the code comments.
  // A D40 cannot reach HIGH below 0.50 confidence.
  if (worst.detection.classCode == 'D40' &&
      worst.detection.confidence < PriorityScoringConfig.d40HighConfidenceThreshold) {
    // The pothole model is weak: cap D40 below HIGH threshold (<= 65.0) when confidence < 0.50.
    rawScore = math.min(rawScore, PriorityScoringConfig.highThreshold);
  }

  // Round to 2 decimal places for golden vector parity across Dart and JS
  final score = double.parse(rawScore.toStringAsFixed(2));

  // 5. Determine label
  final String label;
  if (score < PriorityScoringConfig.lowThreshold) {
    label = 'LOW';
  } else if (score > PriorityScoringConfig.highThreshold) {
    label = 'HIGH';
  } else {
    label = 'MEDIUM';
  }

  return PriorityScoreResult(
    score: score,
    label: label,
    worstClassCode: worst.detection.classCode,
    worstConfidence: worst.detection.confidence,
    baseScore: double.parse(baseScore.toStringAsFixed(2)),
    countBonus: double.parse(countBonus.toStringAsFixed(2)),
  );
}
