/**
 * Road Segment Risk Scoring & Explanation Engine
 *
 * Implements a transparent, deterministic risk calculation based on real observation
 * data (defect class, priority scores, report density, backlog age, and GPS quality).
 */

import { DAMAGE_CLASSES } from '../constants';
import { resolveTunisiaAdmin } from './tunisiaGeo';
import { haversineDistanceMeters } from './clustering';

export const RISK_LEVELS = {
  CRITICAL: { label: 'CRITIQUE', color: '#EF4444', minScore: 70 },
  HIGH: { label: 'ÉLEVÉ', color: '#F97316', minScore: 50 },
  MEDIUM: { label: 'MOYEN', color: '#EAB308', minScore: 30 },
  LOW: { label: 'FAIBLE', color: '#3B82F6', minScore: 0 },
};

/**
 * Calculates risk level from score.
 */
export function getRiskLevel(score) {
  if (score >= RISK_LEVELS.CRITICAL.minScore) return 'CRITICAL';
  if (score >= RISK_LEVELS.HIGH.minScore) return 'HIGH';
  if (score >= RISK_LEVELS.MEDIUM.minScore) return 'MEDIUM';
  return 'LOW';
}

/**
 * Generates transparent, human-readable justification for the computed score.
 */
export function generateRiskExplanation({
  activeReportsCount,
  dominantClass,
  potholeCount,
  maxPriorityScore,
  oldestAgeDays,
  importanceWeight = 1.0,
}) {
  const points = [];

  if (activeReportsCount > 0) {
    points.push(`${activeReportsCount} signalement${activeReportsCount > 1 ? 's' : ''} actif${activeReportsCount > 1 ? 's' : ''}`);
  }

  if (potholeCount > 0) {
    points.push(`${potholeCount} nid${potholeCount > 1 ? 's' : ''}-de-poule (D40) nécessitant un rebouchage urgent`);
  } else if (dominantClass === 'D20') {
    points.push('Faïençage structurel (D20) indiquant une fatigue du sous-sol');
  } else if (dominantClass === 'D00' || dominantClass === 'D10') {
    points.push('Fissuration linéaire continue requérant un pontage d\'étanchéité');
  }

  if (oldestAgeDays > 30) {
    points.push(`Défaut non résolu depuis ${oldestAgeDays} jours (seuil d'arriéré dépassé)`);
  } else if (oldestAgeDays > 14) {
    points.push(`Signalement en attente depuis ${oldestAgeDays} jours`);
  }

  if (maxPriorityScore >= 65) {
    points.push(`Score de sévérité maximal élevé (${maxPriorityScore.toFixed(1)}/100)`);
  }

  if (importanceWeight > 1.0) {
    points.push(`Axe stratégique prioritaire (pondération trafic ${importanceWeight.toFixed(2)}x)`);
  }

  return points.length > 0
    ? `Facteurs déterminants : ${points.join(' • ')}.`
    : 'Observation standard sans facteur aggravant.';
}

/**
 * Aggregates a list of observations into geographic road segments / corridors
 * and evaluates their composite risk score.
 */
