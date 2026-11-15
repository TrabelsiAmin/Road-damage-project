/**
 * Public totals are real only after both aggregate functions succeed.
 * A missing function or an error is unavailable, never a count of zero.
 */

export function canDownloadPublicExport(status) {
  return status === 'ready';
}

/**
 * A missing PostgREST function is HTTP 404. A dropped connection is a network
 * error. Both are unavailable counts, never a successful zero.
 */
export function classifyPublicError(error) {
  const status = Number(error?.status ?? error?.statusCode ?? error?.response?.status);
  const code = String(error?.code || '');
  const message = `${error?.message || ''} ${error?.details || ''} ${error?.hint || ''}`;
  if (
    status === 404
    || code === 'PGRST202'
    || /\b404\b|PGRST202|schema cache|could not find the function/i.test(message)
  ) {
    return 'http_404';
  }
  if (
    status === 0
    || code === 'NETWORK'
    || /failed to fetch|networkerror|network request failed|timeout|econn|enotfound|load failed/i.test(message)
  ) {
    return 'network';
  }
  return 'unavailable';
}

export function publicRequestError(error, fallbackMessage) {
  const wrapped = new Error(fallbackMessage);
  wrapped.publicFailure = classifyPublicError(error);
  return wrapped;
}

/**
 * Sums the aggregate rows. The length of the summary is the number of
 * groups, not the number of anomalies.
 */
export function publicDamageTotals(summary) {
  if (!Array.isArray(summary)) return null;
  let open = 0;
  let repaired = 0;
  let highOpen = 0;
  for (const row of summary) {
    const openCount = Number(row?.open_count);
    const repairedCount = Number(row?.repaired_count);
    const openValue = Number.isFinite(openCount) ? openCount : 0;
    const repairedValue = Number.isFinite(repairedCount) ? repairedCount : 0;
    open += openValue;
    repaired += repairedValue;
    const band = String(row?.priority_band || '').toLowerCase();
    if (band === 'high' || band === 'critical') highOpen += openValue;
  }
  return { open, repaired, highOpen, total: open + repaired };
}

export function publicCatalogueText({ status, summary = [], lang = 'fr' } = {}) {
  if (status !== 'ready') return publicSituationText({ status, summary, lang });
  const totals = publicDamageTotals(summary);
  if (!totals || !Array.isArray(summary) || summary.length === 0) {
    return publicSituationText({ status, summary, lang });
  }
  const headline = lang === 'fr'
    ? `${totals.total} anomalies au total, dont ${totals.open} encore ouvertes et ${totals.highOpen} prioritaires.`
    : `${totals.total} anomalies in total, including ${totals.open} still open and ${totals.highOpen} high priority.`;
  return `${headline} ${publicSituationText({ status, summary, lang })}`;
}

export function publicCountText(value, status, lang = 'fr') {
  if (status !== 'ready') return lang === 'fr' ? 'Indisponible' : 'Unavailable';
  const count = Number(value);
  return Number.isFinite(count) ? String(count) : '0';
}

export function publicSituationText({ status, summary = [], lang = 'fr' } = {}) {
  if (status !== 'ready') return lang === 'fr' ? 'Indisponible' : 'Unavailable';
  if (!Array.isArray(summary) || summary.length === 0) {
    return lang === 'fr' ? 'Aucun total public pour le moment.' : 'No public totals yet.';
  }
  const openLabel = lang === 'fr' ? 'ouverts' : 'open';
  const repairedLabel = lang === 'fr' ? 'réparés' : 'repaired';
  return summary.map((row) => {
    const code = row?.anomaly_type || '—';
    const band = row?.priority_band || '—';
    const openCount = Number(row?.open_count) || 0;
    const repairedCount = Number(row?.repaired_count) || 0;
    return `${code} · ${band} · ${openCount} ${openLabel} · ${repairedCount} ${repairedLabel}`;
  }).join(' · ');
}
