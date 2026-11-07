import { createClient } from '@supabase/supabase-js';
import { OBSERVATION_PAGE_SIZE } from './utils/records';

// Public anon key only. A production Vite build does not use the debug
// fallback. `vite` and vitest still do, so a local run without env starts.
// No service-role key is read or logged here. Env vars do not replace RLS.
// import.meta.env.DEV is folded to false in `vite build`, so these strings
// are not part of the production bundle. Local `vite` and vitest still see them.
const DEBUG_SUPABASE_URL = import.meta.env.DEV
  ? 'https://lendqcjihusqkmxansbl.supabase.co'
  : '';
const DEBUG_SUPABASE_ANON_KEY = import.meta.env.DEV
  ? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxlbmRxY2ppaHVzcWtteGFuc2JsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyODA3ODYsImV4cCI6MjEwNTg1Njc4Nn0.F1FS2HZNf7qEbTx14WBSAOHeCWTGsA5OMZghgw_YNNs'
  : '';

export function resolvePublicConfig({ url, key, production }) {
  const projectUrl = String(url || '').trim();
  const anon = String(key || '').trim();
  return {
    url: projectUrl || (production ? '' : DEBUG_SUPABASE_URL),
    key: anon || (production ? '' : DEBUG_SUPABASE_ANON_KEY),
  };
}

const productionBuild = Boolean(import.meta.env?.PROD) && import.meta.env?.MODE !== 'test';
const resolvedConfig = resolvePublicConfig({
  url: import.meta.env?.VITE_SUPABASE_URL,
  key: import.meta.env?.VITE_SUPABASE_ANON_KEY,
  production: productionBuild,
});
const SUPABASE_URL = resolvedConfig.url;
const SUPABASE_ANON_KEY = resolvedConfig.key;

function jwtRole(token) {
  try {
    const part = String(token).split('.')[1];
    if (!part) return null;
    const padded = part.replace(/-/g, '+').replace(/_/g, '/');
    const pad = padded.length % 4 === 0 ? padded : padded + '='.repeat(4 - (padded.length % 4));
    const decoded = typeof atob === 'function'
      ? atob(pad)
      : Buffer.from(pad, 'base64').toString('utf8');
    const role = JSON.parse(decoded).role;
    return typeof role === 'string' ? role : null;
  } catch {
    return null;
  }
}

/**
 * Startup check for the public client. Empty config and a service-role key
 * stop the dashboard. The key itself is never included in the error.
 */
export function assertPublicSupabaseConfig(url, key) {
  const projectUrl = String(url || '').trim();
  const anon = String(key || '').trim();
  if (!projectUrl.startsWith('https://')) {
    throw new Error('Supabase URL is missing. Set VITE_SUPABASE_URL. The value is not logged.');
  }
  if (anon.length < 20) {
    throw new Error('Supabase anon key is missing. Set VITE_SUPABASE_ANON_KEY. The value is not logged.');
  }
  if (jwtRole(anon) === 'service_role') {
    throw new Error('Refusing to start: the dashboard must not use a service-role key.');
  }
}

assertPublicSupabaseConfig(SUPABASE_URL, SUPABASE_ANON_KEY);

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

/**
 * Authentication helpers
 */
export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function getCurrentUser() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

export async function checkIsAuthority() {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return false;
    const { data, error } = await supabase.rpc('is_authority');
    if (error) {
      // Fallback: query authority_users table
      const { data: rows } = await supabase
        .from('authority_users')
        .select('user_id')
        .eq('user_id', user.id);
      return Boolean(rows && rows.length > 0);
    }
    return Boolean(data);
  } catch (_) {
    return false;
  }
}

/**
 * Generates signed URL for private observation-images bucket (10-minute expiry: 600s).
 * Strictly uses createSignedUrl for observation-images.
 * Returns { signedUrl, expiresAt }.
 */
