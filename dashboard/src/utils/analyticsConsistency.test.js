import { describe, it, expect } from 'vitest';
import {
  buildDataQualityMetrics,
  buildExecutiveKpis,
  filterObservations,
} from './commandCenterAnalytics';
import { clusterObservations } from './clustering';
import { buildExportRows } from './exportFormats';
import { computeRoadSegmentsRisk } from './roadSegmentRisk';
import { UNKNOWN_CLASS_LABEL } from './classCodes';

const incomplete = [
  {
    id: 'missing-class',
    latitude: 36.81,
    longitude: 10.19,
    status: 'unconfirmed',
    accuracy_meters: 4,
    created_at: '2026-11-01T00:00:00Z',
    detections: [{ confidence: 0.91 }],
  },
  {
    id: 'unknown-class',
    latitude: 36.8101,
    longitude: 10.1901,
    status: 'confirmed',
    anomaly_type: 'D99',
    priority_score: 10,
    accuracy_meters: 6,
    created_at: '2026-11-02T00:00:00Z',
    detections: [{ class_code: 'D99', confidence: 0.2 }],
  },
  {
    id: 'known',
    latitude: 36.82,
    longitude: 10.2,
    status: 'unconfirmed',
    anomaly_type: 'D00',
    priority_score: 20,
    accuracy_meters: 5,
    created_at: '2026-11-03T00:00:00Z',
    detections: [{ class_code: 'D00', confidence: 0.5 }],
  },
];

describe('analytics consistency', () => {
  it('keeps an empty set empty', () => {
    const quality = buildDataQualityMetrics([]);
    expect(quality.highConfidencePercent).toBeNull();
    expect(quality.totalObservations).toBe(0);
    expect(quality.classesBreakdown).toEqual({ D40: 0, D20: 0, D10: 0, D00: 0 });

    const kpis = buildExecutiveKpis([]);
    expect(kpis.activeAnomalies).toBe(0);
    expect(kpis.repairCompletionRate).toBeNull();
    expect(kpis.estimatedOpenBudgetTnd).toBeNull();
    expect(kpis.avgResolutionDays).toBeNull();
    expect(filterObservations([], { anomalyClass: 'D40' })).toEqual([]);
  });

  it('does not count a missing or unknown class as D40', () => {
    expect(filterObservations(incomplete, { anomalyClass: 'D40' })).toEqual([]);
    const d00 = filterObservations(incomplete, { anomalyClass: 'D00' });
    expect(d00.map((row) => row.id)).toEqual(['known']);

    const quality = buildDataQualityMetrics(incomplete);
    const bucketSum = Object.values(quality.classesBreakdown).reduce((sum, n) => sum + n, 0);
    expect(quality.classesBreakdown.D40).toBe(0);
    expect(quality.classesBreakdown.D00).toBe(1);
    expect(quality.unspecifiedClassCount).toBe(2);
    expect(bucketSum + quality.unspecifiedClassCount).toBe(3);
    expect(quality.totalObservations).toBe(incomplete.length);

    const clusters = clusterObservations(structuredClone([incomplete[0], incomplete[1]]), 50, 25);
    expect(clusters).toHaveLength(1);
    expect(clusters[0].dominantClass).toBeNull();

    const rows = buildExportRows([structuredClone(incomplete[0])]);
    expect(rows[0].classCode).toBe(UNKNOWN_CLASS_LABEL);
    expect(rows[0].estimatedCostTnd).toBeNull();
    expect(rows[0].priorityScore).toBe('');
    expect(rows[0].priorityLabel).toBe('');

    const segments = computeRoadSegmentsRisk(incomplete);
    const unknown = segments.reduce((sum, seg) => sum + seg.unknownClassCount, 0);
    const d40 = segments.reduce((sum, seg) => sum + seg.d40Count, 0);
    expect(unknown).toBe(2);
    expect(d40).toBe(0);

    const kpis = buildExecutiveKpis(incomplete, {}, Date.parse('2026-11-05T00:00:00Z'));
    const knownOnly = buildExecutiveKpis([incomplete[2]], {}, Date.parse('2026-11-05T00:00:00Z'));
    const unknownOnly = buildExecutiveKpis([incomplete[1]], {}, Date.parse('2026-11-05T00:00:00Z'));
    expect(kpis.estimatedOpenBudgetTnd).toBeNull();
    expect(knownOnly.estimatedOpenBudgetTnd).toBeNull();
    expect(unknownOnly.estimatedOpenBudgetTnd).toBeNull();
  });
});
