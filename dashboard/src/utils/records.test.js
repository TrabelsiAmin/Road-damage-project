import { describe, it, expect } from 'vitest';
import {
  eventTimeMs,
  mergeObservationPages,
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
});
