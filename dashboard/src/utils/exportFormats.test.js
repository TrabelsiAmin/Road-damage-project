import { describe, it, expect } from 'vitest';
import {
  buildExportRows,
  generateCsvString,
  generateGeoJson,
  generatePublicAggregateCsv,
} from './exportFormats';

describe('exportFormats', () => {
  const mockObservations = [
    {
      id: 'obs-test-1',
      latitude: 36.8065,
      longitude: 10.1815,
      anomaly_type: 'D40',
      priority_score: 85,
      priority_label: 'HIGH',
      status: 'unconfirmed',
      accuracy_meters: 4.5,
      is_demo: false,
      created_at: '2026-11-01T10:00:00Z',
    },
  ];

  it('buildExportRows populates all operational columns', () => {
    const rows = buildExportRows(mockObservations);
    expect(rows.length).toBe(1);
    expect(rows[0].id).toBe('obs-test-1');
    expect(rows[0].classCode).toBe('D40');
    expect(rows[0].typeLabel).toBe('D40');
    expect(rows[0].governorate).toBe('Tunis');
    expect(rows[0].estimatedCostTnd).toBeNull();
  });

  it('generateCsvString produces valid UTF-8 BOM CSV text', () => {
    const csv = generateCsvString(mockObservations);
    expect(csv.startsWith('\uFEFF')).toBe(true);
    expect(csv).toContain('ID Signalement');
    expect(csv).toContain('obs-test-1');
    expect(csv).toContain('D40');
    expect(csv).toContain('unavailable');
    expect(csv).not.toContain('280');
  });

  it('generateGeoJson produces standard GeoJSON FeatureCollection', () => {
    const geoJson = generateGeoJson(mockObservations);
    expect(geoJson.type).toBe('FeatureCollection');
    expect(geoJson.features.length).toBe(1);
    expect(geoJson.features[0].geometry.type).toBe('Point');
    expect(geoJson.features[0].geometry.coordinates[0]).toBeCloseTo(10.1815);
    expect(geoJson.features[0].geometry.coordinates[1]).toBeCloseTo(36.8065);
    expect(geoJson.features[0].properties.class_code).toBe('D40');
  });

  it('public aggregate csv omits observation ids and measured coordinates', () => {
    const csv = generatePublicAggregateCsv(
      [{ anomaly_type: 'D40', priority_band: 'high', open_count: 2, repaired_count: 1 }],
      [{ cell_lat: 36.805, cell_lng: 10.185, report_count: 2, dominant_class: 'D40' }]
    );
    expect(csv).toContain('anomaly_type;priority_band;open_count;repaired_count');
    expect(csv).toContain('centre_maille_lat;centre_maille_lng;report_count;dominant_class');
    expect(csv).toContain('D40;high;2;1');
    expect(csv).toContain('36.805;10.185;2;D40');
    expect(csv).not.toContain('obs-test-1');
    expect(csv).not.toContain('cccccccc-cccc-4ccc-8ccc-ccccccccccc1');
    expect(csv).not.toContain('36.80651');
    expect(csv).not.toContain('10.18151');
    expect(csv.toLowerCase()).not.toContain('device');
    expect(csv.toLowerCase()).not.toContain('budget');
  });
});
