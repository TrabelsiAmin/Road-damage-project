import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { classifyPublicError, publicRequestError } from './publicStats';
import {
  authorityCountStatus,
  overviewCounters,
  visitorCountStatus,
} from './overviewCounters';

const cells = [
  { cell_lat: 36.8, cell_lng: 10.18, report_count: 2 },
  { cell_lat: 36.81, cell_lng: 10.19, report_count: 1 },
];

describe('public response classes', () => {
  it('classifies a missing function as HTTP 404', () => {
    const error = {
      code: 'PGRST202',
      message: 'Could not find the function public.public_damage_summary without parameters in the schema cache',
      status: 404,
    };
    expect(classifyPublicError(error)).toBe('http_404');
    const wrapped = publicRequestError(error, 'Les totaux publics ne sont pas disponibles.');
    expect(wrapped.publicFailure).toBe('http_404');
    expect(wrapped.message).toContain('ne sont pas disponibles');
  });

  it('classifies a dropped connection as a network error', () => {
    expect(classifyPublicError({ message: 'Failed to fetch', status: 0 })).toBe('network');
    expect(classifyPublicError(new TypeError('NetworkError when attempting to fetch resource.'))).toBe('network');
  });
});

describe('visitor counters do not invent a zero', () => {
  it('keeps HTTP 404 off the counters', () => {
    const status = visitorCountStatus({ loading: false, publicStatsStatus: 'unavailable' });
    expect(classifyPublicError({ status: 404, code: 'PGRST202' })).toBe('http_404');
    const copy = overviewCounters({ status, resultCount: 0, accuracyKnown: false, lang: 'fr' });
    expect(copy.clusterHeading).toBe('Top clusters prioritaires (Indisponible)');
    expect(copy.accuracyLine).toBe('Positions avec précision > 25 m : Indisponible');
    expect(copy.clusterHeading).not.toContain('(0)');
    expect(copy.accuracyLine).not.toContain('0 signalements exclus');
  });

  it('keeps a network error off the counters', () => {
    const status = visitorCountStatus({ loading: false, publicStatsStatus: 'unavailable' });
    expect(classifyPublicError({ message: 'Failed to fetch' })).toBe('network');
    const copy = overviewCounters({ status, resultCount: 0, lang: 'fr' });
    expect(copy.countText).toBe('Indisponible');
    expect(copy.accuracyLine).not.toMatch(/\(0 /);
  });

  it('uses the loading sentence instead of zero while the request is in flight', () => {
    const status = visitorCountStatus({ loading: true, publicStatsStatus: 'idle' });
    const copy = overviewCounters({ status, resultCount: 0, lang: 'fr' });
    expect(status).toBe('loading');
    expect(copy.clusterHeading).toBe('Top clusters prioritaires (Chargement…)');
    expect(copy.accuracyLine).not.toContain('0 signalements exclus');
  });

  it('prints a real zero after a successful empty response', () => {
    const status = visitorCountStatus({ loading: false, publicStatsStatus: 'ready' });
    const copy = overviewCounters({ status, resultCount: 0, accuracyKnown: false, lang: 'fr' });
    expect(copy.countText).toBe('0');
    expect(copy.clusterHeading).toBe('Top clusters prioritaires (0)');
    expect(copy.accuracyLine).toBeNull();
  });

  it('prints the returned cell count after a successful response with incidents', () => {
    const status = visitorCountStatus({ loading: false, publicStatsStatus: 'ready' });
    const copy = overviewCounters({ status, resultCount: cells.length, accuracyKnown: false, lang: 'fr' });
    expect(copy.countText).toBe('2');
    expect(copy.clusterHeading).toBe('Top clusters prioritaires (2)');
    expect(copy.clusterHeading).not.toContain('(0)');
  });
});

describe('the overview renders the honest counter copy', () => {
  it('does not print the raw zero expressions', () => {
    const app = fs.readFileSync(path.resolve(__dirname, '../App.jsx'), 'utf8');
    expect(app).toContain('{overviewCount.clusterHeading}');
    expect(app).toContain('{overviewCount.accuracyLine}');
    expect(app).not.toContain('Top clusters prioritaires ({filteredClusters.length})');
    expect(app).not.toContain('{accuracyExcludedCount} signalements exclus');
  });
});

describe('authority counters keep a measured zero', () => {
  it('shows zero exclusions only after a successful load', () => {
    const status = authorityCountStatus({ loading: false, error: null, hasPayload: false });
    const copy = overviewCounters({
      status,
      resultCount: 0,
      accuracyExcluded: 0,
      accuracyKnown: true,
      lang: 'fr',
    });
    expect(copy.clusterHeading).toBe('Top clusters prioritaires (0)');
    expect(copy.accuracyLine).toBe('Positions avec précision > 25 m non affichées (0 signalements exclus)');
  });

  it('does not replace a failed first load with zero', () => {
    const status = authorityCountStatus({
      loading: false,
      error: 'Les totaux publics ne sont pas disponibles.',
      hasPayload: false,
    });
    const copy = overviewCounters({ status, resultCount: 0, accuracyKnown: true, lang: 'fr' });
    expect(status).toBe('unavailable');
    expect(copy.countText).toBe('Indisponible');
    expect(copy.accuracyLine).not.toContain('0 signalements exclus');
  });
});
