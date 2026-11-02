import { describe, it, expect } from 'vitest';
import { isValidLatLng, filterValidClusters } from './mapValidation';

describe('Map Coordinate & Cluster Validation', () => {
  it('identifies valid geodetic coordinates', () => {
    // Grand Tunis coordinates
    expect(isValidLatLng(36.8065, 10.1815)).toBe(true);
    expect(isValidLatLng('36.8065', '10.1815')).toBe(true);
    // Extremities
    expect(isValidLatLng(-90, -180)).toBe(true);
    expect(isValidLatLng(90, 180)).toBe(true);
  });

  it('rejects Null Island (0, 0) default coordinates', () => {
    expect(isValidLatLng(0, 0)).toBe(false);
    expect(isValidLatLng('0', '0')).toBe(false);
  });

  it('rejects non-finite, null, undefined, or NaN coordinates', () => {
    expect(isValidLatLng(null, 10.18)).toBe(false);
    expect(isValidLatLng(36.8, undefined)).toBe(false);
    expect(isValidLatLng(NaN, 10.18)).toBe(false);
    expect(isValidLatLng(Infinity, 10.18)).toBe(false);
    expect(isValidLatLng('abc', 10.18)).toBe(false);
  });

  it('rejects out-of-bounds latitudes and longitudes', () => {
    expect(isValidLatLng(91, 10)).toBe(false);
    expect(isValidLatLng(-91, 10)).toBe(false);
    expect(isValidLatLng(36, 181)).toBe(false);
    expect(isValidLatLng(36, -181)).toBe(false);
  });

  it('filters clusters down to valid instances only', () => {
    const mixedClusters = [
      { id: 'c1', latitude: 36.8065, longitude: 10.1815, count: 3 },
      { id: 'c2', latitude: null, longitude: 10.1815, count: 1 },
      { id: 'c3', latitude: 0, longitude: 0, count: 2 },
      { id: 'c4', latitude: 36.85, longitude: '10.20', count: 4 },
      { id: 'c5', latitude: 'invalid', longitude: 10.20, count: 1 },
    ];

    const valid = filterValidClusters(mixedClusters);
    expect(valid).toHaveLength(2);
    expect(valid.map((c) => c.id)).toEqual(['c1', 'c4']);
  });

  it('handles empty, null, or invalid input gracefully', () => {
    expect(filterValidClusters([])).toEqual([]);
    expect(filterValidClusters(null)).toEqual([]);
    expect(filterValidClusters(undefined)).toEqual([]);
  });
});
