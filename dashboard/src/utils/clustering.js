import { calculatePriorityScore, PRIORITY_CONFIG } from './priorityScoring.js';

/**
 * Geospatial distance calculation using spherical Haversine formula.
 * Returns distance in meters between two lat/lng coordinates.
 */
export function haversineDistanceMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Earth radius in meters
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

const CLASS_SEVERITY_ORDER = { D40: 4, D20: 3, D10: 2, D00: 1 };

/**
 * Test & Reference Helper: Metric spatial clustering (radius-based DBSCAN pass matching PostGIS ST_ClusterDBSCAN).
 * Production single source of truth is the Supabase RPC public.get_clusters().
 * This client function is retained as a test helper and algorithmic reference.
 *
 * @param {Array} observations - List of observation objects
 * @param {number} radiusMeters - Grouping radius in meters (default 20m)
 * @param {number} maxAccuracy - Skip points with GPS inaccuracy worse than this (default 25m)
 */
export function clusterObservations(observations = [], radiusMeters = 20, maxAccuracy = 25) {
  // 1. Filter out observations with poor GPS quality, zero coordinates, or status 'rejected'
  const valid = observations.filter((obs) => {
    if (!obs || typeof obs.latitude !== 'number' || typeof obs.longitude !== 'number') return false;
    if (obs.latitude === 0 && obs.longitude === 0) return false;
    if (typeof obs.accuracy_meters === 'number' && obs.accuracy_meters > maxAccuracy) return false;
    if (obs.status === 'rejected') return false;
    return true;
  });

  const visited = new Set();
  const clusters = [];

  for (let i = 0; i < valid.length; i++) {
    const root = valid[i];
    if (visited.has(root.id)) continue;

    visited.add(root.id);
    const members = [root];

    // Find all neighbors within radiusMeters
    for (let j = i + 1; j < valid.length; j++) {
      const candidate = valid[j];
      if (visited.has(candidate.id)) continue;

      const dist = haversineDistanceMeters(
        root.latitude,
        root.longitude,
        candidate.latitude,
        candidate.longitude
      );

      if (dist <= radiusMeters) {
        visited.add(candidate.id);
        members.push(candidate);
      }
    }

    // Aggregate cluster properties
    const count = members.length;
    const avgLat = members.reduce((sum, m) => sum + m.latitude, 0) / count;
    const avgLng = members.reduce((sum, m) => sum + m.longitude, 0) / count;

    // Pick dominant class by safety hierarchy (D40 > D20 > D10 > D00)
    let dominantClass = 'D40';
    let highestSeverity = -1;
    let maxPriorityScore = 0;

    members.forEach((m) => {
      // Recompute priority score via Priority Scoring v2 if detections present
      let score = m.priority_score;
      if (typeof score !== 'number' || isNaN(score)) {
        if (m.detections && m.detections.length > 0) {
          score = calculatePriorityScore(m.detections).score;
          m.priority_score = score;
        } else {
          score = 0;
        }
      }

      const cls = m.anomaly_type || m.detections?.[0]?.class_code || 'D40';
      const order = CLASS_SEVERITY_ORDER[cls] || 1;
      if (order > highestSeverity) {
        highestSeverity = order;
        dominantClass = cls;
      }
      if (score > maxPriorityScore) {
        maxPriorityScore = score;
      }
    });

    // Priority label based on Priority Scoring v2 tunable thresholds
    const priorityLabel =
      maxPriorityScore > PRIORITY_CONFIG.highThreshold
        ? 'HIGH'
        : maxPriorityScore < PRIORITY_CONFIG.lowThreshold
        ? 'LOW'
        : 'MEDIUM';

    // Status counts in cluster
    const statusCounts = {
      unconfirmed: members.filter((m) => m.status === 'unconfirmed').length,
      confirmed: members.filter((m) => m.status === 'confirmed').length,
      repaired: members.filter((m) => m.status === 'repaired').length,
    };

    // Dominant status hierarchy: repaired > confirmed > unconfirmed
    let dominantStatus = 'unconfirmed';
    if (statusCounts.repaired > 0 && statusCounts.repaired === count) {
      dominantStatus = 'repaired';
    } else if (statusCounts.confirmed > 0) {
      dominantStatus = 'confirmed';
    } else if (statusCounts.repaired > 0) {
      dominantStatus = 'repaired';
    }

    // Earliest and latest detection timestamps
    const dates = members
      .map((m) => new Date(m.created_at || Date.now()).getTime())
      .filter((t) => !isNaN(t))
      .sort((a, b) => a - b);

    const oldestDate = dates.length > 0 ? new Date(dates[0]) : new Date();
    const newestDate = dates.length > 0 ? new Date(dates[dates.length - 1]) : new Date();

    // Best photo available in cluster (storage_path for authenticated signed url generation)
    const storageMember = members.find((m) => m.storage_path);
    const storagePath = storageMember?.storage_path || null;
    const bucket = storageMember?.bucket || 'observation-images';

    clusters.push({
      id: `cluster-${root.id}`,
      latitude: avgLat,
      longitude: avgLng,
      count,
      dominantClass,
      maxPriorityScore: Math.round(maxPriorityScore * 100) / 100,
      priorityLabel,
      oldestDate: oldestDate.toISOString(),
      newestDate: newestDate.toISOString(),
      status: dominantStatus,
      statusCounts,
      storagePath,
      bucket,
      members,
    });
  }

  // Sort clusters descending by priority score and sightings
  return clusters.sort((a, b) => b.maxPriorityScore - a.maxPriorityScore || b.count - a.count);
}

/**
 * Calculates Road Health Index (0-100) for a given area.
 * 100 = Perfect condition. D40/D20 penalize heavily.
 */
export function calculateRoadHealthScore(clusters = []) {
  if (!clusters || clusters.length === 0) return 100;

  let totalPenalty = 0;
  clusters.forEach((c) => {
    const weight = c.dominantClass === 'D40' ? 8 : c.dominantClass === 'D20' ? 5 : 2;
    totalPenalty += weight * Math.min(c.count, 3);
  });

  const rawScore = 100 - totalPenalty;
  return Math.max(12, Math.min(100, Math.round(rawScore)));
}
