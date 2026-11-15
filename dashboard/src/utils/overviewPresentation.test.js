import { describe, expect, it } from 'vitest';
import { buildOverviewPresentation, formatIncidentDate, periodDelta } from './overviewPresentation';

const tunis = {
  id: 'obs-tunis',
  status: 'confirmed',
  anomaly_type: 'D40',
  latitude: 36.8065,
  longitude: 10.1815,
  created_at: '2024-03-01T12:00:00.000Z',
  organization_id: 'org-1',
};

const sousse = {
  id: 'obs-sousse',
  status: 'repaired',
  anomaly_type: 'D00',
  latitude: 35.8256,
  longitude: 10.6369,
  created_at: '2024-02-01T12:00:00.000Z',
};

describe('overview presentation', () => {
  it('formats a real timestamp in Africa/Tunis', () => {
    expect(formatIncidentDate('2024-03-01T12:00:00.000Z', 'fr')).toBe('1 mars 2024');
    expect(formatIncidentDate('not-a-date', 'fr')).toBeNull();
  });

  it('omits the period delta unless both windows have reports', () => {
    expect(periodDelta({ previousTotal: 0, totalPct: null }, 4)).toBeNull();
    expect(periodDelta(null, 4)).toBeNull();
    expect(periodDelta({ previousTotal: 4, totalPct: -100 }, 0)).toBeNull();
    expect(periodDelta({ previousTotal: 2, totalPct: 50 }, 3)).toEqual({ pct: 50, previous: 2 });
  });

  it('counts loaded observations by stored class code and derived place', () => {
    const view = buildOverviewPresentation({
      canSeeRows: true,
      figureStatus: 'ready',
      observations: [
        tunis,
        sousse,
        { ...tunis, id: 'rejected', status: 'rejected', created_at: '2024-04-01T12:00:00.000Z' },
      ],
      authorityTotal: 2,
      authorityClassCounts: { D40: 1, D20: 0, D10: 0, D00: 1, other: 0 },
      comparison: { previousTotal: 1, totalPct: 100 },
      organizations: [{ id: 'org-1', name: 'Direction test' }],
      lang: 'fr',
    });

    expect(view.total).toBe(2);
    expect(view.delta).toEqual({ pct: 100, previous: 1 });
    expect(view.chart.mode).toBe('class');
    expect(view.chart.title).toBe('Répartition par classe');
    expect(view.chart.slices.map((slice) => slice.label)).toEqual(['D40', 'D00']);
    expect(view.zoneCount).toBe(2);
    expect(view.regions.map((region) => region.label).sort()).toEqual(['Sousse', 'Tunis']);
    expect(view.rows).toHaveLength(2);
    expect(view.rows[0].id).toBe('obs-tunis');
    expect(view.rows[0].classCode).toBe('D40');
    expect(view.rows[0].organization).toBe('Direction test');
    expect(view.rows.map((row) => row.id)).not.toContain('rejected');
    expect(view.tableState).toBe('rows');
  });

  it('sums public aggregate groups and hides individual rows', () => {
    const view = buildOverviewPresentation({
      canSeeRows: false,
      figureStatus: 'ready',
      publicSummary: [
        { anomaly_type: 'D40', priority_band: 'high', open_count: 40, repaired_count: 5 },
        { anomaly_type: 'D00', priority_band: 'low', open_count: 30, repaired_count: 2 },
      ],
      publicCells: [{ cell_lat: 36.8065, cell_lng: 10.1815, report_count: 77 }],
      lang: 'fr',
    });

    expect(view.total).toBe(77);
    expect(view.chart.slices.map((slice) => slice.label)).toEqual(['D40', 'D00']);
    expect(view.zoneCount).toBe(1);
    expect(view.rows).toEqual([]);
    expect(view.tableState).toBe('restricted');
    expect(view.lastIncident).toBeNull();
    expect(view.delta).toBeNull();
  });

  it('does not turn a failed public load into zero', () => {
    const view = buildOverviewPresentation({
      canSeeRows: false,
      figureStatus: 'unavailable',
      publicSummary: [{ anomaly_type: 'D40', open_count: 40, repaired_count: 5 }],
    });
    expect(view.total).toBeNull();
    expect(view.routeCount).toBeNull();
    expect(view.chart).toBeNull();
    expect(view.tableState).toBe('restricted');
  });

  it('mentions the catalogue size only when the loaded page is truncated', () => {
    const view = buildOverviewPresentation({
      canSeeRows: true,
      figureStatus: 'ready',
      observations: [tunis],
      authorityTotal: 1,
      catalogueTotal: 9,
      loadedCount: 1,
      listTruncated: true,
      lang: 'fr',
    });
    expect(view.total).toBe(1);
    expect(view.totalNote).toBe('1 signalement chargé pour les totaux, 9 au catalogue.');
  });
});
