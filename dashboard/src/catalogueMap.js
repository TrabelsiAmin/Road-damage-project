import { supabase, fetchPublicDamageSummary, fetchPublicMapCells } from './supabase';
import { classifyPublicError, publicRequestError } from './utils/publicStats';
import { aggregatePublicMapCells } from './utils/publicMapCells';

const PAGE_SIZE = 500;
const PAGE_LIMIT = 40;

/**
 * Reads the catalogue the anon key can already see and returns only cell centers.
 * Used when public_map_cells is missing. Row ids and measured points are not returned.
 */
export async function fetchCatalogueMapCells(cellDegrees = 0.01) {
  const [observations, locations] = await Promise.all([
    fetchPages('observations', 'id, status, is_demo, anomaly_type'),
    fetchPages('locations', 'observation_id, latitude, longitude'),
  ]);
  const byObservation = new Map();
  locations.forEach((row) => {
    if (row?.observation_id) byObservation.set(row.observation_id, row);
  });
  const points = observations.map((row) => {
    const place = byObservation.get(row.id);
    return {
      status: row.status,
      is_demo: row.is_demo,
      anomaly_type: row.anomaly_type,
      latitude: place?.latitude,
      longitude: place?.longitude,
    };
  });
  return aggregatePublicMapCells(points, cellDegrees);
}

async function fetchPages(table, columns) {
  const rows = [];
  for (let page = 0; page < PAGE_LIMIT; page += 1) {
    const from = page * PAGE_SIZE;
    const { data, error } = await supabase
      .from(table)
      .select(columns)
      .range(from, from + PAGE_SIZE - 1);
    if (error) {
      throw publicRequestError(error, 'La carte publique n\'est pas disponible.');
    }
    const batch = data || [];
    rows.push(...batch);
    if (batch.length < PAGE_SIZE) return rows;
  }
  return rows;
}

/**
 * Official public cells when the function exists.
 * A missing function falls back to the coarse visible catalogue, never to invented points.
 * The official total stays unavailable when public_damage_summary is missing.
 */
export async function loadVisitorPublicMap() {
  let summary = [];
  let summaryStatus = 'ready';
  try {
    summary = (await fetchPublicDamageSummary()) || [];
  } catch {
    summary = [];
    summaryStatus = 'unavailable';
  }

  try {
    const cells = (await fetchPublicMapCells(0.01)) || [];
    return { summary, summaryStatus, cells, cellSource: 'rpc', failure: null };
  } catch (error) {
    const failure = error?.publicFailure || classifyPublicError(error);
    if (failure !== 'http_404') {
      return { summary, summaryStatus, cells: [], cellSource: 'unavailable', failure };
    }
    try {
      const cells = await fetchCatalogueMapCells(0.01);
      return { summary, summaryStatus, cells, cellSource: 'catalogue', failure: null };
    } catch {
      return { summary, summaryStatus, cells: [], cellSource: 'unavailable', failure: 'http_404' };
    }
  }
}
