/**
 * A counter is numeric only after its request succeeds.
 * Loading, HTTP 404, and network failures must not be printed as zero.
 * A successful empty payload still prints 0.
 */

export function visitorCountStatus({ loading = false, publicStatsStatus = 'idle' } = {}) {
  if (publicStatsStatus === 'ready') return 'ready';
  if (loading) return 'loading';
  return 'unavailable';
}

export function authorityCountStatus({ loading = false, error = null, hasPayload = false } = {}) {
  if (hasPayload) return 'ready';
  if (loading) return 'loading';
  if (error) return 'unavailable';
  return 'ready';
}

export function overviewCounters({
  status = 'unavailable',
  resultCount = 0,
  accuracyExcluded = 0,
  accuracyKnown = false,
  lang = 'fr',
} = {}) {
  const french = lang !== 'en';
  const unavailableLabel = french ? 'Indisponible' : 'Unavailable';
  const loadingLabel = french ? 'Chargement…' : 'Loading…';
  let countText = unavailableLabel;
  if (status === 'loading') countText = loadingLabel;
  else if (status === 'ready') countText = String(Math.max(0, Number(resultCount) || 0));

  const clusterHeading = french
    ? `Top clusters prioritaires (${countText})`
    : `Top priority clusters (${countText})`;

  let accuracyLine = null;
  if (status === 'loading') {
    accuracyLine = french
      ? `Positions avec précision > 25 m : ${loadingLabel}`
      : `Positions with accuracy > 25 m: ${loadingLabel}`;
  } else if (status !== 'ready') {
    accuracyLine = french
      ? `Positions avec précision > 25 m : ${unavailableLabel}`
      : `Positions with accuracy > 25 m: ${unavailableLabel}`;
  } else if (accuracyKnown) {
    const excluded = Math.max(0, Number(accuracyExcluded) || 0);
    accuracyLine = french
      ? `Positions avec précision > 25 m non affichées (${excluded} signalements exclus)`
      : `Positions with accuracy > 25 m are hidden (${excluded} reports excluded)`;
  }

  return { countText, clusterHeading, accuracyLine };
}
