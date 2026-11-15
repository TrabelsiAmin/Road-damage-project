/**
 * Executive Overview & Command Center Analytics
 *
 * Implements filter-aware KPI calculations, operational queue partitioning,
 * regional backlog ranking, and model monitoring data quality checks.
 */

import { observationClassCode, statClassCode } from './classCodes';
import { haversineDistanceMeters } from './clustering';
import { eventTimeMs, uniqueObservations, utcDayKey } from './records';
import { resolveTunisiaAdmin } from './tunisiaGeo';
import { computeRoadSegmentsRisk } from './roadSegmentRisk';

const ACTIVE_STATUSES = new Set(['unconfirmed', 'confirmed', 'in_progress']);
const DAY_MS = 86400000;
const REPEAT_RADIUS_METERS = 20;

/** Printed on the overdue KPI and the operations queue. One threshold for both. */
export const OVERDUE_AFTER_DAYS = 14;

/**
 * Start of the selected date pill, or null when the full loaded history stays visible.
 * `period` remains the numeric day count used by older callers.
 */
export function filterCutoffMs(filters = {}, now = Date.now()) {
  const range = filters.dateRange;
  if (range && range !== 'all') {
    if (range === 'today') {
      const date = new Date(now);
      return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
    }
    if (range === 'year') {
      const date = new Date(now);
      return Date.UTC(date.getUTCFullYear(), 0, 1);
    }
    const days = Number(String(range).replace(/d$/, ''));
    if (Number.isFinite(days) && days > 0) return now - days * DAY_MS;
  }
  if (filters.period && filters.period !== 'all') {
    const days = Number(filters.period);
    if (Number.isFinite(days) && days > 0) return now - days * DAY_MS;
  }
  return null;
}

/** HIGH/CRITICAL label, or a stored score of at least 65. A class code alone is not critical. */
export function isCriticalObservation(obs) {
  const label = String(obs?.priority_label || '').toUpperCase();
  if (label === 'CRITICAL' || label === 'HIGH') return true;
  const score = Number(obs?.priority_score);
  return Number.isFinite(score) && score >= 65;
}

export function isOverdueObservation(obs, maintenanceCase = {}, now = Date.now()) {
  const status = obs?.status || 'unconfirmed';
  if (!ACTIVE_STATUSES.has(status)) return false;
  const dueRaw = obs?.due_date || maintenanceCase?.due_date;
  const dueMs = dueRaw ? new Date(dueRaw).getTime() : NaN;
  if (Number.isFinite(dueMs) && dueMs < now) return true;
  const timestamp = eventTimeMs(obs);
  if (timestamp == null) return false;
  return Math.floor((now - timestamp) / DAY_MS) > OVERDUE_AFTER_DAYS;
}

function isAssignedObservation(obs, maintenanceCase = {}) {
  return Boolean(
    maintenanceCase?.assigned_to
    || maintenanceCase?.assigned_contractor_id
    || obs?.assigned_to
    || obs?.assigned_contractor_id
  );
}

