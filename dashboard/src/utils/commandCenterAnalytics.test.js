import { describe, it, expect } from 'vitest';
import {
  filterObservations,
  buildExecutiveKpis,
  partitionActionCenterQueues,
  buildDataQualityMetrics,
  buildRegionalBacklog,
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
    expect(kpis.overdueCases).toBe(1); // obs-2 (> 30 days)
    expect(kpis.estimatedOpenBudgetTnd).toBeGreaterThan(0);
  });

  it('partitions observations into Action Center operational queues', () => {
    const queues = partitionActionCenterQueues(mockObservations);
    expect(queues.criticalQueue.length).toBe(2); // obs-1, obs-2
    expect(queues.validationQueue.length).toBe(1); // obs-1
    expect(queues.overdueQueue.length).toBe(1); // obs-2
    expect(queues.unassignedQueue.length).toBe(2); // obs-1, obs-2
    expect(queues.inProgressQueue.length).toBe(1); // obs-2
    expect(queues.poorGpsQueue.length).toBe(1); // obs-2 (35m > 25m)
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
