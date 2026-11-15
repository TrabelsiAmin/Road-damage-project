import { describe, expect, it } from 'vitest';
import { PUBLIC_ROAD_REPORTS } from '../data/publicRoadReports';
import {
  escapeHtml,
  incidentTotalBreakdown,
  isCitedPublicReport,
  publicReportListItems,
  publicReportMapMarkers,
  publicReportPopupHtml,
  PUBLIC_REPORT_ZOOM,
  storedPublicReportCount,
  sumIncidentTotal,
} from './publicRoadReports';

const CLASS_CODE = /\bD(?:00|10|20|40)\b/;

describe('public road reports', () => {
  it('keeps only cited reports and never assigns a class code', () => {
    expect(PUBLIC_ROAD_REPORTS.filter(isCitedPublicReport)).toHaveLength(PUBLIC_ROAD_REPORTS.length);
    const items = publicReportListItems(PUBLIC_ROAD_REPORTS, 'fr');
    expect(items).toHaveLength(6);
    for (const item of items) {
      expect(item.title).toBeTruthy();
      expect(item.place).toBeTruthy();
      expect(item.sources[0].url).toMatch(/^https:\/\//);
      expect(item.publicNote).toBe('Rapport public, pas une capture TariqMap.');
      expect(item.classCode).toBeNull();
      expect(item.catalogueObservation).toBe(false);
      expect(JSON.stringify(item)).not.toMatch(CLASS_CODE);
    }
    expect(isCitedPublicReport({ title: 'Sans source', place: 'Tunis', quote: 'trou', publicNote: { fr: 'Rapport public, pas une capture TariqMap.' } })).toBe(false);
  });

  it('maps only labeled approximate centroids and leaves the rest off the map', () => {
    const markers = publicReportMapMarkers(PUBLIC_ROAD_REPORTS, 'fr');
    expect(markers.map((marker) => marker.id)).toEqual([
      'oued-el-khayat-2026:jaafar-raoued',
      'sfax-rues-2026-06:rue-palestine-bostane',
      'moulares-2025:moulares-ville',
      'kabaria-2020:kabaria',
    ]);
    expect(markers.find((marker) => marker.reportId === 'oued-el-khayat-2026')).toMatchObject({
      lat: 36.9156857,
      lng: 10.1826972,
      precision: 'approximate-centroid',
    });
    expect(markers.find((marker) => marker.id === 'kabaria-2020:kabaria')).toMatchObject({
      lat: 36.7422859,
      lng: 10.1918110,
    });
    expect(markers.find((marker) => marker.id === 'moulares-2025:moulares-ville')).toMatchObject({
      lat: 34.4857370,
      lng: 8.2733836,
    });
    expect(markers.find((marker) => marker.id === 'sfax-rues-2026-06:rue-palestine-bostane')).toMatchObject({
      lat: 34.7521432,
      lng: 10.7674612,
    });
    for (const marker of markers) {
      expect(marker.positionLabel.toLowerCase()).toContain('approximative');
      expect(marker.classCode).toBeNull();
      expect(marker.catalogueObservation).toBe(false);
      expect(marker.geocoderUrl).toMatch(/^https:\/\/nominatim\.openstreetmap\.org\//);
    }

    const items = publicReportListItems(PUBLIC_ROAD_REPORTS, 'fr');
    const byId = Object.fromEntries(items.map((item) => [item.id, item]));
    expect(byId['a1-pk69-84-2025'].onMap).toBe(false);
    expect(byId['a1-pk69-84-2025'].focus).toBeNull();
    expect(byId['a1-pk69-84-2025'].placementNote).toContain('points kilométriques');
    expect(byId['sfax-perimetre-2026-08'].onMap).toBe(false);
    expect(byId['sfax-perimetre-2026-08'].placementNote).toContain('Pas sur la carte');
    expect(byId['sfax-rues-2026-06'].onMap).toBe(true);
    expect(byId['sfax-rues-2026-06'].placementNote).toContain('rue Palestine');
    expect(byId['sfax-rues-2026-06'].placementNote).toContain('ne sont pas placées');
    expect(byId['oued-el-khayat-2026'].focus).toEqual({
      id: 'oued-el-khayat-2026:jaafar-raoued',
      lat: 36.9156857,
      lng: 10.1826972,
      zoom: PUBLIC_REPORT_ZOOM,
    });
  });

  it('drops a guessed or unlabeled coordinate instead of drawing it', () => {
    const base = {
      id: 'essai',
      title: 'Essai',
      place: 'Tunis',
      quote: 'trou',
      publicNote: { fr: 'Rapport public, pas une capture TariqMap.', en: 'Public report, not a TariqMap capture.' },
      sources: [{ name: 'Exemple', url: 'https://example.com/rapport' }],
      unmappedNote: { fr: 'Pas sur la carte.', en: 'Not on the map.' },
    };
    expect(publicReportMapMarkers([
      { ...base, locations: [{ place: 'Tunis', precision: 'guess', lat: 36.8, lng: 10.1 }] },
    ])).toEqual([]);
    expect(publicReportMapMarkers([
      {
        ...base,
        locations: [{
          place: 'Tunis',
          precision: 'approximate-centroid',
          lat: 0,
          lng: 0,
          positionLabel: { fr: 'Position approximative.', en: 'Approximate position.' },
          geocoderName: 'Nominatim',
          geocoderUrl: 'https://nominatim.openstreetmap.org/search?q=Tunis',
        }],
      },
    ])).toEqual([]);
    expect(publicReportMapMarkers([
      {
        ...base,
        locations: [{
          place: 'Tunis',
          precision: 'approximate-centroid',
          lat: 36.8,
          lng: 10.18,
          positionLabel: { fr: 'Centre ville.', en: 'City center.' },
          geocoderName: 'Nominatim',
          geocoderUrl: 'https://nominatim.openstreetmap.org/search?q=Tunis',
        }],
      },
    ])).toEqual([]);
    const hidden = publicReportListItems([{ ...base, classCode: 'D00' }]);
    expect(hidden).toEqual([]);
  });

  it('adds each stored public report once to the incident total', () => {
    expect(storedPublicReportCount(PUBLIC_ROAD_REPORTS)).toBe(PUBLIC_ROAD_REPORTS.length);
    expect(storedPublicReportCount(publicReportListItems(PUBLIC_ROAD_REPORTS, 'fr'))).toBe(6);
    const manyStreets = PUBLIC_ROAD_REPORTS.find((report) => report.id === 'sfax-rues-2026-06');
    const doubled = {
      ...manyStreets,
      locations: [
        manyStreets.locations[0],
        { ...manyStreets.locations[0], id: 'autre-rue' },
        { ...manyStreets.locations[0], id: 'encore-une-rue' },
      ],
    };
    expect(storedPublicReportCount([doubled])).toBe(1);
    expect(publicReportMapMarkers([doubled])).toHaveLength(3);
    expect(sumIncidentTotal(21, storedPublicReportCount(PUBLIC_ROAD_REPORTS))).toBe(27);
    expect(sumIncidentTotal(31, 6)).toBe(37);
    expect(sumIncidentTotal(0, 6)).toBe(6);
    expect(sumIncidentTotal(null, 6)).toBeNull();
    expect(sumIncidentTotal(undefined, 6)).toBeNull();
    expect(sumIncidentTotal(-1, 6)).toBeNull();
    expect(incidentTotalBreakdown(21, 6, 'fr')).toBe('21 signalements TariqMap + 6 rapports publics');
    expect(incidentTotalBreakdown(1, 1, 'fr')).toBe('1 signalement TariqMap + 1 rapport public');
    expect(incidentTotalBreakdown(21, 6, 'en')).toBe('21 TariqMap reports + 6 public reports');
    expect(incidentTotalBreakdown(null, 6, 'fr')).toBeNull();
    expect(storedPublicReportCount([{ id: 'x', title: 'Sans source' }])).toBe(0);
  });

  it('builds a popup that quotes the source and states the position is approximate', () => {
    const marker = publicReportMapMarkers(PUBLIC_ROAD_REPORTS, 'fr')[0];
    const html = publicReportPopupHtml(marker, 'fr');
    expect(html).toContain('Rapport public');
    expect(html).toContain('pas une capture TariqMap');
    expect(html).toContain('approximative');
    expect(html).toContain('https://businessnews.com.tn/2026/09/21/effondrement-de-la-route-doued-el-khayat-le-ministere-de-lequipement-sexplique/1419358/');
    expect(html).toContain('https://www.lapresse.tn/2026/09/21/voirie-endommagee-a-lariana-quand-la-pluie-met-a-nu-la-fragilite-des-routes/');
    expect(html).not.toMatch(CLASS_CODE);
    expect(publicReportPopupHtml({ ...marker, classCode: 'D40' }, 'fr')).toBe('');
    expect(escapeHtml(`<b class="x">`)).toBe('&lt;b class=&quot;x&quot;&gt;');
  });
});
