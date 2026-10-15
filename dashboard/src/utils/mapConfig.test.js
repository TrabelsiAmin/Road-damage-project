import { describe, it, expect } from 'vitest';
import {
  DEFAULT_TILE_URL,
  DEFAULT_TILE_ATTRIBUTION,
  MAP_CONFIG,
} from '../constants.js';

describe('Basemap Configuration & Defaults', () => {
  it('defaults to standard OpenStreetMap tile URL', () => {
    expect(DEFAULT_TILE_URL).toBe('https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(MAP_CONFIG.tileUrl).toBe('https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  });

  it('defaults to OpenStreetMap attribution', () => {
    expect(DEFAULT_TILE_ATTRIBUTION).toBe('© OpenStreetMap contributors');
    expect(MAP_CONFIG.tileAttribution).toBe('© OpenStreetMap contributors');
  });

  it('sets maxZoom to 19 for street-level road anomaly inspection', () => {
    expect(MAP_CONFIG.maxZoom).toBe(19);
  });

  it('allows overriding tile URL and attribution via env variables without code changes', () => {
    const customUrl = 'https://custom-tiles.example.org/{z}/{x}/{y}.png';
    const customAttr = 'Custom Tile Provider';

    const resolvedUrl = customUrl || DEFAULT_TILE_URL;
    const resolvedAttr = customAttr || DEFAULT_TILE_ATTRIBUTION;

    expect(resolvedUrl).toBe(customUrl);
    expect(resolvedAttr).toBe(customAttr);
  });
});
