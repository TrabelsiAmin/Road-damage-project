import { describe, it, expect } from 'vitest';
import {
  assembleObservationRows,
  eventTimeMs,
  mergeObservationPages,
  observationCoordinates,
  OBSERVATION_PAGE_SIZE,
  uniqueObservations,
  utcDayKey,
} from './records';
import { buildDataQualityMetrics, buildExecutiveKpis, filterObservations } from './commandCenterAnalytics';

describe('records', () => {
  it('counts one observation once and does not invent a timestamp', () => {
    const row = {
      id: 'obs-1',
      status: 'unconfirmed',
      anomaly_type: 'D00',
      created_at: '2026-11-01T23:30:00Z',
      detections: [{ class_code: 'D00', confidence: 0.5 }],
    };
    const doubled = uniqueObservations([row, { ...row }]);
    expect(doubled).toHaveLength(1);
    expect(buildDataQualityMetrics([row, row]).totalObservations).toBe(1);
    expect(buildDataQualityMetrics([row, row]).classesBreakdown.D00).toBe(1);
    expect(eventTimeMs({})).toBeNull();
    expect(utcDayKey(Date.parse('2026-11-01T23:30:00Z'))).toBe('2026-11-01');
    expect(filterObservations([{ id: 'undated', status: 'unconfirmed' }], { period: '7' })).toEqual([]);
    const kpis = buildExecutiveKpis([{ id: 'undated', status: 'unconfirmed' }], {}, Date.parse('2026-11-05T00:00:00Z'));
    expect(kpis.newThisWeek).toBe(0);
    expect(kpis.overdueCases).toBe(0);
  });

  it('pages by merging ids and caps a page at 500', () => {
    expect(OBSERVATION_PAGE_SIZE).toBe(500);
    const merged = mergeObservationPages([{ id: 'a' }, { id: 'b' }], [{ id: 'b' }, { id: 'c' }]);
    expect(merged.map((row) => row.id)).toEqual(['a', 'b', 'c']);
  });

  it('keeps a report that has no map point in the catalogue', () => {
    expect(observationCoordinates(undefined, undefined)).toEqual({ latitude: null, longitude: null });
    expect(observationCoordinates(0, 0)).toEqual({ latitude: null, longitude: null });
    const rows = assembleObservationRows(
      [
        { id: 'located', status: 'unconfirmed', is_demo: false, priority_label: 'LOW', priority_score: 10 },
        { id: 'noloc', status: 'unconfirmed', is_demo: false, priority_label: 'CRITICAL', priority_score: 82 },
      ],
      [{ observation_id: 'located', latitude: 36.8, longitude: 10.18, accuracy_meters: 8 }],
    );
    expect(rows).toHaveLength(2);
    expect(rows[1].latitude).toBeNull();
    expect(rows[1].longitude).toBeNull();
    const kpis = buildExecutiveKpis(rows, { demoFilter: 'exclude_demo' }, Date.parse('2026-11-15T00:00:00Z'));
    expect(kpis.totalEvaluated).toBe(2);
    expect(kpis.activeAnomalies).toBe(2);
    expect(kpis.criticalAnomalies).toBe(1);
    expect(kpis.unconfirmedReports).toBe(2);
  });
});
