/** Shared observation identity and UTC time. Day keys are UTC, not local midnight. */

export function uniqueObservations(observations) {
  const seen = new Set();
  const rows = [];
  for (const obs of observations || []) {
    const id = obs?.id;
    if (id != null && id !== '') {
      if (seen.has(id)) continue;
      seen.add(id);
    }
    rows.push(obs);
  }
  return rows;
}

export function eventTimeMs(obs) {
  const raw = obs?.created_at || obs?.captured_at;
  if (!raw) return null;
  const time = new Date(raw).getTime();
  return Number.isFinite(time) ? time : null;
}

export function utcDayKey(timeMs) {
  if (!Number.isFinite(timeMs)) return null;
  return new Date(timeMs).toISOString().slice(0, 10);
}

export const OBSERVATION_PAGE_SIZE = 500;

export function mergeObservationPages(existing, next) {
  return uniqueObservations([...(existing || []), ...(next || [])]);
}
