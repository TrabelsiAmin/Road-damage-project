import { describe, expect, it } from 'vitest';
import { aggregatePublicMapCells } from './publicMapCells';
import {
  buildVisitorCellPopupHtml,
  emptyPhotoHtml,
  indexCellPhotos,
  pickMarkerPhotoUrl,
  photosFromMembers,
} from './markerPhoto';

const D40_URL = 'https://cdn.example.com/public-photos/d40.webp';
const D20_URL = 'https://cdn.example.com/public-photos/d20.webp';

describe('marker photo url', () => {
  it('uses a public image url already stored on the record', () => {
    expect(pickMarkerPhotoUrl({ public_url: D40_URL })).toBe(D40_URL);
    expect(pickMarkerPhotoUrl({
      thumbnail_media: { bucket: 'public-photos', public_url: D20_URL },
    })).toBe(D20_URL);
  });

  it('does not invent a url from a storage path or a private bucket', () => {
    expect(pickMarkerPhotoUrl({ storage_path: 'obs/photo.webp', bucket: 'public-photos' })).toBeNull();
    expect(pickMarkerPhotoUrl({
      original_media: { bucket: 'observation-images', public_url: 'https://cdn.example.com/secret.jpg', storage_path: 'secret.jpg' },
    })).toBeNull();
    expect(pickMarkerPhotoUrl({ public_url: 'javascript:alert(1)' })).toBeNull();
    expect(pickMarkerPhotoUrl({ image_url: 'http://cdn.example.com/plain.jpg' })).toBeNull();
    expect(pickMarkerPhotoUrl(null)).toBeNull();
  });

  it('attaches each public photo to the cell of that observation and drops rejected ones', () => {
    const points = [
      { is_demo: false, status: 'unconfirmed', anomaly_type: 'D40', latitude: 37.2592457, longitude: 9.8789713, created_at: '2026-11-05T11:19:28.911Z', public_url: D40_URL },
      { is_demo: false, status: 'unconfirmed', anomaly_type: 'D20', latitude: 37.2600199, longitude: 9.8800905, created_at: '2026-11-05T11:18:13.915Z', public_url: D20_URL },
      { is_demo: false, status: 'rejected', anomaly_type: 'D20', latitude: 37.2524788, longitude: 9.8772957, public_url: 'https://cdn.example.com/rejected.webp' },
      { is_demo: true, status: 'unconfirmed', anomaly_type: 'D00', latitude: 36.8, longitude: 10.18, public_url: 'https://cdn.example.com/demo.webp' },
    ];
    const cells = aggregatePublicMapCells(points);
    const index = indexCellPhotos(points);
    const d40 = cells.find((cell) => cell.dominant_class === 'D40');
    const d20 = cells.find((cell) => cell.dominant_class === 'D20');
    expect(index.get(`${d40.cell_lat}|${d40.cell_lng}`).map((photo) => photo.url)).toEqual([D40_URL]);
    expect(index.get(`${d20.cell_lat}|${d20.cell_lng}`).map((photo) => photo.url)).toEqual([D20_URL]);
    expect(JSON.stringify([...index.values()])).not.toContain('rejected');
    expect(JSON.stringify([...index.values()])).not.toContain('demo.webp');
    expect(JSON.stringify(cells)).not.toContain('https://');
  });

  it('shows the photo with its class and date, or the French empty state', () => {
    const withPhoto = buildVisitorCellPopupHtml({
      count: 2,
      dominantClass: 'D40',
      photos: [{ url: D40_URL, classCode: 'D40', createdAt: '2026-11-05T11:19:28.911Z' }],
    }, 'fr');
    expect(withPhoto).toContain(`src="${D40_URL}"`);
    expect(withPhoto).toContain('D40');
    expect(withPhoto).toContain('5 novembre 2026');
    expect(withPhoto).toContain('Centre d’une maille');
    expect(withPhoto).toContain('data-empty-label="Aucune photo"');
    expect(withPhoto).not.toContain('class="anomaly-photo-empty"');

    const empty = buildVisitorCellPopupHtml({ count: 1, dominantClass: 'D00', photos: [] }, 'fr');
    expect(empty).toContain('Aucune photo');
    expect(empty).toContain('D00');
    expect(empty).toContain('Centre d’une maille');
    expect(empty).not.toContain('src=');
    expect(emptyPhotoHtml('fr')).toBe('<p class="anomaly-photo-empty">Aucune photo</p>');
  });

  it('escapes a hostile url and ignores it when it is not https', () => {
    const html = buildVisitorCellPopupHtml({
      count: 1,
      dominantClass: 'D20',
      photos: [{ url: 'https://cdn.example.com/a.webp?q="><img>', classCode: 'D20', createdAt: '2026-11-05T00:00:00Z' }],
    }, 'fr');
    expect(html).not.toContain('<img src');
    expect(html).toContain('Aucune photo');
    expect(photosFromMembers([
      { thumbnail_media: { bucket: 'public-photos', public_url: D20_URL }, anomaly_type: 'D20', created_at: '2026-11-05T11:18:13.915Z' },
      { original_media: { bucket: 'observation-images', public_url: 'https://cdn.example.com/private.jpg' } },
    ])).toEqual([
      { url: D20_URL, classCode: 'D20', createdAt: '2026-11-05T11:18:13.915Z' },
    ]);
  });
});
