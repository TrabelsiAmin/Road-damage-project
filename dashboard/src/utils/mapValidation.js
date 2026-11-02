/**
 * Coordinate and cluster validation utilities for the Leaflet GIS map.
 * Ensures strictly valid, finite, and non-zero coordinates before passing to Leaflet APIs.
 */

/**
 * Validates whether latitude and longitude are finite numbers, within standard WGS84 bounds,
 * not null/undefined/empty, and not the uninitialized coordinate origin (0, 0 / Null Island).
 *
 * @param {number|string|null|undefined} lat
 * @param {number|string|null|undefined} lng
 * @returns {boolean} True if coordinates are valid for rendering on the map
 */
export function isValidLatLng(lat, lng) {
  if (lat === null || lat === undefined || lng === null || lng === undefined) {
    return false;
  }
  if (typeof lat === 'string' && lat.trim() === '') return false;
  if (typeof lng === 'string' && lng.trim() === '') return false;

  const nLat = Number(lat);
  const nLng = Number(lng);

  return (
    Number.isFinite(nLat) &&
    Number.isFinite(nLng) &&
    nLat >= -90 &&
    nLat <= 90 &&
    nLng >= -180 &&
    nLng <= 180 &&
    !(nLat === 0 && nLng === 0)
  );
}

/**
 * Filters a collection of clusters or observations, returning only those with valid coordinates.
 *
 * @param {Array<object>} clusters
 * @returns {Array<object>} Filtered array with valid latitude and longitude
 */
export function filterValidClusters(clusters) {
  if (!Array.isArray(clusters)) return [];
  return clusters.filter((cluster) => isValidLatLng(cluster?.latitude, cluster?.longitude));
}
