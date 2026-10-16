import { describe, it, expect } from 'vitest';
import {
  buildMinistryOverview,
  isWithinPeriod,
  matchesObservationFilters,
  observationPriority,
} from './ministryAnalytics.js';

const NOW = Date.parse('2026-10-16T12:00:00.000Z');
const DAY = 24 * 60 * 60 * 1000;

function obs(partial) {
  return {
    id: partial.id,
    anomaly_type: partial.anomaly_type || 'D40',
    priority_score: partial.priority_score ?? 80,
    priority_label: partial.priority_label ?? 'HIGH',
    status: partial.status || 'unconfirmed',
    created_at: partial.created_at,
    latitude: partial.latitude ?? 36.8,
    longitude: partial.longitude ?? 10.18,
    is_demo: partial.is_demo || false,
  };
}

describe('ministry analytics', () => {
  it('uses the stored priority label and does not invent a score', () => {
    expect(observationPriority({ priority_label: 'MEDIUM', priority_score: 90 })).toBe('MEDIUM');
    expect(observationPriority({ priority_score: 70 })).toBe('HIGH');
    expect(observationPriority({})).toBe(null);
  });

  it('counts real statuses and hides a percentage when the previous window is empty', () => {
    const rows = [
      obs({ id: 'a', created_at: new Date(NOW - 2 * DAY).toISOString(), status: 'unconfirmed', priority_label: 'HIGH', priority_score: 80 }),
      obs({ id: 'b', created_at: new Date(NOW - 3 * DAY).toISOString(), status: 'repaired', anomaly_type: 'D00', priority_label: 'LOW', priority_score: 20 }),
      obs({ id: 'c', created_at: new Date(NOW - 40 * DAY).toISOString(), status: 'confirmed', priority_label: 'HIGH', priority_score: 90 }),
      obs({ id: 'd', created_at: new Date(NOW - DAY).toISOString(), status: 'rejected', priority_label: 'HIGH', priority_score: 99 }),
    ];

    const week = buildMinistryOverview(rows, { period: '7', now: NOW });
    expect(week.total).toBe(2);
    expect(week.rejected).toBe(1);
    expect(week.high).toBe(1);
    expect(week.awaiting).toBe(1);
    expect(week.repaired).toBe(1);
    expect(week.classCounts.D40).toBe(1);
    expect(week.classCounts.D00).toBe(1);
    expect(week.comparison.previousTotal).toBe(0);
    expect(week.comparison.totalPct).toBe(null);
    expect(week.priorityQueue.map((item) => item.id)).toEqual(['a']);
    expect(week.recent.map((item) => item.id)).toEqual(['d', 'a', 'b']);
    expect(week.regionAvailable).toBe(false);
    expect(week.trend.buckets.length).toBeGreaterThanOrEqual(7);
    expect(week.trend.buckets.reduce((sum, bucket) => sum + bucket.count, 0)).toBe(2);
  });

  it('counts every report inside the selected window on the trend', () => {
    const rows = [
      obs({ id: 'opening', created_at: new Date(NOW - 7 * DAY + 60 * 60 * 1000).toISOString() }),
      obs({ id: 'latest', created_at: new Date(NOW - 60 * 60 * 1000).toISOString() }),
      obs({ id: 'repaired', created_at: new Date(NOW - 2 * DAY).toISOString(), status: 'repaired', priority_label: 'LOW', priority_score: 10 }),
    ];
    const week = buildMinistryOverview(rows, { period: '7', now: NOW });
    expect(week.total).toBe(3);
    expect(week.priorityQueue.map((item) => item.id)).toEqual(['latest', 'opening']);
    expect(week.trend.buckets.reduce((sum, bucket) => sum + bucket.count, 0)).toBe(week.total);

    const quarter = buildMinistryOverview([
      obs({ id: 'old', created_at: new Date(NOW - 80 * DAY).toISOString() }),
      obs({ id: 'new', created_at: new Date(NOW - 2 * 60 * 60 * 1000).toISOString(), priority_label: 'LOW', priority_score: 12 }),
    ], { period: '90', now: NOW });
    expect(quarter.trend.buckets.reduce((sum, bucket) => sum + bucket.count, 0)).toBe(quarter.total);
    expect(quarter.trend.buckets.at(-1).count).toBeGreaterThan(0);
  });

  it('compares equal windows when both contain reports', () => {
    const rows = [
      obs({ id: 'now', created_at: new Date(NOW - DAY).toISOString() }),
      obs({ id: 'now-2', created_at: new Date(NOW - 2 * DAY).toISOString(), priority_label: 'LOW', priority_score: 10, anomaly_type: 'D10' }),
      obs({ id: 'prev', created_at: new Date(NOW - 10 * DAY).toISOString(), status: 'repaired', priority_label: 'LOW', priority_score: 10 }),
    ];
    const overview = buildMinistryOverview(rows, { period: '7', now: NOW });
    expect(overview.total).toBe(2);
    expect(overview.comparison.previousTotal).toBe(1);
    expect(overview.comparison.totalPct).toBe(100);
  });

  it('does not compare periods when the full catalogue is selected', () => {
    const overview = buildMinistryOverview([
      obs({ id: 'a', created_at: new Date(NOW).toISOString() }),
    ], { period: 'all', now: NOW });
    expect(overview.comparison).toBe(null);
    expect(overview.total).toBe(1);
  });

  it('applies class, priority, and status filters before aggregation', () => {
    const rows = [
      obs({ id: 'keep', anomaly_type: 'D20', priority_label: 'MEDIUM', priority_score: 50, status: 'in_progress' }),
      obs({ id: 'drop', anomaly_type: 'D40', priority_label: 'HIGH', status: 'unconfirmed' }),
    ];
    const scoped = rows.filter((row) => matchesObservationFilters(row, {
      classFilter: 'D20',
      priorityFilter: 'MEDIUM',
      statusFilter: 'in_progress',
    }));
    expect(scoped.map((row) => row.id)).toEqual(['keep']);
    expect(isWithinPeriod(new Date(NOW - 2 * DAY).toISOString(), '7', NOW)).toBe(true);
    expect(isWithinPeriod(new Date(NOW - 20 * DAY).toISOString(), '7', NOW)).toBe(false);
  });
});
