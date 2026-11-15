/**
 * Public totals are real only after both aggregate functions succeed.
 * A missing function or an error is unavailable, never a count of zero.
 */

export function canDownloadPublicExport(status) {
  return status === 'ready';
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
