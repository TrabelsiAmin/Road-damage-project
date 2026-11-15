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

/** Safety stop for a catalogue that keeps growing. Not a displayed total. */
export const OBSERVATION_PAGE_LIMIT = 40;

export function mergeObservationPages(existing, next) {
  return uniqueObservations([...(existing || []), ...(next || [])]);
}

/**
 * A measured point. Missing coordinates and the 0,0 placeholder stay null
 * so a report is still counted and is not drawn at Null Island.
 */
export function observationCoordinates(latitude, longitude) {
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return { latitude: null, longitude: null };
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return { latitude: null, longitude: null };
  if (lat === 0 && lng === 0) return { latitude: null, longitude: null };
  return { latitude: lat, longitude: lng };
}

/**
 * Joins one observation page to its children.
 * A report with no location, detection, or photo stays in the catalogue.
 */
export function assembleObservationRows(obsData = [], locData = [], detData = [], mediaData = []) {
  const locMap = new Map();
  (locData || []).forEach((row) => locMap.set(row.observation_id, row));

  const detMap = new Map();
  (detData || []).forEach((row) => {
    const list = detMap.get(row.observation_id) || [];
    list.push(row);
    detMap.set(row.observation_id, list);
  });

  const originalMap = new Map();
  const thumbMap = new Map();
  (mediaData || []).forEach((row) => {
    if (row.bucket === 'observation-images') originalMap.set(row.observation_id, row);
    else if (row.bucket === 'public-photos') thumbMap.set(row.observation_id, row);
  });

  return (obsData || []).map((obs) => {
    const loc = locMap.get(obs.id) || null;
    const point = observationCoordinates(loc?.latitude, loc?.longitude);
    const original = originalMap.get(obs.id) || null;
    const thumb = thumbMap.get(obs.id) || null;
    return {
      ...obs,
      latitude: point.latitude,
      longitude: point.longitude,
      accuracy_meters: loc?.accuracy_meters ?? null,
      detections: detMap.get(obs.id) || [],
      original_media: original,
      thumbnail_media: thumb,
      storage_path: original?.storage_path || thumb?.storage_path || null,
      bucket: original?.bucket || thumb?.bucket || 'observation-images',
    };
  });
}
