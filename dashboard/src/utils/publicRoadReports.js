/**
 * Cited public road reports stay outside the catalogue class counts and the map cells.
 * Each stored record can be added once to the incident total.
 * A marker exists only for a labeled approximate centroid or for coordinates
 * the source itself published.
 */

const HTTP_URL = /^https?:\/\/\S+$/i;
const CLASS_CODE = /\bD(?:00|10|20|40)\b/;
const TUNISIA_BOX = { minLat: 30, maxLat: 38.5, minLng: 7, maxLng: 12.5 };

export const PUBLIC_REPORT_ZOOM = 12;

function text(value) {
  const cleaned = String(value ?? '').replace(/\s+/g, ' ').trim();
  return cleaned.length > 0 ? cleaned : '';
}

function localized(value, lang) {
  if (value && typeof value === 'object') {
    return text(lang === 'en' ? value.en : value.fr);
  }
  return text(value);
}

function httpUrl(value) {
  const cleaned = text(value);
  return HTTP_URL.test(cleaned) ? cleaned : '';
}

function finite(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function insideTunisia(lat, lng) {
  return lat >= TUNISIA_BOX.minLat
    && lat <= TUNISIA_BOX.maxLat
    && lng >= TUNISIA_BOX.minLng
    && lng <= TUNISIA_BOX.maxLng;
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function reportBlob(report) {
  const sources = Array.isArray(report?.sources) ? report.sources : [];
  const locations = Array.isArray(report?.locations) ? report.locations : [];
  return [
    report?.title,
    report?.place,
    report?.quote,
    report?.dateLabel,
    localized(report?.dateNote, 'fr'),
    localized(report?.dateNote, 'en'),
    localized(report?.publicNote, 'fr'),
    localized(report?.publicNote, 'en'),
    localized(report?.unmappedNote, 'fr'),
    localized(report?.placementExtra, 'fr'),
    ...sources.map((source) => `${source?.name || ''} ${source?.url || ''}`),
    ...locations.map((location) => [
      location?.place,
      location?.precision,
      localized(location?.positionLabel, 'fr'),
      localized(location?.positionLabel, 'en'),
      location?.geocoderUrl,
    ].join(' ')),
  ].join('\n');
}

export function isCitedPublicReport(report) {
  if (!report || typeof report !== 'object') return false;
  if (!text(report.id) || !text(report.title) || !text(report.place) || !text(report.quote)) return false;
  const note = localized(report.publicNote, 'fr');
  if (!note.includes('pas une capture TariqMap')) return false;
  const sources = Array.isArray(report.sources) ? report.sources : [];
  if (sources.length === 0) return false;
  if (sources.some((source) => !text(source?.name) || !httpUrl(source?.url))) return false;
  if (report.classCode != null && text(report.classCode)) return false;
  if (CLASS_CODE.test(reportBlob(report))) return false;
  return true;
}

/**
 * One stored report record, even when the article names several streets
 * or carries several approximate locations.
 */
export function storedPublicReportCount(reports) {
  const seen = new Set();
  for (const report of Array.isArray(reports) ? reports : []) {
    if (!isCitedPublicReport(report)) continue;
    const id = text(report.id);
    if (id) seen.add(id);
  }
  return seen.size;
}

/**
 * Honest catalogue count plus cited public reports.
 * A missing catalogue count stays missing. Extra locations do not add incidents.
 */
export function sumIncidentTotal(catalogueCount, publicReportCount) {
  if (catalogueCount == null || catalogueCount === '') return null;
  const catalogue = Number(catalogueCount);
  const reports = Number(publicReportCount);
  if (!Number.isFinite(catalogue) || catalogue < 0) return null;
  const extra = Number.isFinite(reports) && reports > 0 ? Math.trunc(reports) : 0;
  return catalogue + extra;
}

export function incidentTotalBreakdown(catalogueCount, publicReportCount, lang = 'fr') {
  const total = sumIncidentTotal(catalogueCount, publicReportCount);
  const reports = Number(publicReportCount);
  if (total == null || !Number.isFinite(reports) || reports < 0) return null;
  const catalogue = Number(catalogueCount);
  const publicCount = Math.trunc(reports);
  if (lang === 'en') {
    const signalWord = catalogue === 1 ? 'TariqMap report' : 'TariqMap reports';
    const publicWord = publicCount === 1 ? 'public report' : 'public reports';
    return `${catalogue} ${signalWord} + ${publicCount} ${publicWord}`;
  }
  const signalWord = catalogue === 1 ? 'signalement TariqMap' : 'signalements TariqMap';
  const publicWord = publicCount === 1 ? 'rapport public' : 'rapports publics';
  return `${catalogue} ${signalWord} + ${publicCount} ${publicWord}`;
}

function acceptedLocation(report, location) {
  if (!location || typeof location !== 'object') return null;
  const place = text(location.place);
  const lat = finite(location.lat);
  const lng = finite(location.lng);
  if (!place || lat == null || lng == null || !insideTunisia(lat, lng)) return null;
  const precision = location.precision;
  const labelFr = localized(location.positionLabel, 'fr');
  const labelEn = localized(location.positionLabel, 'en');
  if (!/approximat/i.test(labelFr) || !/approximate/i.test(labelEn)) return null;
  if (precision === 'approximate-centroid') {
    if (!httpUrl(location.geocoderUrl) || !text(location.geocoderName)) return null;
  } else if (precision === 'source-coordinates') {
    if (report.coordinatesFromSource !== true) return null;
  } else {
    return null;
  }
  return {
    id: text(location.id) || place,
    place,
    lat,
    lng,
    precision,
    positionLabel: { fr: labelFr, en: labelEn },
    geocoderName: text(location.geocoderName),
    geocoderUrl: httpUrl(location.geocoderUrl),
  };
}

export function publicReportMapMarkers(reports, lang = 'fr') {
  return (Array.isArray(reports) ? reports : []).filter(isCitedPublicReport).flatMap((report) => {
    const locations = Array.isArray(report.locations) ? report.locations : [];
    return locations.map((location) => acceptedLocation(report, location)).filter(Boolean).map((location) => ({
      id: `${report.id}:${location.id}`,
      reportId: report.id,
      title: text(report.title),
      place: location.place,
      lat: location.lat,
      lng: location.lng,
      precision: location.precision,
      positionLabel: localized(location.positionLabel, lang),
      positionLabelFr: location.positionLabel.fr,
      positionLabelEn: location.positionLabel.en,
      geocoderName: location.geocoderName,
      geocoderUrl: location.geocoderUrl,
      quote: text(report.quote),
      dateLabel: text(report.dateLabel) || null,
      publicNote: localized(report.publicNote, lang),
      sourceName: text(report.sources[0].name),
      url: report.sources[0].url,
      sources: report.sources.map((source) => ({ name: text(source.name), url: source.url })),
      catalogueObservation: false,
      classCode: null,
    }));
  });
}

function placementNote(report, markers, lang) {
  if (markers.length === 0) {
    return localized(report.unmappedNote, lang)
      || (lang === 'en'
        ? 'Not on the map: the source does not give coordinates that can be placed.'
        : 'Pas sur la carte : la source ne donne pas de coordonnées plaçables.');
  }
  const places = markers.map((marker) => marker.place).join(' ; ');
  const base = lang === 'en'
    ? `On the map: ${places}. Approximate position (centroid of the named place), not a GPS reading.`
    : `Sur la carte : ${places}. Position approximative (centroïde du lieu cité), pas un relevé GPS.`;
  const extra = localized(report.placementExtra, lang);
  return extra ? `${base} ${extra}` : base;
}

export function publicReportListItems(reports, lang = 'fr') {
  const french = lang !== 'en';
  const markers = publicReportMapMarkers(reports, french ? 'fr' : 'en');
  return (Array.isArray(reports) ? reports : []).filter(isCitedPublicReport).map((report) => {
    const ownMarkers = markers.filter((marker) => marker.reportId === report.id);
    const first = ownMarkers[0] || null;
    return {
      id: text(report.id),
      title: text(report.title),
      place: text(report.place),
      dateLabel: text(report.dateLabel) || null,
      dateNote: localized(report.dateNote, french ? 'fr' : 'en') || null,
      quote: text(report.quote),
      publicNote: localized(report.publicNote, french ? 'fr' : 'en'),
      sources: report.sources.map((source) => ({ name: text(source.name), url: source.url })),
      onMap: ownMarkers.length > 0,
      placementNote: placementNote(report, ownMarkers, french ? 'fr' : 'en'),
      focus: first
        ? { id: first.id, lat: first.lat, lng: first.lng, zoom: PUBLIC_REPORT_ZOOM }
        : null,
      catalogueObservation: false,
      classCode: null,
    };
  });
}

export function publicReportPopupHtml(marker, lang = 'fr') {
  if (!marker || marker.catalogueObservation !== false || marker.classCode != null) return '';
  const french = lang !== 'en';
  const position = french
    ? (marker.positionLabelFr || marker.positionLabel)
    : (marker.positionLabelEn || marker.positionLabel);
  const sources = Array.isArray(marker.sources) && marker.sources.length > 0
    ? marker.sources
    : [{ name: marker.sourceName, url: marker.url }];
  const sourceHtml = sources.map((source) => (
    `<a href="${escapeHtml(source.url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(source.name)}</a>`
  )).join('<br/>');
  const geocoder = marker.geocoderUrl
    ? `<p><a href="${escapeHtml(marker.geocoderUrl)}" target="_blank" rel="noopener noreferrer">${escapeHtml(marker.geocoderName || 'Nominatim')}</a></p>`
    : '';
  return [
    `<p class="public-report-kicker">${french ? 'Rapport public' : 'Public report'}</p>`,
    `<strong>${escapeHtml(marker.title)}</strong>`,
    `<p>${escapeHtml(marker.place)}</p>`,
    `<p>« ${escapeHtml(marker.quote)} »</p>`,
    marker.dateLabel ? `<p>${escapeHtml(marker.dateLabel)}</p>` : '',
    `<p>${sourceHtml}</p>`,
    `<p>${escapeHtml(marker.publicNote)}</p>`,
    `<p>${escapeHtml(position)}</p>`,
    geocoder,
  ].filter(Boolean).join('');
}