export async function getSignedMediaUrl(storagePath, bucket = 'observation-images', expiresInSeconds = 600) {
  if (!storagePath) throw new Error('storagePath is required');
  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(storagePath, expiresInSeconds);

  if (error || !data?.signedUrl) {
    throw error || new Error('Failed to create signed URL from storage');
  }

  return {
    signedUrl: data.signedUrl,
    expiresAt: Date.now() + (expiresInSeconds - 30) * 1000, // Refresh 30s before expiry
  };
}

/**
 * Returns public URL for public-photos or demo-images.
 */
export function getPublicMediaUrl(storagePath, bucket = 'public-photos') {
  if (!storagePath) return null;
  const { data } = supabase.storage.from(bucket).getPublicUrl(storagePath);
  return data?.publicUrl || null;
}

/**
 * Backwards-compatible getMediaUrl.
 */
export async function getMediaUrl(storagePath, bucket = 'observation-images', isDemo = false) {
  if (!storagePath) return null;
  if (bucket === 'demo-images' || bucket === 'public-photos') {
    return getPublicMediaUrl(storagePath, bucket);
  }
  try {
    const res = await getSignedMediaUrl(storagePath, bucket, 600);
    return res.signedUrl;
  } catch (err) {
    console.warn('[Supabase] getMediaUrl failed:', err);
    return null;
  }
}

/**
 * Fetches fresh media_files rows for a specific set of observation IDs.
 * Used whenever a cluster is opened or auth session state changes.
 */
export async function fetchMediaFilesForObservations(obsIds) {
  if (!obsIds || obsIds.length === 0) return {};
  try {
    const { data, error } = await supabase
      .from('media_files')
      .select('id, observation_id, bucket, storage_path, media_type, is_demo, public_url')
      .in('observation_id', obsIds);

    if (error) {
      console.warn('[Supabase] fetchMediaFilesForObservations failed:', error.message);
      return {};
    }

    const result = {};
    obsIds.forEach((id) => {
      result[id] = { original: null, thumbnail: null };
    });

    (data || []).forEach((row) => {
      if (!result[row.observation_id]) {
        result[row.observation_id] = { original: null, thumbnail: null };
      }
      if (row.bucket === 'observation-images' && (row.media_type === 'image' || row.media_type === 'frame')) {
        result[row.observation_id].original = row;
      } else if (row.bucket === 'public-photos' || row.media_type === 'thumbnail') {
        result[row.observation_id].thumbnail = row;
      } else {
        result[row.observation_id].original = row;
      }
    });

    return result;
  } catch (err) {
    console.warn('[Supabase] fetchMediaFilesForObservations error:', err);
    return {};
  }
}

/**
 * Fetches server-calculated clusters via public.get_clusters() RPC.
 * Server is the single source of truth (DBSCAN 20m, accuracy <= 25m, status <> 'rejected').
 */
export async function fetchServerClusters(epsMeters = 20, minPoints = 1) {
  const { data, error } = await supabase.rpc('get_clusters', {
    eps_meters: epsMeters,
    min_points: minPoints,
  });

  if (error) {
    console.error('[Supabase] get_clusters RPC failed:', error);
    throw error;
  }

  return data || [];
}

/**
 * Loads observations with locations, detections, and media files.
 */
