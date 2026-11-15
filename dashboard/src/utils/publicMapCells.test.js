import { describe, expect, it } from 'vitest';
import {
  aggregatePublicMapCells,
  catalogueMapNote,
  catalogueReportCount,
  catalogueVisibleStats,
  preferWiderCells,
  publicCellSize,
} from './publicMapCells';

describe('public map cells', () => {
  it('keeps the cell at least about one kilometre', () => {
    expect(publicCellSize(0.0001)).toBe(0.01);
    expect(publicCellSize(0.02)).toBe(0.02);
  });

  it('groups real reports on a cell center and drops demos, rejections, and ids', () => {
    const cells = aggregatePublicMapCells([
      { is_demo: false, status: 'unconfirmed', anomaly_type: 'D40', latitude: 37.2649983, longitude: 9.8778872, id: 'secret-1' },
      { is_demo: false, status: 'confirmed', anomaly_type: 'D00', latitude: 37.2649779, longitude: 9.8778506, id: 'secret-2' },
      { is_demo: false, status: 'unconfirmed', anomaly_type: 'D40', latitude: 37.2601, longitude: 9.8701 },
      { is_demo: true, status: 'unconfirmed', anomaly_type: 'D20', latitude: 36.8, longitude: 10.18 },
      { is_demo: false, status: 'rejected', anomaly_type: 'D20', latitude: 36.8, longitude: 10.18 },
      { is_demo: false, status: 'unconfirmed', anomaly_type: 'D00', latitude: 0, longitude: 0 },
    ]);

    expect(cells).toEqual([
      { cell_lat: 37.265, cell_lng: 9.875, report_count: 3, dominant_class: 'D40' },
    ]);
    expect(JSON.stringify(cells)).not.toContain('secret');
    expect(cells[0].cell_lat).not.toBe(37.2649983);
    expect(cells[0].cell_lng).not.toBe(9.8778872);
  });

  it('breaks a class tie by code, with an unnamed class last', () => {
    const cells = aggregatePublicMapCells([
      { is_demo: false, status: 'unconfirmed', anomaly_type: 'D40', latitude: 36.81, longitude: 10.19 },
      { is_demo: false, status: 'unconfirmed', anomaly_type: null, latitude: 36.812, longitude: 10.191 },
      { is_demo: false, status: 'unconfirmed', anomaly_type: 'D20', latitude: 36.813, longitude: 10.192 },
    ]);
    expect(cells[0].dominant_class).toBe('D20');
    expect(cells[0].report_count).toBe(3);
  });

  it('counts the same real reports the cells group, without ids', () => {
    const points = [
      { is_demo: false, status: 'unconfirmed', anomaly_type: 'D40', latitude: 37.2649983, longitude: 9.8778872, id: 'secret-1' },
      { is_demo: false, status: 'confirmed', anomaly_type: 'D00', latitude: 37.2649779, longitude: 9.8778506, id: 'secret-2' },
      { is_demo: false, status: 'unconfirmed', anomaly_type: 'D40', latitude: 37.2601, longitude: 9.8701 },
      { is_demo: true, status: 'unconfirmed', anomaly_type: 'D20', latitude: 36.8, longitude: 10.18 },
      { is_demo: false, status: 'rejected', anomaly_type: 'D20', latitude: 36.8, longitude: 10.18 },
    ];
    const stats = catalogueVisibleStats(points);
    expect(stats.reports).toBe(3);
    expect(stats.classes).toEqual([
      { anomaly_type: 'D40', count: 2 },
      { anomaly_type: 'D00', count: 1 },
    ]);
    expect(JSON.stringify(stats)).not.toContain('secret');
    expect(catalogueReportCount(aggregatePublicMapCells(points))).toBe(3);
  });

  it('does not replace a known catalogue with a shorter one', () => {
    const wider = [{ cell_lat: 36.8, cell_lng: 10.18, report_count: 21 }];
    const shorter = [{ cell_lat: 36.8, cell_lng: 10.18, report_count: 4 }];
    expect(preferWiderCells(wider, shorter)).toBe(wider);
    expect(preferWiderCells(wider, [])).toBe(wider);
    expect(catalogueReportCount(preferWiderCells(shorter, wider))).toBe(21);
  });

  it('says the official total is a 404, not a national total', () => {
    const note = catalogueMapNote({ cells: 15, reports: 21, lang: 'fr' });
    expect(note).toContain('21 signalements réels');
    expect(note).toContain('15 mailles');
    expect(note).toContain('HTTP 404');
    expect(note).not.toContain('128');
    expect(catalogueMapNote({ cells: 1, reports: 1, lang: 'en' })).toContain('unavailable (HTTP 404)');
  });
});
