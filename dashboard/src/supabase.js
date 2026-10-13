import { createClient } from '@supabase/supabase-js';

// Read from Vite environment or fall back to staging/default
const SUPABASE_URL =
  import.meta.env.VITE_SUPABASE_URL || 'https://lendqcjihusqkmxansbl.supabase.co';
const SUPABASE_ANON_KEY =
  import.meta.env.VITE_SUPABASE_ANON_KEY ||
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
 * Generates signed URL for private observation-images if user is authority.
 * For demo-images, returns direct public URL.
 */
export async function getMediaUrl(storagePath, bucket = 'observation-images', isDemo = false) {
  if (isDemo || bucket === 'demo-images') {
    const { data } = supabase.storage.from(bucket).getPublicUrl(storagePath);
    return data?.publicUrl;
  }
  try {
    const { data, error } = await supabase.storage
      .from('observation-images')
      .createSignedUrl(storagePath, 3600); // 1 hour token
    if (error || !data) return null;
    return data.signedUrl;
  } catch (_) {
    return null;
  }
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

    const mediaMap = new Map();
    (mediaData || []).forEach((m) => {
      if (!mediaMap.has(m.observation_id)) {
        mediaMap.set(m.observation_id, m);
      }
    });

    // Merge entities
    return obsData.map((obs) => {
      const loc = locMap.get(obs.id) || { latitude: 0, longitude: 0, accuracy_meters: null };
      const dets = detMap.get(obs.id) || [];
      const media = mediaMap.get(obs.id) || null;

      return {
        ...obs,
        latitude: Number(loc.latitude) || 0,
        longitude: Number(loc.longitude) || 0,
        accuracy_meters: loc.accuracy_meters,
        detections: dets,
        photo_url: media?.public_url || null,
        storage_path: media?.storage_path || null,
        bucket: media?.bucket || 'observation-images',
      };
    }).filter((o) => o.latitude !== 0 && o.longitude !== 0);
  } catch (err) {
    console.error('[Supabase] fetchObservations failed:', err);
    throw err;
  }
}

/**
 * Updates status of an observation (requires authenticated authority operator).
 */
export async function updateObservationStatus(id, newStatus) {
  const { data, error } = await supabase
    .from('observations')
    .update({ status: newStatus })
    .eq('id', id)
    .select();

  if (error) throw error;
  return data;
}
