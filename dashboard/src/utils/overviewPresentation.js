/**
 * Figures for the ministry overview.
 * Counts come from loaded observations or from the public aggregate.
 * A failed load stays null so the screen can say Indisponible instead of 0.
 * Road and governorate names are derived from coordinates. They are not stored fields.
 */

import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import { displayClassCode, statClassCode } from './classCodes';
import { observationClass, observationPriority, observationTime } from './ministryAnalytics';
import { catalogueReportCount } from './publicMapCells';
import { publicDamageTotals } from './publicStats';
import { resolveTunisiaAdmin } from './tunisiaGeo';

const CLASS_ORDER = ['D40', 'D20', 'D10', 'D00'];
const PRIORITY_ORDER = ['HIGH', 'MEDIUM', 'LOW'];
const PRIORITY_COLORS = {
  HIGH: '#EF4444',
  MEDIUM: '#F59E0B',
  LOW: '#2563EB',
  unknown: '#94A3B8',
};
const MONTHS_FR = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const MONTHS_EN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export function formatIncidentDate(iso, lang = 'fr') {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  try {
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Africa/Tunis',
      day: 'numeric',
      month: 'numeric',
      year: 'numeric',
    }).formatToParts(date);
    const day = Number(parts.find((part) => part.type === 'day')?.value);
    const month = Number(parts.find((part) => part.type === 'month')?.value);
    const year = parts.find((part) => part.type === 'year')?.value;
    if (!day || !month || !year) return null;
    const names = lang === 'fr' ? MONTHS_FR : MONTHS_EN;
    return `${day} ${names[month - 1]} ${year}`;
  } catch {
    return null;
  }
}