export async function fetchObservations({ before = null, limit = OBSERVATION_PAGE_SIZE } = {}) {
  try {
    // 1. Fetch observations (device_id is omitted to comply with anon column privilege)
    const pageSize = Math.min(Math.max(Number(limit) || OBSERVATION_PAGE_SIZE, 1), OBSERVATION_PAGE_SIZE);
    let query = supabase
      .from('observations')
      .select('id, capture_id, anomaly_type, priority_score, priority_label, status, is_demo, created_at, organization_id')
      .order('created_at', { ascending: false })
      .limit(pageSize);
    if (before) query = query.lt('created_at', before);
    const { data: obsData, error: obsErr } = await query;

    if (obsErr) throw obsErr;
    if (!obsData || obsData.length === 0) return { rows: [], truncated: false };

    const obsIds = obsData.map((o) => o.id);

    // 2. Fetch locations
    const { data: locData } = await supabase
      .from('locations')
      .select('observation_id, latitude, longitude, accuracy_meters')
      .in('observation_id', obsIds);

    // 3. Fetch detections
    const { data: detData } = await supabase
      .from('detections')
      .select('observation_id, class_code, confidence, box_x, box_y, box_w, box_h')
      .in('observation_id', obsIds);

    // 4. Fetch media files
    const { data: mediaData } = await supabase
      .from('media_files')
      .select('observation_id, public_url, storage_path, bucket, is_demo, media_type')
      .in('observation_id', obsIds);

    const locMap = new Map();
    (locData || []).forEach((l) => locMap.set(l.observation_id, l));

    const detMap = new Map();
    (detData || []).forEach((d) => {
      const arr = detMap.get(d.observation_id) || [];
      arr.push(d);
      detMap.set(d.observation_id, arr);
    });

    const mediaOriginalMap = new Map();
    const mediaThumbMap = new Map();
    (mediaData || []).forEach((m) => {
      if (m.bucket === 'observation-images') {
        mediaOriginalMap.set(m.observation_id, m);
      } else if (m.bucket === 'public-photos') {
        mediaThumbMap.set(m.observation_id, m);
      }
    });

    const truncated = obsData.length === pageSize;
    // Merge entities
    const rows = obsData.map((obs) => {
      const loc = locMap.get(obs.id) || { latitude: 0, longitude: 0, accuracy_meters: null };
      const dets = detMap.get(obs.id) || [];
      const orig = mediaOriginalMap.get(obs.id) || null;
      const thumb = mediaThumbMap.get(obs.id) || null;

      return {
        ...obs,
        latitude: Number(loc.latitude) || 0,
        longitude: Number(loc.longitude) || 0,
        accuracy_meters: loc.accuracy_meters,
        detections: dets,
        original_media: orig,
        thumbnail_media: thumb,
        storage_path: orig?.storage_path || thumb?.storage_path || null,
        bucket: orig?.bucket || thumb?.bucket || 'observation-images',
      };
    }).filter((o) => o.latitude !== 0 && o.longitude !== 0);
    return { rows, truncated };
  } catch (err) {
    console.error('[Supabase] fetchObservations failed:', err);
    throw err;
  }
}

/**
 * Updates status of a single observation (requires authenticated authority operator).
 * Strictly verifies that exactly 1 row was updated under RLS.
 */
export async function updateObservationStatus(id, newStatus) {
  const { data, error } = await supabase
    .from('observations')
    .update({ status: newStatus })
    .eq('id', id)
    .select('id, status');

  if (error) throw error;
  if (!data || data.length !== 1) {
    throw new Error('Échec de la mise à jour (0 ligne modifiée). Vérifiez les permissions RLS d\'autorité.');
  }
  return data[0];
}

/**
 * Updates status of multiple observations in a single query with id=in.(...).
 * Strictly verifies that the returned row count matches the requested IDs count.
 */
export async function updateMultipleObservationsStatus(ids, newStatus) {
  if (!ids || ids.length === 0) return [];
  const { data, error } = await supabase
    .from('observations')
    .update({ status: newStatus })
    .in('id', ids)
    .select('id, status');

  if (error) throw error;
  if (!data || data.length !== ids.length) {
    throw new Error(`Échec de la mise à jour par lot : ${data?.length || 0}/${ids.length} lignes modifiées.`);
  }
  return data;
}



/**
 * Loads maintenance cases metadata (contractor assignment, due dates, repair notes, verification).
 * Returns Map of observation_id -> maintenance_case row.
 */
