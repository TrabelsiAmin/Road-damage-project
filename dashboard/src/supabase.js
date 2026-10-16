import { createClient } from '@supabase/supabase-js';

// Read from Vite environment or fall back to staging/default
const SUPABASE_URL =
  import.meta.env?.VITE_SUPABASE_URL || 'https://lendqcjihusqkmxansbl.supabase.co';
const SUPABASE_ANON_KEY =
  import.meta.env?.VITE_SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxlbmRxY2ppaHVzcWtteGFuc2JsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyODA3ODYsImV4cCI6MjEwNTg1Njc4Nn0.F1FS2HZNf7qEbTx14WBSAOHeCWTGsA5OMZghgw_YNNs';

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
export async function fetchObservations() {
  try {
    // 1. Fetch observations (device_id is omitted to comply with anon column privilege)
    const { data: obsData, error: obsErr } = await supabase
      .from('observations')
      .select('id, capture_id, anomaly_type, priority_score, priority_label, status, is_demo, created_at, organization_id')
      .order('created_at', { ascending: false })
      .limit(500);

    if (obsErr) throw obsErr;
    if (!obsData || obsData.length === 0) return [];

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

    // Merge entities
    return obsData.map((obs) => {
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