export function computeRoadSegmentsRisk(observations, { minRiskFilter = 'ALL' } = {}) {
  if (!observations || observations.length === 0) return [];

  // 1. Group observations by spatial corridor / municipality segment
  const segmentBuckets = new Map();

  observations.forEach((obs) => {
    if (obs.status === 'rejected') return;

    const lat = Number(obs.latitude);
    const lng = Number(obs.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

    const geo = resolveTunisiaAdmin(lat, lng);
    // Key by corridor + municipality
    const key = `${geo.roadSegment}::${geo.governorate}::${geo.municipality}`;

    if (!segmentBuckets.has(key)) {
      segmentBuckets.set(key, {
        segmentKey: key,
        roadName: geo.roadSegment,
        governorate: geo.governorate,
        municipality: geo.municipality,
        centroidLat: lat,
        centroidLng: lng,
        reports: [],
      });
    }

    segmentBuckets.get(key).reports.push(obs);
  });

  // 2. Score each segment
  const results = [];
  const now = Date.now();

  for (const bucket of segmentBuckets.values()) {
    const reps = bucket.reports;
    const active = reps.filter((r) => r.status !== 'repaired');
    const repaired = reps.filter((r) => r.status === 'repaired');

    // Counts by class
    let d40Count = 0;
    let d20Count = 0;
    let d10Count = 0;
    let d00Count = 0;
    let maxPriorityScore = 0;
    let oldestTimestamp = now;

    let estimatedBudget = 0;

    reps.forEach((r) => {
      const cls = r.anomaly_type || r.detections?.[0]?.class_code || 'D40';
      const score = Number(r.priority_score) || 50;
      if (score > maxPriorityScore) maxPriorityScore = score;

      const t = new Date(r.created_at || r.captured_at || now).getTime();
      if (t < oldestTimestamp) oldestTimestamp = t;

      if (cls === 'D40') {
        d40Count++;
        estimatedBudget += DAMAGE_CLASSES.D40.defaultCostTnd;
      } else if (cls === 'D20') {
        d20Count++;
        estimatedBudget += DAMAGE_CLASSES.D20.defaultCostTnd;
      } else if (cls === 'D10') {
        d10Count++;
        estimatedBudget += DAMAGE_CLASSES.D10.defaultCostTnd;
      } else {
        d00Count++;
        estimatedBudget += DAMAGE_CLASSES.D00.defaultCostTnd;
      }
    });

    const dominantClass =
      d40Count > 0 ? 'D40' : d20Count > 0 ? 'D20' : d10Count > 0 ? 'D10' : 'D00';

    const oldestAgeDays = Math.max(0, Math.floor((now - oldestTimestamp) / (1000 * 60 * 60 * 24)));

    // Base severity weight
    let baseSeverity = 15;
    if (dominantClass === 'D40') baseSeverity = 35;
    else if (dominantClass === 'D20') baseSeverity = 28;
    else if (dominantClass === 'D10') baseSeverity = 18;

    // Corridor importance weight
    const isAutoroute = bucket.roadName.includes('Autoroute') || bucket.roadName.startsWith('A');
    const isRN = bucket.roadName.includes('Nationale') || bucket.roadName.startsWith('RN');
    const importanceWeight = isAutoroute ? 1.4 : isRN ? 1.25 : 1.0;

    // Composite risk calculation
    const rawScore =
      baseSeverity +
      maxPriorityScore * 0.25 +
      Math.min(active.length * 4.0, 20.0) +
      Math.min(oldestAgeDays * 0.35, 15.0);

    const calculatedRiskScore = Math.min(100, Math.round(rawScore * importanceWeight * 10) / 10);
    const riskLevel = getRiskLevel(calculatedRiskScore);

    const explanation = generateRiskExplanation({
      activeReportsCount: active.length,
      dominantClass,
      potholeCount: d40Count,
      maxPriorityScore,
      oldestAgeDays,
      importanceWeight,
    });

    if (
      minRiskFilter === 'ALL' ||
      minRiskFilter === riskLevel ||
      (minRiskFilter === 'CRITICAL' && calculatedRiskScore >= 70) ||
      (minRiskFilter === 'HIGH' && calculatedRiskScore >= 50)
    ) {
      results.push({
        segmentKey: bucket.segmentKey,
        roadName: bucket.roadName,
        governorate: bucket.governorate,
        municipality: bucket.municipality,
        centroidLat: bucket.centroidLat,
        centroidLng: bucket.centroidLng,
        totalReports: reps.length,
        activeReportsCount: active.length,
        repairedCount: repaired.length,
        dominantClass,
        d40Count,
        maxPriorityScore,
        oldestAgeDays,
        importanceWeight,
        riskScore: calculatedRiskScore,
        riskLevel,
        estimatedBudgetTnd: estimatedBudget,
        explanation,
      });
    }
  }

  // Sort by highest risk score first
  return results.sort((a, b) => b.riskScore - a.riskScore);
}

/**
 * High-level helper for the Command Center corridor matrix view.
 */
export function computeAllCorridorRisks(observations) {
  const segments = computeRoadSegmentsRisk(observations);

  return segments.map((seg, idx) => {
    const levelInfo = RISK_LEVELS[seg.riskLevel] || RISK_LEVELS.LOW;

    // Filter member anomalies for this corridor
    const memberAnomalies = (observations || []).filter((obs) => {
      const geo = resolveTunisiaAdmin(obs.latitude, obs.longitude);
      return (
        geo.roadSegment === seg.roadName &&
        geo.governorate === seg.governorate &&
        geo.municipality === seg.municipality
      );
    });

    return {
      code: seg.roadName.includes('Autoroute') ? seg.roadName.split(' ')[1] || `AXE-${idx + 1}` : `AXE-${idx + 1}`,
      name: `${seg.roadName} (${seg.municipality}, ${seg.governorate})`,
      reportCount: seg.totalReports,
      anomaliesCount: seg.activeReportsCount,
      dominantClass: seg.dominantClass,
      maxAgeDays: seg.oldestAgeDays,
      estimatedBudgetTnd: seg.estimatedBudgetTnd,
      riskScore: Math.round(seg.riskScore),
      riskLevel: levelInfo.label,
      levelColor: levelInfo.color,
      scoreExplanation: seg.explanation,
      anomalies: memberAnomalies,
    };
  });
}
