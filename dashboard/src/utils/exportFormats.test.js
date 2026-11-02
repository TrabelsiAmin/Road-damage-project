import { describe, it, expect } from 'vitest';
import {
  buildExportRows,
  generateCsvString,
  generateGeoJson,
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
    expect(rows[0].typeLabel).toContain('poule');
    expect(rows[0].governorate).toBe('Tunis');
    expect(rows[0].estimatedCostTnd).toBe(280);
  });

  it('generateCsvString produces valid UTF-8 BOM CSV text', () => {
    const csv = generateCsvString(mockObservations);
    expect(csv.startsWith('\uFEFF')).toBe(true);
    expect(csv).toContain('ID Signalement');
    expect(csv).toContain('obs-test-1');
    expect(csv).toContain('D40');
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
});
