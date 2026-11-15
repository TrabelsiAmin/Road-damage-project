import { describe, expect, it } from 'vitest';
import { mapLoadCopy, mapLoadState } from './mapLoadState';

describe('map load state', () => {
  it('keeps a technical failure distinct from an empty result', () => {
    expect(mapLoadState({ loading: false, error: 'missing function', markerCount: 0 })).toBe('error');
    expect(mapLoadState({ loading: false, error: null, markerCount: 0 })).toBe('empty');
    expect(mapLoadCopy('error', 'fr')).toContain('erreur technique');
    expect(mapLoadCopy('error', 'fr')).not.toContain('Aucune anomalie');
    expect(mapLoadCopy('empty', 'fr')).toContain('Aucune anomalie');
  });

  it('shows markers as ready even while a background refresh runs', () => {
    expect(mapLoadState({ loading: true, error: null, markerCount: 3 })).toBe('ready');
  });
});
