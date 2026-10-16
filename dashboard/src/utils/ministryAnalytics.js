/**
 * Ministry overview metrics derived only from stored observations.
 * Period comparisons use the previous window of the same length.
 * A percentage is omitted when the previous window has no reports.
 */

export const PERIODS = ['all', '7', '30', '90'];

const UNRESOLVED = new Set(['unconfirmed', 'confirmed', 'in_progress']);

export function observationClass(obs) {
  return (
    obs?.anomaly_type ||
    obs?.detections?.[0]?.class_code ||
    obs?.detections?.[0]?.classCode ||
    null
  );
}

export function observationPriority(obs) {
  const label = String(obs?.priority_label || '').toUpperCase();
  if (label === 'HIGH' || label === 'MEDIUM' || label === 'LOW' || label === 'CRITICAL') {
    return label === 'CRITICAL' ? 'HIGH' : label;
  }
  const score = Number(obs?.priority_score);
  if (!Number.isFinite(score)) return null;
  if (score > 65) return 'HIGH';
  if (score < 35) return 'LOW';
  return 'MEDIUM';
}

export function observationTime(obs) {
  const t = new Date(obs?.created_at || obs?.captured_at || '').getTime();
  return Number.isNaN(t) ? null : t;
}

export function matchesObservationFilters(obs, { classFilter = 'all', priorityFilter = 'all', statusFilter = 'all' } = {}) {
  if (!obs) return false;
  if (classFilter !== 'all' && observationClass(obs) !== classFilter) return false;
  if (priorityFilter !== 'all' && observationPriority(obs) !== priorityFilter) return false;
  if (statusFilter !== 'all' && (obs.status || 'unconfirmed') !== statusFilter) return false;
  return true;
}

export function isWithinPeriod(iso, period, now = Date.now()) {
  if (!period || period === 'all') return true;
  const days = Number(period);
  if (!Number.isFinite(days) || days <= 0) return true;
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return false;
  return t >= now - days * 24 * 60 * 60 * 1000 && t <= now;
}

function inWindow(obs, start, end) {
  const t = observationTime(obs);
  if (t == null) return false;
  return t >= start && t <= end;
}

function dayKey(ts) {
  return new Date(ts).toISOString().slice(0, 10);
}

