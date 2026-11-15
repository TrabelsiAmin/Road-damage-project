import { describe, it, expect } from 'vitest';
import { canDownloadPublicExport, publicCountText, publicSituationText } from './publicStats';

describe('public stats availability', () => {
  it('shows Indisponible when the public functions fail', () => {
    expect(publicSituationText({ status: 'unavailable', summary: [], lang: 'fr' })).toBe('Indisponible');
    expect(publicCountText(0, 'unavailable', 'fr')).toBe('Indisponible');
    expect(publicCountText(undefined, 'idle', 'en')).toBe('Unavailable');
    expect(canDownloadPublicExport('unavailable')).toBe(false);
    expect(canDownloadPublicExport('idle')).toBe(false);
  });

  it('keeps a real zero only after a successful response', () => {
    expect(publicSituationText({ status: 'ready', summary: [], lang: 'fr' })).toBe('Aucun total public pour le moment.');
    expect(publicCountText(0, 'ready', 'fr')).toBe('0');
    expect(canDownloadPublicExport('ready')).toBe(true);
  });

  it('prints the returned totals when the functions succeed', () => {
    const text = publicSituationText({
      status: 'ready',
      lang: 'fr',
      summary: [{ anomaly_type: 'D40', priority_band: 'high', open_count: 2, repaired_count: 1 }],
    });
    expect(text).toBe('D40 · high · 2 ouverts · 1 réparés');
  });
});
