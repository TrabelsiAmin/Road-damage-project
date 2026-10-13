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

const CLASS_SEVERITY_ORDER = { D40: 4, D20: 3, D00: 2, D10: 2 };

/**
 * Real distance-based spatial clustering (radius-based DBSCAN pass).
 * Replaces coordinate grid truncations with true metric clustering.
 *
 * @param {Array} observations - List of observation objects
 * @param {number} radiusMeters - Grouping radius in meters (default 20m)
 * @param {number} maxAccuracy - Skip points with GPS inaccuracy worse than this (default 25m)
 */
export function clusterObservations(observations, radiusMeters = 20, maxAccuracy = 25) {
  // 1. Filter out observations with poor GPS quality or zero coordinates
  const valid = observations.filter((obs) => {
    if (!obs.latitude || !obs.longitude) return false;
    if (obs.accuracy_meters && obs.accuracy_meters > maxAccuracy) return false;
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

    // Pick dominant class by safety hierarchy (D40 > D20 > D00/D10)
    let dominantClass = 'D40';
    let highestSeverity = -1;
    let maxPriorityScore = 0;

    members.forEach((m) => {
      const cls = m.anomaly_type || (m.detections?.[0]?.class_code) || 'D40';
      const order = CLASS_SEVERITY_ORDER[cls] || 1;
      if (order > highestSeverity) {
        highestSeverity = order;
        dominantClass = cls;
      }
      if ((m.priority_score || 0) > maxPriorityScore) {
        maxPriorityScore = m.priority_score;
      }
    });

    // Earliest and latest detection timestamps
    const dates = members.map((m) => new Date(m.created_at).getTime()).sort();
    const oldestDate = new Date(dates[0]);
    const newestDate = new Date(dates[dates.length - 1]);
    const ageDays = Math.round((Date.now() - oldestDate.getTime()) / (1000 * 60 * 60 * 24));

    // Best photo available in cluster
    const photo = members.find((m) => m.photo_url)?.photo_url || null;

    // Highest status priority in cluster
    const statusPriority = ['repaired', 'verified', 'scheduled', 'confirmed', 'unconfirmed', 'dismissed'];
    let dominantStatus = members[0].status || 'unconfirmed';
    for (const st of statusPriority) {
      if (members.some((m) => m.status === st)) {
        dominantStatus = st;
        break;
      }
    }

    clusters.push({
      id: `cluster-${root.id}`,
      latitude: avgLat,
      longitude: avgLng,
      count,
      dominantClass,
      maxPriorityScore: Math.round(maxPriorityScore),
      priorityLabel: maxPriorityScore >= 70 ? 'CRITICAL' : maxPriorityScore >= 40 ? 'HIGH' : maxPriorityScore >= 20 ? 'MEDIUM' : 'LOW',
      oldestDate: oldestDate.toISOString(),
      newestDate: newestDate.toISOString(),
      ageDays,
      status: dominantStatus,
      photoUrl: photo,
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
export function calculateRoadHealthScore(clusters) {
  if (!clusters || clusters.length === 0) return 100;

  let totalPenalty = 0;
  clusters.forEach((c) => {
    const weight = c.dominantClass === 'D40' ? 8 : c.dominantClass === 'D20' ? 5 : 2;
    totalPenalty += weight * Math.min(c.count, 3);
  });

  const rawScore = 100 - totalPenalty;
  return Math.max(12, Math.min(100, Math.round(rawScore)));
}