function locatedAdmin(lat, lng) {
  const latitude = Number(lat);
  const longitude = Number(lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (latitude === 0 && longitude === 0) return null;
  const geo = resolveTunisiaAdmin(latitude, longitude);
  if (!geo || geo.governorate === 'Non déterminé') return null;
  return geo;
}

function activeRows(observations) {
  return (Array.isArray(observations) ? observations : []).filter((row) => row && row.status !== 'rejected');
}

function classBucket(obs) {
  return statClassCode(observationClass(obs)) || 'other';
}

function summarise(rows) {
  const classCounts = { D40: 0, D20: 0, D10: 0, D00: 0, other: 0 };
  const priorityCounts = { HIGH: 0, MEDIUM: 0, LOW: 0, unknown: 0 };
  rows.forEach((obs) => {
    const code = classBucket(obs);
    classCounts[code] = (classCounts[code] || 0) + 1;
    const priority = observationPriority(obs);
    const key = priority && priorityCounts[priority] != null ? priority : 'unknown';
    priorityCounts[key] += 1;
  });
  return { total: rows.length, classCounts, priorityCounts };
}

function publicBuckets(summary) {
  const classCounts = { D40: 0, D20: 0, D10: 0, D00: 0, other: 0 };
  const priorityCounts = { HIGH: 0, MEDIUM: 0, LOW: 0, unknown: 0 };
  (Array.isArray(summary) ? summary : []).forEach((row) => {
    const openCount = Number(row?.open_count);
    const repairedCount = Number(row?.repaired_count);
    const count = (Number.isFinite(openCount) ? openCount : 0) + (Number.isFinite(repairedCount) ? repairedCount : 0);
    if (count <= 0) return;
    const code = statClassCode(row?.anomaly_type);
    classCounts[code || 'other'] += count;
    const band = String(row?.priority_band || '').toUpperCase();
    const priority = band === 'CRITICAL' ? 'HIGH' : band;
    const key = priorityCounts[priority] != null ? priority : 'unknown';
    priorityCounts[key] += count;
  });
  return { classCounts, priorityCounts };
}

function sumOf(counts, keys) {
  return keys.reduce((total, key) => total + (Number(counts?.[key]) || 0), 0);
}

function slicesFrom(counts, order, colorFor, labelFor) {
  const keys = order.filter((key) => (Number(counts?.[key]) || 0) > 0);
  const extra = (Number(counts?.other) || 0) > 0 ? ['other'] : [];
  const unknown = (Number(counts?.unknown) || 0) > 0 ? ['unknown'] : [];
  const used = [...keys, ...extra, ...unknown];
  const total = used.reduce((sum, key) => sum + (Number(counts[key]) || 0), 0);
  if (total <= 0) return [];
  return used.map((key) => {
    const value = Number(counts[key]) || 0;
    return {
      key,
      label: labelFor(key),
      value,
      color: colorFor(key),
      percent: Math.round((value / total) * 100),
    };
  });
}

function chartFor(classCounts, priorityCounts, lang) {
  const knownClasses = sumOf(classCounts, CLASS_ORDER);
  const french = lang !== 'en';
  if (knownClasses > 0 || (classCounts?.other || 0) > 0) {
    const slices = slicesFrom(
      classCounts,
      CLASS_ORDER,
      (key) => DAMAGE_CLASSES[key]?.color || '#94A3B8',
      (key) => (key === 'other' ? (french ? 'Non classé' : 'Unclassified') : key),
    );
    if (slices.length === 0) return null;
    return {
      mode: 'class',
      title: french ? 'Répartition par classe' : 'Split by class',
      slices,
    };
  }
  const slices = slicesFrom(
    priorityCounts,
    PRIORITY_ORDER,
    (key) => PRIORITY_COLORS[key] || '#94A3B8',
    (key) => (key === 'unknown' ? (french ? 'Sans priorité' : 'Unscored') : key),
  );
  if (slices.length === 0) return null;
  return {
    mode: 'priority',
    title: french ? 'Répartition par priorité' : 'Split by priority',
    slices,
  };
}

function collectPlaces(points) {
  const routes = new Set();
  const zones = new Set();
  const zoneCounts = new Map();
  points.forEach((point) => {
    const geo = locatedAdmin(point.latitude, point.longitude);
    if (!geo) return;
    const weight = Number(point.weight);
    const amount = Number.isFinite(weight) && weight > 0 ? weight : 1;
    if (geo.roadSegment && geo.roadSegment !== 'Voie non répertoriée') routes.add(geo.roadSegment);
    zones.add(geo.governorate);
    zoneCounts.set(geo.governorate, (zoneCounts.get(geo.governorate) || 0) + amount);
  });
  const regions = [...zoneCounts.entries()]
    .map(([label, value]) => ({ key: label, label, value }))
    .sort((a, b) => b.value - a.value || a.label.localeCompare(b.label, 'fr'));
  return { routeCount: routes.size, zoneCount: zones.size, regions };
}

function trimRegions(regions, lang) {
  if (regions.length <= 6) return regions;
  const head = regions.slice(0, 5);
  const rest = regions.slice(5).reduce((sum, region) => sum + region.value, 0);
  head.push({
    key: 'other-regions',
    label: lang === 'fr' ? 'Autres gouvernorats' : 'Other governorates',
    value: rest,
  });
  return head;
}

function organizationName(obs, organizations) {
  const id = obs?.organization_id || obs?.assigned_contractor_id || null;
  if (id && Array.isArray(organizations)) {
    const found = organizations.find((org) => org.id === id);
    if (found?.name) return found.name;
  }
  const named = obs?.assigned_to_name;
  if (typeof named === 'string' && named.trim()) return named.trim();
  return null;
}

function placeOf(obs) {
  const geo = locatedAdmin(obs?.latitude, obs?.longitude);
  if (!geo) return { road: null, place: null };
  const place = geo.municipality && geo.municipality !== geo.governorate
    ? `${geo.municipality}, ${geo.governorate}`
    : geo.governorate;
  return { road: geo.roadSegment || null, place };
}

function presentRows(rows, organizations, lang) {
  return [...rows]
    .sort((a, b) => (observationTime(b) || 0) - (observationTime(a) || 0))
    .slice(0, 5)
    .map((obs) => {
      const status = obs.status || 'unconfirmed';
      const statusText = STATUS_LABELS[status];
      const located = placeOf(obs);
      return {
        id: obs.id,
        dateLabel: formatIncidentDate(obs.created_at || obs.captured_at, lang),
        road: located.road,
        place: located.place,
        classCode: displayClassCode(observationClass(obs)),
        status,
        statusLabel: statusText ? (lang === 'fr' ? statusText.fr : statusText.en) : status,
        organization: organizationName(obs, organizations),
      };
    });
}

export function periodDelta(comparison, total) {
  const previous = Number(comparison?.previousTotal);
  const pct = Number(comparison?.totalPct);
  if (!(previous > 0) || !(Number(total) > 0) || !Number.isFinite(pct)) return null;
  return { pct, previous };
}

export function officialPublicTotalNote(lang = 'fr') {
  return lang === 'fr'
    ? 'Signalements réels non rejetés du catalogue visible. Le total public officiel reste indisponible.'
    : 'Non-rejected real reports in the visible catalogue. The official public total is still unavailable.';
}

/**
 * The public cell count is a floor only while the authority view is unfiltered.
 * A period, class, or search must be allowed to show a smaller slice.
 */
export function catalogueFloorFor(filters, cells) {
  if (filters) {
    const open = (filters.dateRange || 'all') === 'all'
      && (filters.governorate || 'all') === 'all'
      && (filters.municipality || 'all') === 'all'
      && (filters.anomalyClass || 'all') === 'all'
      && (filters.priority || 'all') === 'all'
      && (filters.status || 'all') === 'all'
      && (filters.organization || 'all') === 'all';
    if (!open) return null;
  }
  return catalogueReportCount(cells);
}

function cellPlaces(publicCells) {
  return collectPlaces((publicCells || []).map((cell) => ({
    latitude: cell?.cell_lat,
    longitude: cell?.cell_lng,
    weight: Number(cell?.report_count) > 0 ? Number(cell.report_count) : 1,
  })));
}

function catalogueClassBuckets(catalogueStats) {
  if (!catalogueStats || !Array.isArray(catalogueStats.classes)) return null;
  const classCounts = { D40: 0, D20: 0, D10: 0, D00: 0, other: 0 };
  const priorityCounts = { HIGH: 0, MEDIUM: 0, LOW: 0, unknown: 0 };
  catalogueStats.classes.forEach((row) => {
    const count = Number(row?.count);
    if (!Number.isFinite(count) || count <= 0) return;
    const code = statClassCode(row?.anomaly_type);
    classCounts[code || 'other'] += count;
  });
  return { classCounts, priorityCounts };
}

function catalogueOverview({
  publicCells,
  catalogueStats,
  lang,
  tableState,
}) {
  const places = cellPlaces(publicCells);
  const buckets = catalogueClassBuckets(catalogueStats);
  return {
    status: 'ready',
    total: catalogueReportCount(publicCells),
    delta: null,
    routeCount: places.routeCount,
    zoneCount: places.zoneCount,
    totalNote: officialPublicTotalNote(lang),
    lastIncident: null,
    chart: buckets ? chartFor(buckets.classCounts, buckets.priorityCounts, lang) : null,
    regions: trimRegions(places.regions, lang),
    rows: [],
    tableState,
  };
}

export function buildOverviewPresentation({
  observations = [],
  canSeeRows = false,
  figureStatus = 'unavailable',
  publicSummary = [],
  publicCells = [],
  catalogueStats = null,
  catalogueFloor = null,
  comparison = null,
  authorityTotal = null,
  authorityClassCounts = null,
  authorityPriorityCounts = null,
  organizations = [],
  catalogueTotal = null,
  loadedCount = 0,
  listTruncated = false,
  lang = 'fr',
} = {}) {
  const knownReports = catalogueReportCount(publicCells);
  const restricted = {
    status: figureStatus,
    total: null,
    delta: null,
    routeCount: null,
    zoneCount: null,
    totalNote: null,
    lastIncident: null,
    chart: null,
    regions: [],
    rows: [],
    tableState: canSeeRows ? (figureStatus === 'loading' ? 'loading' : 'unavailable') : 'restricted',
  };

  if (!canSeeRows) {
    if (figureStatus === 'ready') {
      const totals = publicDamageTotals(publicSummary);
      const buckets = publicBuckets(publicSummary);
      const places = cellPlaces(publicCells);
      return {
        status: 'ready',
        total: totals ? totals.total : 0,
        delta: null,
        routeCount: places.routeCount,
        zoneCount: places.zoneCount,
        totalNote: null,
        lastIncident: null,
        chart: chartFor(buckets.classCounts, buckets.priorityCounts, lang),
        regions: trimRegions(places.regions, lang),
        rows: [],
        tableState: 'restricted',
      };
    }
    if (knownReports != null) {
      return catalogueOverview({
        publicCells,
        catalogueStats,
        lang,
        tableState: 'restricted',
      });
    }
    return restricted;
  }

  if (figureStatus !== 'ready') {
    if (knownReports != null) {
      return catalogueOverview({
        publicCells,
        catalogueStats,
        lang,
        tableState: 'listMissing',
      });
    }
    return restricted;
  }

  const rows = activeRows(observations);
  const counted = summarise(rows);
  const classCounts = authorityClassCounts || counted.classCounts;
  const priorityCounts = authorityPriorityCounts || counted.priorityCounts;
  const countedTotal = Number.isFinite(Number(authorityTotal)) ? Number(authorityTotal) : counted.total;
  const floor = Number(catalogueFloor);
  const floored = Number.isFinite(floor) && floor > 0 && floor > countedTotal;
  const total = floored ? floor : countedTotal;
  const authorityPlaces = collectPlaces(rows.map((obs) => ({
    latitude: obs.latitude,
    longitude: obs.longitude,
    weight: 1,
  })));
  const knownPlaces = cellPlaces(publicCells);
  const useKnownPlaces = (floored || (authorityPlaces.routeCount === 0 && authorityPlaces.zoneCount === 0))
    && (knownPlaces.routeCount > 0 || knownPlaces.zoneCount > 0);
  const places = useKnownPlaces ? knownPlaces : authorityPlaces;
  const tableRows = presentRows(rows, organizations, lang);
  const latest = tableRows.find((row) => row.dateLabel);
  const catalogue = Number(catalogueTotal);
  const loaded = Number(loadedCount);
  const truncatedNote = listTruncated && Number.isFinite(catalogue) && Number.isFinite(loaded) && catalogue > loaded
    ? (lang === 'fr'
      ? `${loaded} signalement${loaded > 1 ? 's' : ''} chargé${loaded > 1 ? 's' : ''} pour les totaux, ${catalogue} au catalogue.`
      : `${loaded} loaded into the totals, ${catalogue} in the catalogue.`)
    : null;
  const knownBuckets = floored ? catalogueClassBuckets(catalogueStats) : null;
  const chart = knownBuckets
    ? chartFor(knownBuckets.classCounts, knownBuckets.priorityCounts, lang)
    : chartFor(classCounts, priorityCounts, lang);

  return {
    status: 'ready',
    total,
    delta: floored ? null : periodDelta(comparison, total),
    routeCount: places.routeCount,
    zoneCount: places.zoneCount,
    totalNote: floored ? officialPublicTotalNote(lang) : truncatedNote,
    lastIncident: latest
      ? { dateLabel: latest.dateLabel, place: latest.place }
      : null,
    chart,
    regions: trimRegions(places.regions, lang),
    rows: tableRows,
    tableState: tableRows.length > 0 ? 'rows' : (floored ? 'listMissing' : 'empty'),
  };
}