function repeatCounts(rows) {
  const located = [];
  rows.forEach((obs) => {
    const lat = Number(obs?.latitude);
    const lng = Number(obs?.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
    if (lat === 0 && lng === 0) return;
    located.push(obs);
  });
  const parent = located.map((_, index) => index);
  const find = (index) => {
    let cursor = index;
    while (parent[cursor] !== cursor) {
      parent[cursor] = parent[parent[cursor]];
      cursor = parent[cursor];
    }
    return cursor;
  };
  const unite = (left, right) => {
    const rootLeft = find(left);
    const rootRight = find(right);
    if (rootLeft !== rootRight) parent[rootRight] = rootLeft;
  };
  for (let i = 0; i < located.length; i += 1) {
    for (let j = i + 1; j < located.length; j += 1) {
      const distance = haversineDistanceMeters(
        Number(located[i].latitude),
        Number(located[i].longitude),
        Number(located[j].latitude),
        Number(located[j].longitude),
      );
      if (distance <= REPEAT_RADIUS_METERS) unite(i, j);
    }
  }
  const size = new Map();
  located.forEach((_, index) => {
    const root = find(index);
    size.set(root, (size.get(root) || 0) + 1);
  });
  const counts = new Map();
  located.forEach((obs, index) => {
    const key = obs?.id != null && obs.id !== '' ? obs.id : obs;
    counts.set(key, size.get(find(index)) || 1);
  });
  return counts;
}

function clockMs(now) {
  const value = Number(now);
  return Number.isFinite(value) ? value : Date.now();
}

/**
 * The checkbox stores includeDemo. The filter itself only understands demoFilter.
 * Absent or false means demonstration rows stay out.
 */
export function demoFilterForSelection(includeDemo) {
  return includeDemo === true ? 'all' : 'exclude_demo';
}

/**
 * Authority map clusters keep the server counts, then drop demonstration
 * rows unless the operator asked to see them. A cluster with no real count
 * and no remaining real member is omitted. It is not shown as zero incidents.
 */
export function clustersForDemoSelection(clusters, includeDemo) {
  if (!Array.isArray(clusters)) return [];
  if (includeDemo === true) return clusters;
  const visible = [];
  for (const cluster of clusters) {
    const members = (cluster?.members || []).filter((member) => member && member.is_demo !== true);
    const realKnown = cluster?.realCount !== undefined && cluster?.realCount !== null && cluster?.realCount !== '';
    const realCount = realKnown ? Number(cluster.realCount) : null;
    const hasReal = realKnown && Number.isFinite(realCount) && realCount > 0;
    if (!hasReal && members.length === 0) continue;
    visible.push({
      ...cluster,
      members,
      count: hasReal ? realCount : members.length,
    });
  }
  return visible;
}

/**
 * Filter evaluation across all dashboard dimensions.
 */
export function filterObservations(observations, filters = {}, now = Date.now()) {
  const unique = uniqueObservations(observations);
  if (!unique || unique.length === 0) return [];

  const {
    governorate = 'all',
    municipality = 'all',
    organization = 'all',
    anomalyClass = 'all',
    priority = 'all',
    status = 'all',
    demoFilter = 'all', // 'all', 'exclude_demo', 'only_demo'
  } = filters;

  const clock = clockMs(now);
  const periodCutoff = filterCutoffMs(filters, clock);

  return unique.filter((obs) => {
    // 1. Demo filter
    if (demoFilter === 'exclude_demo' && obs.is_demo) return false;
    if (demoFilter === 'only_demo' && !obs.is_demo) return false;

    // 2. Status filter
    const obsStatus = obs.status || 'unconfirmed';
    if (status !== 'all' && obsStatus !== status) return false;

    // 3. Class filter. A missing class does not match D40.
    const cls = statClassCode(observationClassCode(obs));
    if (anomalyClass !== 'all' && cls !== anomalyClass) return false;

    // 4. Priority filter
    const rawPriority = (obs.priority_label || '').toUpperCase();
    const resolvedPriority =
      rawPriority === 'CRITICAL' || rawPriority === 'HIGH'
        ? 'HIGH'
        : rawPriority === 'LOW'
        ? 'LOW'
        : Number(obs.priority_score) >= 65
        ? 'HIGH'
        : Number(obs.priority_score) <= 35
        ? 'LOW'
        : 'MEDIUM';

    if (priority !== 'all') {
      if (priority === 'CRITICAL' && rawPriority !== 'CRITICAL' && Number(obs.priority_score) < 80) return false;
      if (priority === 'HIGH' && resolvedPriority !== 'HIGH') return false;
      if (priority === 'MEDIUM' && resolvedPriority !== 'MEDIUM') return false;
      if (priority === 'LOW' && resolvedPriority !== 'LOW') return false;
    }

    // 5. Date period. Undated rows stay out of a bounded window.
    if (periodCutoff != null) {
      const t = eventTimeMs(obs);
      if (t == null || t < periodCutoff || t > clock) return false;
    }

    // 6. Organization filter
    if (organization !== 'all') {
      const orgId = obs.organization_id || '';
      const actor = obs.actor || '';
      const matches =
        orgId === organization ||
        actor.toLowerCase().includes(organization.toLowerCase());
      if (!matches) return false;
    }

    // 7. Geographic filters (Governorate & Municipality)
    if (governorate !== 'all' || municipality !== 'all') {
      const geo = resolveTunisiaAdmin(obs.latitude, obs.longitude);
      if (governorate !== 'all' && geo.governorate.toLowerCase() !== governorate.toLowerCase()) {
        return false;
      }
      if (municipality !== 'all' && geo.municipality.toLowerCase() !== municipality.toLowerCase()) {
        return false;
      }
    }

    return true;
  });
}

/**
 * Calculates Executive KPI numbers and period delta comparisons.
 * A full-history view has no previous window, so the delta stays null.
 */
export function buildExecutiveKpis(observations, filters = {}, now = Date.now(), maintenanceCasesMap = {}) {
  const clock = clockMs(now);
  const filtered = filterObservations(observations, filters, clock);

  const activeReports = filtered.filter((o) => ACTIVE_STATUSES.has(o.status || 'unconfirmed'));
  const activeCount = activeReports.length;

  const criticalReports = activeReports.filter((o) => isCriticalObservation(o));
  const criticalCount = criticalReports.length;

  const segments = computeRoadSegmentsRisk(filtered);
  const highRiskSegments = segments.filter((s) => s.riskLevel === 'CRITICAL' || s.riskLevel === 'HIGH').length;

  const sevenDaysAgo = clock - 7 * DAY_MS;
  const newThisWeek = filtered.filter((o) => {
    const t = eventTimeMs(o);
    return t != null && t >= sevenDaysAgo && t <= clock && o.status !== 'rejected';
  }).length;

  const unconfirmedCount = filtered.filter((o) => (o.status || 'unconfirmed') === 'unconfirmed').length;

  const overdueCount = activeReports.filter((o) => (
    isOverdueObservation(o, maintenanceCasesMap[o.id] || {}, clock)
  )).length;

  const inProgressCount = filtered.filter((o) => o.status === 'in_progress').length;
  const repairedCount = filtered.filter((o) => o.status === 'repaired').length;

  const cutoff = filterCutoffMs(filters, clock);
  let criticalDelta = null;
  let repairDelta = null;
  if (cutoff != null) {
    const length = Math.max(clock - cutoff, DAY_MS);
    const priorStart = cutoff - length;
    const comparable = filterObservations(
      observations,
      { ...filters, dateRange: 'all', period: 'all' },
      clock,
    );
    const prior = comparable.filter((o) => {
      const t = eventTimeMs(o);
      return t != null && t >= priorStart && t < cutoff && o.status !== 'rejected';
    });
    const priorCritical = prior.filter((o) => (
      ACTIVE_STATUSES.has(o.status || 'unconfirmed') && isCriticalObservation(o)
    )).length;
    criticalDelta = criticalCount - priorCritical;
    repairDelta = repairedCount - prior.filter((o) => o.status === 'repaired').length;
  }

  const totalClosedOrActive = activeCount + repairedCount;
  const repairCompletionRate =
    totalClosedOrActive > 0 ? Math.round((repairedCount / totalClosedOrActive) * 100) : null;

  // Repair cost is unavailable. There is no cited TND schedule.
  const estimatedBudgetTnd = null;
  // Not computed from stored repair timestamps.
  const avgResolutionDays = null;
  const activeDateRange = filters.dateRange
    || (filters.period && filters.period !== 'all' ? String(filters.period) : 'all');

  return {
    activeAnomalies: activeCount,
    criticalAnomalies: criticalCount,
    criticalDelta,
    highRiskSegments,
    newThisWeek,
    unconfirmedReports: unconfirmedCount,
    overdueCases: overdueCount,
    repairsInProgress: inProgressCount,
    repairsCompleted: repairedCount,
    repairDelta,
    repairCompletionRate,
    estimatedOpenBudgetTnd: estimatedBudgetTnd,
    avgResolutionDays,
    totalEvaluated: filtered.length,
    activeDateRange,
  };
}

function withQueueAliases(queues) {
  return {
    ...queues,
    criticalQueue: queues.critical,
    validationQueue: queues.awaiting_validation,
    overdueQueue: queues.overdue,
    unassignedQueue: queues.unassigned,
    inProgressQueue: queues.in_progress,
    verificationQueue: queues.awaiting_verification,
    multiReportQueue: queues.repeated_reports,
    poorGpsQueue: queues.poor_gps,
  };
}

/**
 * Partitions observations into the operational queues the Action Center renders.
 * Keys match the queue tabs. Legacy names stay as aliases for existing tests.
 */
export function partitionActionCenterQueues(observations, maintenanceCasesMap = {}, now = Date.now()) {
  const queues = {
    critical: [],
    awaiting_validation: [],
    overdue: [],
    unassigned: [],
    in_progress: [],
    awaiting_verification: [],
    repeated_reports: [],
    poor_gps: [],
  };

  if (!observations) return withQueueAliases(queues);

  const clock = clockMs(now);
  const rows = uniqueObservations(observations).filter((obs) => obs && obs.status !== 'rejected');
  const counts = repeatCounts(rows);

  rows.forEach((obs) => {
    const mCase = maintenanceCasesMap[obs.id] || {};
    const status = obs.status || 'unconfirmed';
    const isActive = ACTIVE_STATUSES.has(status);
    const key = obs.id != null && obs.id !== '' ? obs.id : obs;
    const reportsCount = counts.get(key) || 1;
    const view = reportsCount > 1 ? { ...obs, reportsCount } : obs;
    const accuracy = Number(obs.accuracy_meters);

    if (isActive && isCriticalObservation(obs)) queues.critical.push(view);
    if (status === 'unconfirmed') queues.awaiting_validation.push(view);
    if (isOverdueObservation(obs, mCase, clock)) queues.overdue.push(view);
    if (isActive && !isAssignedObservation(obs, mCase)) queues.unassigned.push(view);
    if (status === 'in_progress') queues.in_progress.push(view);
    if (status === 'repaired' && mCase.verification_status !== 'passed') queues.awaiting_verification.push(view);
    if (reportsCount > 1) queues.repeated_reports.push(view);
    if (Number.isFinite(accuracy) && accuracy > 25) queues.poor_gps.push(view);
  });

  return withQueueAliases(queues);
}

/**
 * Computes AI Model Quality & Field Telemetry metrics.
 */
function _percent(count, total) {
  if (!total) return null;
  return Math.round((count / total) * 100);
}

/**
 * Telemetry from stored observations only.
 * Confidence shares use the stored scores (>= 0.65 high, < 0.45 low).
 * They are not precision, recall, or mAP. Empty input does not invent 100%.
 * A detection with no class_code is counted as unspecified, not as D40.
 */
export function buildDataQualityMetrics(observations) {
  const classesBreakdown = { D40: 0, D20: 0, D10: 0, D00: 0 };
  const empty = {
    highConfidencePercent: null,
    mediumConfidencePercent: null,
    lowConfidencePercent: null,
    highConfidenceCount: 0,
    mediumConfidenceCount: 0,
    lowConfidenceCount: 0,
    scoredDetectionCount: 0,
    poorGpsPercent: null,
    poorGpsCount: 0,
    gpsSampleCount: 0,
    missingMediaCount: 0,
    hasMediaPercent: null,
    hasMediaCount: 0,
    unconfirmedPercent: null,
    totalObservations: 0,
    classesBreakdown,
    unspecifiedClassCount: 0,
    modelVersionsBreakdown: {},
  };

  const rows = uniqueObservations(observations);
  if (!rows || rows.length === 0) return empty;

  let highConfCount = 0;
  let mediumConfCount = 0;
  let lowConfCount = 0;
  let scored = 0;
  let poorGpsCount = 0;
  let gpsSampleCount = 0;
  let missingMediaCount = 0;
  let hasMediaCount = 0;
  let unconfirmedCount = 0;
  let considered = 0;
  let unspecifiedClassCount = 0;
  const modelVersions = {};

  rows.forEach((o) => {
    if (o.status === 'rejected') return;
    considered++;

    if ((o.status || 'unconfirmed') === 'unconfirmed') unconfirmedCount++;

    const acc = Number(o.accuracy_meters);
    if (Number.isFinite(acc)) {
      gpsSampleCount++;
      if (acc > 25.0) poorGpsCount++;
    }

    const hasMedia = Boolean(o.storage_path || o.original_media || o.thumbnail_media);
    if (hasMedia) hasMediaCount++;
    else missingMediaCount++;

    if (o.model_bundle_version) {
      modelVersions[o.model_bundle_version] = (modelVersions[o.model_bundle_version] || 0) + 1;
    }

    (o.detections || []).forEach((d) => {
      const conf = Number(d.confidence);
      if (Number.isFinite(conf)) {
        scored++;
        if (conf >= 0.65) highConfCount++;
        else if (conf < 0.45) lowConfCount++;
        else mediumConfCount++;
      }

      const code = statClassCode(d.class_code);
      if (code) {
        classesBreakdown[code]++;
      } else {
        unspecifiedClassCount++;
      }
    });
  });

  return {
    highConfidencePercent: _percent(highConfCount, scored),
    mediumConfidencePercent: _percent(mediumConfCount, scored),
    lowConfidencePercent: _percent(lowConfCount, scored),
    highConfidenceCount: highConfCount,
    mediumConfidenceCount: mediumConfCount,
    lowConfidenceCount: lowConfCount,
    scoredDetectionCount: scored,
    poorGpsPercent: _percent(poorGpsCount, gpsSampleCount),
    poorGpsCount,
    gpsSampleCount,
    missingMediaCount,
    hasMediaPercent: _percent(hasMediaCount, considered),
    hasMediaCount,
    unconfirmedPercent: _percent(unconfirmedCount, considered),
    totalObservations: rows.length,
    classesBreakdown,
    unspecifiedClassCount,
    modelVersionsBreakdown: modelVersions,
  };
}

/**
 * Computes regional backlog aggregated by Governorate and Municipality.
 */
export function buildRegionalBacklog(observations) {
  if (!observations || observations.length === 0) return [];

  const govMap = new Map();

  observations.forEach((obs) => {
    if (obs.status === 'rejected') return;

    const geo = resolveTunisiaAdmin(obs.latitude, obs.longitude);
    const gov = geo.governorate;

    if (!govMap.has(gov)) {
      govMap.set(gov, {
        governorate: gov,
        activeCount: 0,
        repairedCount: 0,
        totalBudgetTnd: null,
        criticalCount: 0,
        municipalities: new Set(),
      });
    }

    const entry = govMap.get(gov);
    entry.municipalities.add(geo.municipality);

    const isActive = ACTIVE_STATUSES.has(obs.status || 'unconfirmed');
    if (isActive) {
      entry.activeCount++;

      const p = (obs.priority_label || '').toUpperCase();
      if (p === 'CRITICAL' || p === 'HIGH' || Number(obs.priority_score) >= 65) {
        entry.criticalCount++;
      }
    } else if (obs.status === 'repaired') {
      entry.repairedCount++;
    }
  });

  const results = Array.from(govMap.values()).map((e) => ({
    ...e,
    municipalitiesCount: e.municipalities.size,
  }));

  // Sort by active backlog descending
  return results.sort((a, b) => b.activeCount - a.activeCount);
}

/**
 * Time series: New vs Repaired reports over the period.
 */
export function buildNewVsRepairedTimeSeries(observations, days = 30, now = Date.now()) {
  const buckets = [];
  const start = now - days * 86400000;

  for (let i = 0; i <= days; i++) {
    const d = new Date(start + i * 86400000);
    const key = utcDayKey(d.getTime());
    buckets.push({ date: key, label: key.slice(5), newReports: 0, repairedReports: 0 });
  }

  const index = new Map(buckets.map((b, idx) => [b.date, idx]));

  (observations || []).forEach((obs) => {
    if (obs.status === 'rejected') return;

    const createdMs = eventTimeMs(obs);
    const createdDate = createdMs == null ? null : utcDayKey(createdMs);
    const cIdx = index.get(createdDate);
    if (cIdx !== undefined) {
      buckets[cIdx].newReports++;
    }

    if (obs.status === 'repaired') {
      // If repaired, increment on updated_at or created_at date
      const repairedMs = obs.updated_at ? new Date(obs.updated_at).getTime() : createdMs;
      const repDate = Number.isFinite(repairedMs) ? utcDayKey(repairedMs) : null;
      const rIdx = index.get(repDate);
      if (rIdx !== undefined) {
        buckets[rIdx].repairedReports++;
      }
    }
  });

  return buckets;
}
