/**
 * Tunable constants for Priority Scoring v2.
 */
export const PRIORITY_CONFIG = {
  minConfidenceThreshold: 0.25,
  d40HighConfidenceThreshold: 0.50,
  areaReference: 0.10, // Normalized box area at which area factor reaches 1.0 (10% of image)
  bonusScale: 2.5,
  maxCountBonus: 10.0,
  lowThreshold: 35.0,
  highThreshold: 65.0,
  classWeights: {
    D40: 1.00, // Pothole — highest safety risk
    D20: 0.85, // Alligator crack — structural pavement fatigue
    D10: 0.50, // Transverse crack
    D00: 0.40, // Longitudinal crack
  },
  defaultClassWeight: 0.40,
};

/**
 * Pure function implementing Priority Scoring v2.
 *
 * Anchored on the WORST detection plus bounded bonuses; never above 100.
 * Identical logic is implemented in Dart (`app/lib/utils/priority_scoring.dart`).
 *
 * @param {Array} detections - List of detection objects { classCode, confidence, box: { width, height } }
 * @returns {Object} { score: number, label: string, worstClassCode, worstConfidence, baseScore, countBonus }
 */
export function calculatePriorityScore(detections = []) {
  // 1. Filter: ignore detections below 0.25 confidence
  const valid = (detections || []).filter(
    (d) => d && typeof d.confidence === 'number' && d.confidence >= PRIORITY_CONFIG.minConfidenceThreshold
  );

  if (valid.length === 0) {
    return {
      score: 0.0,
      label: 'LOW',
      worstClassCode: null,
      worstConfidence: null,
      baseScore: 0.0,
      countBonus: 0.0,
    };
  }

  // 2. Score each detection to find the worst (anchor) detection
  // Area factor: sqrt(box area / image area), capped, so small boxes don't look severe.
  const scoredDetections = valid.map((d) => {
    const weight = PRIORITY_CONFIG.classWeights[d.classCode] ?? PRIORITY_CONFIG.defaultClassWeight;

    // Normalised bounding box area [0..1]
    const box = d.box || {};
    const bw = typeof box.width === 'number' ? box.width : (typeof d.box_w === 'number' ? d.box_w : 0);
    const bh = typeof box.height === 'number' ? box.height : (typeof d.box_h === 'number' ? d.box_h : 0);
    const area = Math.max(0.0, Math.min(1.0, bw * bh));

    const areaFactor = area > 0.0
      ? Math.min(1.0, Math.sqrt(area / PRIORITY_CONFIG.areaReference))
      : 0.0;

    const severityScore = weight * d.confidence * areaFactor * 100.0;

    return {
      detection: d,
      weight,
      areaFactor,
      severityScore,
    };
  });

  // Find worst detection (highest individual severity score)
  let worst = scoredDetections[0];
  for (let i = 1; i < scoredDetections.length; i++) {
    if (scoredDetections[i].severityScore > worst.severityScore) {
      worst = scoredDetections[i];
    }
  }

  const baseScore = worst.severityScore;

  // 3. Count bonus: at most +10 across the other detections
  let bonusSum = 0.0;
  let removedWorst = false;
  for (const item of scoredDetections) {
    if (!removedWorst && item === worst) {
      removedWorst = true;
      continue;
    }
    bonusSum += item.weight * item.detection.confidence * PRIORITY_CONFIG.bonusScale;
  }
  const countBonus = Math.min(PRIORITY_CONFIG.maxCountBonus, bonusSum);

  let rawScore = Math.min(100.0, baseScore + countBonus);

  // 4. Special rule:
  // The pothole model is weak: say so in the code comments.
  // A D40 cannot reach HIGH below 0.50 confidence.
  if (
    worst.detection.classCode === 'D40' &&
    worst.detection.confidence < PRIORITY_CONFIG.d40HighConfidenceThreshold
  ) {
    // The pothole model is weak: cap D40 below HIGH threshold (<= 65.0) when confidence < 0.50.
    rawScore = Math.min(rawScore, PRIORITY_CONFIG.highThreshold);
  }

  // Round to 2 decimal places for golden vector parity across Dart and JS
  const score = Math.round(rawScore * 100) / 100;

  // 5. Determine label
  let label = 'LOW';
  if (score < PRIORITY_CONFIG.lowThreshold) {
    label = 'LOW';
  } else if (score > PRIORITY_CONFIG.highThreshold) {
    label = 'HIGH';
  } else {
    label = 'MEDIUM';
  }

  return {
    score,
    label,
    worstClassCode: worst.detection.classCode,
    worstConfidence: worst.detection.confidence,
    baseScore: Math.round(baseScore * 100) / 100,
    countBonus: Math.round(countBonus * 100) / 100,
  };
}
