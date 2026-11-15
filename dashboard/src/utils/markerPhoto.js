/**
 * Photo shown when a map marker is clicked.
 * A URL is used only when the record already carries one for a public image.
 * Storage paths and press pages are not turned into links here.
 */

import { isCatalogueMapPoint, publicCellKey } from './publicMapCells';

const PUBLIC_BUCKETS = new Set(['public-photos', 'demo-images']);
const MONTHS_FR = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];
const MONTHS_EN = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

export function httpsPhotoUrl(value) {
  const text = String(value ?? '').trim();
  if (!/^https:\/\/[^\s"'<>]+$/i.test(text)) return null;
  try {
    const parsed = new URL(text);
    if (parsed.protocol !== 'https:') return null;
  } catch {
    return null;
  }
  return text;
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function classCaption(value) {
  if (value == null) return null;
  const text = String(value).trim();
  if (!/^[A-Za-z0-9-]{1,12}$/.test(text)) return null;
  return text;
}

/**
 * Public image URL already stored on the marker or its media row.
 * A private bucket URL is left out: it is not displayable without a signature.
 */
export function pickMarkerPhotoUrl(record) {
  if (!record || typeof record !== 'object') return null;
  for (const key of ['photoUrl', 'photo_url', 'image_url', 'public_url']) {
    const url = httpsPhotoUrl(record[key]);
    if (url) return url;
  }
  for (const item of [record.thumbnail_media, record.original_media]) {
    if (!item || typeof item !== 'object') continue;
    if (!PUBLIC_BUCKETS.has(item.bucket)) continue;
    const url = httpsPhotoUrl(item.public_url || item.photoUrl || item.image_url);
    if (url) return url;
  }
  return null;
}

export function formatMarkerDate(value, lang = 'fr') {
  const time = new Date(value);
  if (!Number.isFinite(time.getTime())) return null;
  const day = time.getUTCDate();
  const month = time.getUTCMonth();
  const year = time.getUTCFullYear();
  if (lang === 'en') return `${day} ${MONTHS_EN[month]} ${year}`;
  return `${day} ${MONTHS_FR[month]} ${year}`;
}

export function emptyPhotoHtml(lang = 'fr') {
  const label = lang === 'en' ? 'No photo' : 'Aucune photo';
  return `<p class="anomaly-photo-empty">${label}</p>`;
}

export function photoFigureHtml(photo, lang = 'fr') {
  const url = httpsPhotoUrl(photo?.url);
  if (!url) return '';
  const french = lang !== 'en';
  const empty = french ? 'Aucune photo' : 'No photo';
  const alt = french ? 'Photo du signalement' : 'Anomaly photo';
  const meta = [classCaption(photo?.classCode), formatMarkerDate(photo?.createdAt, french ? 'fr' : 'en')]
    .filter(Boolean)
    .join(' · ');
  return [
    '<figure class="anomaly-photo-frame">',
    `<img data-anomaly-photo="true" data-empty-label="${escapeHtml(empty)}" src="${escapeHtml(url)}" alt="${escapeHtml(alt)}" />`,
    meta ? `<figcaption>${escapeHtml(meta)}</figcaption>` : '',
    '</figure>',
  ].join('');
}

/**
 * Photos that belong on the public grid, keyed by the cell that contains them.
 * Rejected reports, demonstrations, and rows without a public URL stay out.
 */
export function indexCellPhotos(points, cellDegrees = 0.01) {
  const index = new Map();
  for (const point of points || []) {
    if (!isCatalogueMapPoint(point)) continue;
    const url = pickMarkerPhotoUrl(point);
    if (!url) continue;
    const key = publicCellKey(point.latitude, point.longitude, cellDegrees);
    const list = index.get(key) || [];
    if (list.some((item) => item.url === url)) continue;
    list.push({
      url,
      classCode: classCaption(point.anomaly_type),
      createdAt: point.created_at || point.captured_at || null,
    });
    index.set(key, list);
  }
  for (const list of index.values()) {
    list.sort((left, right) => String(left.createdAt || '').localeCompare(String(right.createdAt || ''))
      || String(left.classCode || '').localeCompare(String(right.classCode || '')));
  }
  return index;
}

export function photosFromMembers(members) {
  const photos = [];
  const seen = new Set();
  for (const member of members || []) {
    const url = pickMarkerPhotoUrl(member);
    if (!url || seen.has(url)) continue;
    seen.add(url);
    photos.push({
      url,
      classCode: classCaption(member?.anomaly_type || member?.detections?.[0]?.class_code),
      createdAt: member?.created_at || member?.captured_at || null,
    });
  }
  return photos;
}

export function buildVisitorCellPopupHtml(marker, lang = 'fr') {
  const french = lang !== 'en';
  const count = Number(marker?.count) || 0;
  const classLabel = classCaption(marker?.dominantClass || marker?.dominant_class) || '—';
  const figures = (Array.isArray(marker?.photos) ? marker.photos : [])
    .map((photo) => photoFigureHtml(photo, french ? 'fr' : 'en'))
    .filter(Boolean);
  const photoBlock = figures.length ? figures.join('') : emptyPhotoHtml(french ? 'fr' : 'en');
  const place = french
    ? 'Centre d’une maille d’environ 1 km. Ce n’est pas la position mesurée.'
    : 'Center of a roughly 1 km cell. This is not the measured position.';
  const countWord = french
    ? (count > 1 ? 'signalements' : 'signalement')
    : (count === 1 ? 'report' : 'reports');
  const button = french ? 'Retenir cette observation' : 'Keep this observation';
  return [
    '<div class="anomaly-map-popup">',
    photoBlock,
    `<strong>${count} ${countWord}</strong>`,
    `<p>${escapeHtml(classLabel)}</p>`,
    `<p>${escapeHtml(place)}</p>`,
    `<button type="button" data-rag-ask="true">${escapeHtml(button)}</button>`,
    '</div>',
  ].join('');
}

/** Re-fits the popup after the photo has a height, so the close control stays inside the map. */
export function schedulePopupReflow(popup, root) {
  const run = () => popup?.update?.();
  run();
  if (typeof requestAnimationFrame === 'function') requestAnimationFrame(run);
  root?.querySelectorAll?.('img[data-anomaly-photo]')?.forEach((img) => {
    if (img.complete) run();
    else img.addEventListener('load', run, { once: true });
  });
}

/** Replaces a broken image with the empty label so the popup never shows a broken icon. */
export function bindAnomalyPhotoErrors(root) {
  if (!root || typeof root.querySelectorAll !== 'function') return;
  root.querySelectorAll('img[data-anomaly-photo]').forEach((img) => {
    const fail = () => {
      if (!img.isConnected) return;
      const note = document.createElement('p');
      note.className = 'anomaly-photo-empty';
      note.textContent = img.getAttribute('data-empty-label') || 'Aucune photo';
      img.replaceWith(note);
    };
    img.addEventListener('error', fail);
    if (img.complete && img.naturalWidth === 0) fail();
  });
}