export async function fetchMaintenanceCases() {
  try {
    const { data, error } = await supabase
      .from('maintenance_cases')
      .select('*')
      .limit(1000);

    if (error) {
      console.warn('[Supabase] maintenance_cases table query warning (fallback active):', error.message);
      return {};
    }

    const map = {};
    (data || []).forEach((row) => {
      if (row.observation_id) map[row.observation_id] = row;
    });
    return map;
  } catch (err) {
    console.warn('[Supabase] fetchMaintenanceCases error:', err);
    return {};
  }
}

/**
 * Updates or creates a maintenance case.
 */
export async function updateMaintenanceCase(payload) {
  const { observationId, ...fields } = payload;
  if (!observationId) throw new Error('observationId is required');

  try {
    const { data, error } = await supabase
      .from('maintenance_cases')
      .upsert({
        observation_id: observationId,
        case_number: payload.caseNumber || `CASE-${new Date().getFullYear()}-${observationId.slice(0, 6)}`,
        updated_at: new Date().toISOString(),
        ...fields,
      }, { onConflict: 'observation_id' })
      .select('*');

    if (error) {
      console.warn('[Supabase] updateMaintenanceCase warning:', error.message);
      return { observation_id: observationId, ...fields };
    }
    return data?.[0] || { observation_id: observationId, ...fields };
  } catch (err) {
    console.warn('[Supabase] updateMaintenanceCase error:', err);
    return { observation_id: observationId, ...fields };
  }
}

/**
 * Fetches chronological audit trail events.
 */
export async function fetchMaintenanceEvents(limit = 100) {
  try {
    const { data, error } = await supabase
      .from('maintenance_events')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) {
      console.warn('[Supabase] maintenance_events table query warning:', error.message);
      return [];
    }
    return data || [];
  } catch (err) {
    console.warn('[Supabase] fetchMaintenanceEvents error:', err);
    return [];
  }
}

/**
 * Records an auditable maintenance action event.
 */
export async function recordMaintenanceEvent({
  observationId,
  action,
  previousValue = null,
  newValue = null,
  notes = null,
}) {
  try {
    const user = await getCurrentUser();
    const { data, error } = await supabase
      .from('maintenance_events')
      .insert({
        observation_id: observationId,
        user_id: user?.id || null,
        actor_email: user?.email || 'Autorité Voirie',
        action,
        previous_value: previousValue ? String(previousValue) : null,
        new_value: newValue ? String(newValue) : null,
        notes,
      })
      .select();

    if (error) {
      console.warn('[Supabase] recordMaintenanceEvent warning:', error.message);
    }
    return data?.[0] || null;
  } catch (err) {
    console.warn('[Supabase] recordMaintenanceEvent error:', err);
    return null;
  }
}

/**
 * Fetches server-calculated road segments risk via PostGIS RPC get_road_segment_risk.
 */
export async function fetchRoadSegmentsRisk(minRiskLevel = 'ALL') {
  try {
    const { data, error } = await supabase.rpc('get_road_segment_risk', {
      min_risk_level: minRiskLevel,
    });

    if (error) {
      console.warn('[Supabase] get_road_segment_risk RPC warning (will use client calculation):', error.message);
      return null;
    }
    return data || [];
  } catch (err) {
    console.warn('[Supabase] fetchRoadSegmentsRisk error:', err);
    return null;
  }
}

/**
 * Subscribes to Realtime updates on observations and maintenance_cases.
 */
export function subscribeToCommandCenterUpdates(onUpdate) {
  if (!onUpdate) return () => {};

  let debounceTimer = null;
  const triggerDebounced = (payload) => {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      onUpdate(payload);
    }, 400);
  };

  const channel = supabase
    .channel('command-center-realtime')
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'observations' },
      triggerDebounced
    )
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'maintenance_cases' },
      triggerDebounced
    )
    .subscribe();

  return () => {
    if (debounceTimer) clearTimeout(debounceTimer);
    supabase.removeChannel(channel);
  };
}
