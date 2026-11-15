import { describe, it, expect } from 'vitest';
import {
  filterObservations,
  buildExecutiveKpis,
  partitionActionCenterQueues,
  buildDataQualityMetrics,
  buildRegionalBacklog,
  demoFilterForSelection,
  clustersForDemoSelection,
} from './commandCenterAnalytics';

describe('commandCenterAnalytics', () => {
  const mockObservations = [
    {
      id: 'obs-1',
      latitude: 36.8000,
      longitude: 10.1800,
      anomaly_type: 'D40',
      priority_score: 85,
      priority_label: 'HIGH',
      status: 'unconfirmed',
      accuracy_meters: 5.0,
      is_demo: false,
      created_at: new Date(Date.now() - 3 * 86400000).toISOString(),
      detections: [{ class_code: 'D40', confidence: 0.88 }],
    },
    {
      id: 'obs-2',
      latitude: 36.8005,
      longitude: 10.1805,
      anomaly_type: 'D20',
      priority_score: 70,
      priority_label: 'HIGH',
      status: 'in_progress',
      accuracy_meters: 35.0, // Poor GPS
      is_demo: false,
      created_at: new Date(Date.now() - 35 * 86400000).toISOString(), // Overdue
      detections: [{ class_code: 'D20', confidence: 0.72 }],
    },
    {
      id: 'obs-3',
      latitude: 36.8800,
      longitude: 10.3200,
      anomaly_type: 'D00',
      priority_score: 25,
      priority_label: 'LOW',
      status: 'repaired',
      accuracy_meters: 6.0,
      is_demo: false,
      created_at: new Date(Date.now() - 10 * 86400000).toISOString(),
      detections: [{ class_code: 'D00', confidence: 0.60 }],
    },
    {
      id: 'obs-4',
      latitude: 35.8256,
      longitude: 10.6369,
      anomaly_type: 'D10',
      priority_score: 40,
      priority_label: 'MEDIUM',
      status: 'rejected', // Rejected
      accuracy_meters: 8.0,
      is_demo: true,
      created_at: new Date().toISOString(),
      detections: [{ class_code: 'D10', confidence: 0.40 }],
    },
  ];

  it('excludes demonstration observations unless the selection asks for them', () => {
    const rows = [
      ...mockObservations,
      {
        id: 'obs-demo',
        latitude: 36.81,
        longitude: 10.19,
        anomaly_type: 'D40',
        priority_score: 50,
        priority_label: 'MEDIUM',
        status: 'unconfirmed',
        is_demo: true,
        created_at: new Date().toISOString(),
      },
    ];
    expect(demoFilterForSelection(false)).toBe('exclude_demo');
    expect(demoFilterForSelection(undefined)).toBe('exclude_demo');
    expect(demoFilterForSelection(true)).toBe('all');

    const hidden = filterObservations(rows, { demoFilter: demoFilterForSelection(false) });
    expect(hidden.map((row) => row.id)).not.toContain('obs-demo');

    const shown = filterObservations(rows, { demoFilter: demoFilterForSelection(true) });
    expect(shown.map((row) => row.id)).toContain('obs-demo');
  });

  it('drops demonstration-only clusters and keeps real ones', () => {
    const clusters = [
      { id: 'demo-only', realCount: 0, demoCount: 2, count: 2, members: [{ id: 'd1', is_demo: true }] },
      { id: 'real', realCount: 1, demoCount: 1, count: 2, members: [{ id: 'r1', is_demo: false }, { id: 'd2', is_demo: true }] },
    ];
    const hidden = clustersForDemoSelection(clusters, false);
    expect(hidden.map((cluster) => cluster.id)).toEqual(['real']);
    expect(hidden[0].members.map((member) => member.id)).toEqual(['r1']);
    expect(hidden[0].count).toBe(1);

    const shown = clustersForDemoSelection(clusters, true);
    expect(shown).toHaveLength(2);
  });

  it('filters observations by class, priority, and status correctly', () => {
    const d40Only = filterObservations(mockObservations, { anomalyClass: 'D40' });
    expect(d40Only.length).toBe(1);
    expect(d40Only[0].id).toBe('obs-1');

    const highOnly = filterObservations(mockObservations, { priority: 'HIGH' });
    expect(highOnly.length).toBe(2);

    const activeOnly = filterObservations(mockObservations, { status: 'unconfirmed' });
    expect(activeOnly.length).toBe(1);
  });

  it('builds accurate Executive KPIs and comparisons', () => {
    const kpis = buildExecutiveKpis(mockObservations);
    expect(kpis.activeAnomalies).toBe(2); // obs-1 and obs-2
    expect(kpis.criticalAnomalies).toBe(2);
    expect(kpis.unconfirmedReports).toBe(1); // obs-1
    expect(kpis.repairsInProgress).toBe(1); // obs-2
    expect(kpis.repairsCompleted).toBe(1); // obs-3
    expect(kpis.overdueCases).toBe(1); // obs-2 (> 14 days)
    expect(kpis.newThisWeek).toBe(1); // obs-1, inside the last 7 days
    expect(kpis.criticalDelta).toBeNull(); // full history has no previous window
    expect(kpis.estimatedOpenBudgetTnd).toBeNull();
    expect(kpis.avgResolutionDays).toBeNull();
  });

  it('partitions observations into Action Center operational queues', () => {
    const queues = partitionActionCenterQueues(mockObservations);
    expect(queues.criticalQueue.length).toBe(2); // obs-1, obs-2
    expect(queues.validationQueue.length).toBe(1); // obs-1
    expect(queues.overdueQueue.length).toBe(1); // obs-2
    expect(queues.unassignedQueue.length).toBe(2); // obs-1, obs-2
    expect(queues.inProgressQueue.length).toBe(1); // obs-2
    expect(queues.poorGpsQueue.length).toBe(1); // obs-2 (35m > 25m)
    expect(queues.critical).toBe(queues.criticalQueue);
    expect(queues.awaiting_validation).toBe(queues.validationQueue);
    expect(queues.overdue).toBe(queues.overdueQueue);
    expect(queues.unassigned).toBe(queues.unassignedQueue);
    expect(queues.in_progress).toBe(queues.inProgressQueue);
    expect(queues.awaiting_verification).toBe(queues.verificationQueue);
    expect(queues.poor_gps).toBe(queues.poorGpsQueue);
    expect(queues.repeated_reports).toBe(queues.multiReportQueue);
  });

  it('counts a case overdue after 14 days and not before', () => {
    const now = Date.parse('2026-11-15T00:00:00Z');
    const rows = [
      { id: 'young', status: 'unconfirmed', priority_label: 'LOW', priority_score: 10, created_at: '2026-11-10T00:00:00Z' },
      { id: 'late', status: 'confirmed', priority_label: 'LOW', priority_score: 10, created_at: '2026-10-20T00:00:00Z' },
      { id: 'done', status: 'repaired', priority_label: 'HIGH', priority_score: 90, created_at: '2026-01-01T00:00:00Z' },
    ];
    const kpis = buildExecutiveKpis(rows, {}, now);
    const queues = partitionActionCenterQueues(rows, {}, now);
    expect(kpis.overdueCases).toBe(1);
    expect(queues.overdue.map((row) => row.id)).toEqual(['late']);
    expect(kpis.criticalAnomalies).toBe(0);
  });

  it('does not treat a low-score D40 as a critical case', () => {
    const rows = [{
      id: 'd40-low',
      status: 'unconfirmed',
      anomaly_type: 'D40',
      priority_label: 'LOW',
      priority_score: 20,
      created_at: new Date().toISOString(),
    }];
    expect(buildExecutiveKpis(rows).criticalAnomalies).toBe(0);
    expect(partitionActionCenterQueues(rows).critical).toHaveLength(0);
    expect(partitionActionCenterQueues(rows).awaiting_validation).toHaveLength(1);
  });

  it('keeps the date pill, the filtered count, and the KPI window on the same rows', () => {
    const now = Date.parse('2026-11-15T12:00:00Z');
    const rows = [
      { id: 'recent', status: 'unconfirmed', priority_label: 'HIGH', priority_score: 80, created_at: '2026-11-14T00:00:00Z', is_demo: false },
      { id: 'older', status: 'unconfirmed', priority_label: 'HIGH', priority_score: 80, created_at: '2026-10-01T00:00:00Z', is_demo: false },
      { id: 'demo', status: 'unconfirmed', priority_label: 'HIGH', priority_score: 90, created_at: '2026-11-14T00:00:00Z', is_demo: true },
    ];
    const filters = { dateRange: '7d', demoFilter: 'exclude_demo' };
    const visible = filterObservations(rows, filters, now);
    const kpis = buildExecutiveKpis(rows, filters, now);
    const queues = partitionActionCenterQueues(visible, {}, now);
    expect(visible.map((row) => row.id)).toEqual(['recent']);
    expect(kpis.totalEvaluated).toBe(1);
    expect(kpis.activeAnomalies).toBe(1);
    expect(kpis.criticalAnomalies).toBe(queues.critical.length);
    expect(kpis.unconfirmedReports).toBe(queues.awaiting_validation.length);
    expect(kpis.criticalDelta).toBe(1);
  });

  it('groups observations within 20 m as repeated reports', () => {
    const rows = [
      { id: 'a', status: 'unconfirmed', latitude: 36.8, longitude: 10.18, priority_label: 'LOW', priority_score: 10, created_at: new Date().toISOString() },
      { id: 'b', status: 'confirmed', latitude: 36.80002, longitude: 10.18002, priority_label: 'LOW', priority_score: 10, created_at: new Date().toISOString() },
      { id: 'c', status: 'unconfirmed', latitude: 36.9, longitude: 10.4, priority_label: 'LOW', priority_score: 10, created_at: new Date().toISOString() },
    ];
    const queues = partitionActionCenterQueues(rows);
    expect(queues.repeated_reports.map((row) => row.id).sort()).toEqual(['a', 'b']);
    expect(queues.repeated_reports[0].reportsCount).toBe(2);
  });

  it('computes Data Quality & Model metrics', () => {
    const dq = buildDataQualityMetrics(mockObservations);
    expect(dq.highConfidencePercent).toBeGreaterThan(0);
    expect(dq.poorGpsPercent).toBeGreaterThan(0);
    expect(dq.classesBreakdown.D40).toBe(1);
  });

  it('does not invent confidence or a D40 class when nothing was stored', () => {
    const empty = buildDataQualityMetrics([]);
    expect(empty.highConfidencePercent).toBeNull();
    expect(empty.poorGpsPercent).toBeNull();
    expect(empty.hasMediaPercent).toBeNull();

    const missing = buildDataQualityMetrics([
      {
        id: 'obs-x',
        status: 'unconfirmed',
        detections: [{ confidence: 0.9 }],
      },
    ]);
    expect(missing.classesBreakdown.D40).toBe(0);
    expect(missing.unspecifiedClassCount).toBe(1);
    expect(missing.highConfidencePercent).toBe(100);
  });

  it('computes regional backlog ranking', () => {
    const backlog = buildRegionalBacklog(mockObservations);
    expect(backlog.length).toBeGreaterThan(0);
    // First entry has the highest active count
    expect(backlog[0].activeCount).toBeGreaterThanOrEqual(backlog[backlog.length - 1].activeCount);
  });
});
