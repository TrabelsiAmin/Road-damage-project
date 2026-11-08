/**
 * Executive Overview & Command Center Analytics
 *
 * Implements filter-aware KPI calculations, operational queue partitioning,
 * regional backlog ranking, and model monitoring data quality checks.
 */

import { observationClassCode, statClassCode } from './classCodes';
import { eventTimeMs, uniqueObservations, utcDayKey } from './records';
import { resolveTunisiaAdmin } from './tunisiaGeo';
import { computeRoadSegmentsRisk } from './roadSegmentRisk';

const ACTIVE_STATUSES = new Set(['unconfirmed', 'confirmed', 'in_progress']);

/**
 * Filter evaluation across all dashboard dimensions.
 */
export function filterObservations(observations, filters = {}) {
  const unique = uniqueObservations(observations);
  if (!unique || unique.length === 0) return [];

  const {
    period = 'all',
    governorate = 'all',
    municipality = 'all',
    organization = 'all',
    anomalyClass = 'all',
    priority = 'all',
    status = 'all',
    demoFilter = 'all', // 'all', 'exclude_demo', 'only_demo'
  } = filters;

  const now = Date.now();
  const periodDays = period !== 'all' ? Number(period) : null;
  const periodCutoff = periodDays ? now - periodDays * 86400000 : null;

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

    // 5. Date Period
    if (periodCutoff) {
      const t = eventTimeMs(obs);
      if (t == null || t < periodCutoff) return false;
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
 */
export function buildExecutiveKpis(observations, filters = {}, now = Date.now()) {
  const filtered = filterObservations(observations, filters);

  // Compute prior window for trend comparisons
  const periodDays = filters.period && filters.period !== 'all' ? Number(filters.period) : 30;
  const currentWindowStart = now - periodDays * 86400000;
  const priorWindowStart = currentWindowStart - periodDays * 86400000;

  const source = uniqueObservations(observations);
  const currentWindowReports = source.filter((o) => {
    const t = eventTimeMs(o);
    return t != null && t >= currentWindowStart && t <= now && o.status !== 'rejected';
  });

  const priorWindowReports = source.filter((o) => {
    const t = eventTimeMs(o);
    return t != null && t >= priorWindowStart && t < currentWindowStart && o.status !== 'rejected';
  });

  // KPI 1: Active anomalies (excluding rejected)
  const activeReports = filtered.filter((o) => ACTIVE_STATUSES.has(o.status || 'unconfirmed'));
  const activeCount = activeReports.length;

  // KPI 2: Critical anomalies (Score >= 65 or HIGH/CRITICAL)
  const criticalReports = activeReports.filter((o) => {
    const p = (o.priority_label || '').toUpperCase();
    return p === 'CRITICAL' || p === 'HIGH' || Number(o.priority_score) >= 65;
  });
  const criticalCount = criticalReports.length;

  // Prior window critical count for delta
  const priorCriticalCount = priorWindowReports.filter((o) => {
    const p = (o.priority_label || '').toUpperCase();
    return (p === 'CRITICAL' || p === 'HIGH' || Number(o.priority_score) >= 65) && ACTIVE_STATUSES.has(o.status || 'unconfirmed');
  }).length;
  const criticalDelta = criticalCount - priorCriticalCount;

  // KPI 3: High-risk road segments
  const segments = computeRoadSegmentsRisk(filtered);
  const highRiskSegments = segments.filter((s) => s.riskLevel === 'CRITICAL' || s.riskLevel === 'HIGH').length;

  // KPI 4: New reports this week (last 7 days)
  const sevenDaysAgo = now - 7 * 86400000;
  const newThisWeek = filtered.filter((o) => {
    const t = eventTimeMs(o);
    return t != null && t >= sevenDaysAgo && o.status !== 'rejected';
  }).length;

  // KPI 5: Unconfirmed reports (Awaiting validation)
  const unconfirmedCount = filtered.filter((o) => (o.status || 'unconfirmed') === 'unconfirmed').length;

  // KPI 6: Overdue maintenance cases (> 30 days without resolution or past due date)
  const overdueCount = activeReports.filter((o) => {
    const t = eventTimeMs(o);
    const ageDays = t == null ? 0 : Math.floor((now - t) / 86400000);
    const dueDatePassed = o.due_date && new Date(o.due_date).getTime() < now;
    return (t != null && ageDays > 30) || dueDatePassed;
  }).length;

  // KPI 7: Repairs in progress
  const inProgressCount = filtered.filter((o) => o.status === 'in_progress').length;

  // KPI 8: Repairs completed
  const repairedCount = filtered.filter((o) => o.status === 'repaired').length;
  const priorRepairedCount = priorWindowReports.filter((o) => o.status === 'repaired').length;
  const repairDelta = repairedCount - priorRepairedCount;

  // Repair completion rate
  const totalClosedOrActive = activeCount + repairedCount;
  const repairCompletionRate =
    totalClosedOrActive > 0 ? Math.round((repairedCount / totalClosedOrActive) * 100) : null;

  // KPI 9: Repair cost is unavailable. There is no cited TND schedule,
  // so a known class is not given a price and an unknown class is not priced as D40.
  const estimatedBudgetTnd = null;

  // Not computed from stored repair timestamps.
  const avgResolutionDays = null;

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
  };
}

/**
 * Partitions observations into actionable operational queues for the Action Center.
 */
export function partitionActionCenterQueues(observations, maintenanceCasesMap = {}, now = Date.now()) {
  const queues = {
    criticalQueue: [],
    validationQueue: [],
    overdueQueue: [],
    unassignedQueue: [],
    inProgressQueue: [],
    verificationQueue: [],
    multiReportQueue: [],
    poorGpsQueue: [],
  };

  if (!observations) return queues;

  uniqueObservations(observations).forEach((obs) => {
    if (obs.status === 'rejected') return;

    const mCase = maintenanceCasesMap[obs.id] || {};
    const status = obs.status || 'unconfirmed';
    const isActive = ACTIVE_STATUSES.has(status);

    const pLabel = (obs.priority_label || '').toUpperCase();
    const pScore = Number(obs.priority_score) || 0;
    const isCritical = pLabel === 'CRITICAL' || pLabel === 'HIGH' || pScore >= 65 || obs.anomaly_type === 'D40';

    const t = new Date(obs.created_at || obs.captured_at || now).getTime();
    const ageDays = Math.floor((now - t) / 86400000);
    const isOverdue = isActive && (ageDays > 30 || (mCase.due_date && new Date(mCase.due_date).getTime() < now));

    const isAssigned = Boolean(mCase.assigned_to || obs.assigned_to);
    const accuracy = Number(obs.accuracy_meters);

    // Queue 1: Critical safety hazards
    if (isActive && isCritical) {
      queues.criticalQueue.push(obs);
    }

    // Queue 2: Awaiting validation
    if (status === 'unconfirmed') {
      queues.validationQueue.push(obs);
    }

    // Queue 3: Overdue maintenance
    if (isOverdue) {
      queues.overdueQueue.push(obs);
    }

    // Queue 4: Unassigned cases
    if (isActive && !isAssigned) {
      queues.unassignedQueue.push(obs);
    }

    // Queue 5: In progress
    if (status === 'in_progress') {
      queues.inProgressQueue.push(obs);
    }

    // Queue 6: Repairs awaiting verification pass
    if (status === 'repaired' && mCase.verification_status !== 'passed') {
      queues.verificationQueue.push(obs);
    }

    // Queue 7: Poor GPS accuracy (> 25m)
    if (Number.isFinite(accuracy) && accuracy > 25.0) {
      queues.poorGpsQueue.push(obs);
    }
  });

  return queues;
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
