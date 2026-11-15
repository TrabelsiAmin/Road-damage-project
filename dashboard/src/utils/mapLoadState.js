/**
 * A failed load and an empty result are different map states.
 */

export function mapLoadState({ loading = false, error = null, markerCount = 0 } = {}) {
  if (error) return 'error';
  if (loading && markerCount === 0) return 'loading';
  if (markerCount === 0) return 'empty';
  return 'ready';
}

export function mapLoadCopy(state, lang = 'fr', reason = null) {
  const french = lang !== 'en';
  if (state === 'error' && reason === 'http_404') {
    return french
      ? 'Les totaux publics sont indisponibles (HTTP 404). Ce n’est pas un total de zéro incident.'
      : 'Public totals are unavailable (HTTP 404). This is not a total of zero incidents.';
  }
  if (state === 'error') {
    return french
      ? 'La carte n’a pas pu être chargée. Ce message signale une erreur technique, pas une absence d’anomalies.'
      : 'The map could not be loaded. This is a technical error, not an absence of anomalies.';
  }
  if (state === 'empty' && reason === 'catalogue') {
    return french
      ? 'Aucune maille dans le catalogue visible. Le total public officiel est indisponible (HTTP 404).'
      : 'No cell in the visible catalogue. The official public total is unavailable (HTTP 404).';
  }
  if (state === 'empty') {
    return french
      ? 'Aucune anomalie géolocalisée dans les filtres sélectionnés.'
      : 'No geolocated anomalies match the selected filters.';
  }
  if (state === 'loading') {
    return french ? 'Chargement de la carte…' : 'Loading map…';
  }
  return '';
}
