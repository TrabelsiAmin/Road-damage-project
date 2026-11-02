import { describe, it, expect } from 'vitest';
import {
  resolveTunisiaAdmin,
  ALL_GOVERNORATES,
  getMunicipalitiesForGovernorate,
} from './tunisiaGeo';

describe('tunisiaGeo reverse lookup', () => {
  it('correctly identifies Tunis Centre coordinates', () => {
    // 36.8000, 10.1800 is central Tunis
    const res = resolveTunisiaAdmin(36.8000, 10.1800);
    expect(res.governorate).toBe('Tunis');
    expect(res.municipality).toContain('Tunis');
  });

  it('correctly identifies La Marsa in northern Tunis', () => {
    // 36.8800, 10.3200 is La Marsa / Gammarth
    const res = resolveTunisiaAdmin(36.8800, 10.3200);
    expect(res.governorate).toBe('Tunis');
    expect(res.municipality).toBe('La Marsa');
  });

  it('correctly identifies Ariana Ville and La Soukra', () => {
    const resAriana = resolveTunisiaAdmin(36.8665, 10.1956);
    expect(resAriana.governorate).toBe('Ariana');

    const resSoukra = resolveTunisiaAdmin(36.8750, 10.2500);
    expect(resSoukra.governorate).toBe('Ariana');
    expect(resSoukra.municipality).toBe('La Soukra');
  });

  it('correctly identifies Sousse coordinates', () => {
    const res = resolveTunisiaAdmin(35.8256, 10.6369);
    expect(res.governorate).toBe('Sousse');
  });

  it('returns safe fallback for invalid coordinates', () => {
    const res = resolveTunisiaAdmin(0, 0);
    expect(res.governorate).toBe('Non déterminé');
    expect(res.roadSegment).toBe('Voie non répertoriée');
  });

  it('lists municipalities for selected governorate', () => {
    const munis = getMunicipalitiesForGovernorate('Tunis');
    expect(munis).toContain('La Marsa');
    expect(munis).toContain('Carthage');
  });
});