function utcMidnight(ts) {
  const date = new Date(ts);
  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

function dayBuckets(start, end) {
  const buckets = [];
  let cursor = utcMidnight(start);
  const last = utcMidnight(end);
  while (cursor <= last) {
    const key = new Date(cursor).toISOString().slice(0, 10);
    buckets.push({ key, label: key.slice(5), count: 0 });
    cursor += 86400000;
  }
  return buckets;
}

function weekBuckets(start, end) {
  const first = utcMidnight(start);
  const last = utcMidnight(end);
  if ((last - first) / 86400000 > 800) return null;
  const buckets = [];
  const seen = new Set();
  for (let cursor = first; cursor <= last; cursor += 86400000) {
    const key = weekKey(cursor);
    if (seen.has(key)) continue;
    seen.add(key);
    buckets.push({ key, label: key.slice(5), count: 0 });
  }
  return buckets;
}

function fillCounts(buckets, rows, keyFn) {
  const index = new Map(buckets.map((bucket, i) => [bucket.key, i]));
  rows.forEach((row) => {
    const t = observationTime(row);
    if (t == null) return;
    const slot = index.get(keyFn(t));
    if (slot != null) buckets[slot].count += 1;
  });
  return buckets;
}

function weekKey(ts) {
  const date = new Date(ts);
  const utc = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = utc.getUTCDay() || 7;
  utc.setUTCDate(utc.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(utc.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((utc - yearStart) / 86400000 + 1) / 7);
  return `${utc.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

function countBy(rows, keyFn) {
  const counts = {};
  rows.forEach((row) => {
    const key = keyFn(row);
    if (!key) return;
    counts[key] = (counts[key] || 0) + 1;
  });
  return counts;
}

function changePct(current, previous) {
  if (!previous) return null;
  return Math.round(((current - previous) / previous) * 1000) / 10;
}

function sparseWeeks(rows) {
  const present = new Map();
  rows.forEach((row) => {
    const t = observationTime(row);
    if (t == null) return;
    const key = weekKey(t);
    present.set(key, (present.get(key) || 0) + 1);
  });
  return [...present.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([key, count]) => ({ key, label: key.slice(5), count }));
}

function trend(rows, period, now) {
  if (period === '7' || period === '30') {
    const days = Number(period);
    const start = now - days * 86400000;
    return { unit: 'day', buckets: fillCounts(dayBuckets(start, now), rows, dayKey) };
  }

  if (period === '90') {
    const start = now - 90 * 86400000;
    return { unit: 'week', buckets: fillCounts(weekBuckets(start, now), rows, weekKey) };
  }

  const times = rows.map(observationTime).filter((t) => t != null);
  if (times.length === 0) return { unit: 'week', buckets: [] };
  const start = Math.min(...times);
  const end = Math.max(...times);
  const spanned = weekBuckets(start, end);
  if (!spanned) return { unit: 'week', buckets: sparseWeeks(rows) };
  return { unit: 'week', buckets: fillCounts(spanned, rows, weekKey) };
}

function publicThumb(obs) {
  const media = [obs?.thumbnail_media, obs?.original_media];
  for (const item of media) {
    if (!item) continue;
    if (item.bucket === 'public-photos' || item.bucket === 'demo-images') {
      return item.public_url || null;
    }
  }
  return null;
}

function summarise(rows) {
  const active = rows.filter((o) => o.status !== 'rejected');
  const classCounts = { D40: 0, D20: 0, D10: 0, D00: 0, other: 0 };
  active.forEach((obs) => {
    const code = observationClass(obs);
    if (classCounts[code] != null) classCounts[code] += 1;
    else classCounts.other += 1;
  });

  const priorityCounts = { HIGH: 0, MEDIUM: 0, LOW: 0, unknown: 0 };
  active.forEach((obs) => {
    const label = observationPriority(obs);
    if (label && priorityCounts[label] != null) priorityCounts[label] += 1;
    else priorityCounts.unknown += 1;
  });

  const statusCounts = countBy(rows, (o) => o.status || 'unconfirmed');
  const awaiting = active.filter((o) => UNRESOLVED.has(o.status || 'unconfirmed')).length;
  const repaired = active.filter((o) => o.status === 'repaired').length;
  const high = active.filter((o) => observationPriority(o) === 'HIGH').length;

  return {
    total: active.length,
    rejected: rows.filter((o) => o.status === 'rejected').length,
    high,
    awaiting,
    repaired,
    classCounts,
    priorityCounts,
    statusCounts,
  };
}

export function buildMinistryOverview(observations = [], { period = 'all', now = Date.now() } = {}) {
  const rows = Array.isArray(observations) ? observations : [];
  let current = rows;
  let previous = [];
  let comparison = null;

  if (period !== 'all') {
    const days = Number(period);
    const start = now - days * 24 * 60 * 60 * 1000;
    const prevStart = start - days * 24 * 60 * 60 * 1000;
    current = rows.filter((o) => inWindow(o, start, now));
    previous = rows.filter((o) => inWindow(o, prevStart, start - 1));
    const prevSummary = summarise(previous);
    const currentSummary = summarise(current);
    comparison = {
      previousTotal: prevSummary.total,
      previousHigh: prevSummary.high,
      previousAwaiting: prevSummary.awaiting,
      previousRepaired: prevSummary.repaired,
      totalPct: changePct(currentSummary.total, prevSummary.total),
      highPct: changePct(currentSummary.high, prevSummary.high),
      awaitingPct: changePct(currentSummary.awaiting, prevSummary.awaiting),
      repairedPct: changePct(currentSummary.repaired, prevSummary.repaired),
    };
  }

  const summary = summarise(current);
  const active = current.filter((o) => o.status !== 'rejected');

  const priorityQueue = active
    .filter((obs) => UNRESOLVED.has(obs.status || 'unconfirmed'))
    .sort((a, b) => {
      const scoreA = Number(a.priority_score);
      const scoreB = Number(b.priority_score);
      const safeA = Number.isFinite(scoreA) ? scoreA : Number.NEGATIVE_INFINITY;
      const safeB = Number.isFinite(scoreB) ? scoreB : Number.NEGATIVE_INFINITY;
      if (safeA !== safeB) return safeB - safeA;
      return (observationTime(b) || 0) - (observationTime(a) || 0);
    })
    .slice(0, 6)
    .map(presentObservation);

  const recent = [...current].sort(
    (a, b) => (observationTime(b) || 0) - (observationTime(a) || 0),
  ).slice(0, 6).map(presentObservation);

  return {
    ...summary,
    period,
    comparison,
    trend: trend(active, period, now),
    priorityQueue,
    recent,
    regionAvailable: false,
  };
}

function presentObservation(obs) {
  return {
    id: obs.id,
    classCode: observationClass(obs),
    priority: observationPriority(obs),
    score: Number.isFinite(Number(obs.priority_score)) ? Number(obs.priority_score) : null,
    status: obs.status || 'unconfirmed',
    latitude: Number(obs.latitude) || null,
    longitude: Number(obs.longitude) || null,
    createdAt: obs.created_at || null,
    isDemo: Boolean(obs.is_demo),
    imageUrl: publicThumb(obs),
  };
}
