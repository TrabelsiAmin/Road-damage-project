import { describe, it, expect } from 'vitest';
import { clusterObservations } from './clustering.js';

describe('Clustering - Rejection and GPS Filtering', () => {
  it('excludes observations with status = rejected', () => {
    const obsList = [
      {
        id: 'obs-1',
        latitude: 36.8001,
        longitude: 10.1801,
        status: 'unconfirmed',
        anomaly_type: 'D40',
        priority_score: 75.0,
        priority_label: 'HIGH',
      },
      {
        id: 'obs-2',
        latitude: 36.80012,
        longitude: 10.18012,
        status: 'rejected', // Should be excluded!
        anomaly_type: 'D40',
        priority_score: 80.0,
        priority_label: 'HIGH',
      },
      {
        id: 'obs-3',
        latitude: 36.80015,
        longitude: 10.18015,
        status: 'confirmed',
        anomaly_type: 'D20',
        priority_score: 65.0,
        priority_label: 'MEDIUM',
      },
    ];

    const clusters = clusterObservations(obsList, 20, 25);
    expect(clusters.length).toBe(1);
    expect(clusters[0].count).toBe(2); // Only obs-1 and obs-3
    expect(clusters[0].members.some((m) => m.id === 'obs-2')).toBe(false);
  });

  it('produces 0 clusters when all observations in an area are rejected', () => {
    const obsList = [
      {
        id: 'obs-1',
        latitude: 36.8001,
        longitude: 10.1801,
        status: 'rejected',
        anomaly_type: 'D40',
        priority_score: 75.0,
      },
      {
        id: 'obs-2',
        latitude: 36.80012,
        longitude: 10.18012,
        status: 'rejected',
        anomaly_type: 'D40',
        priority_score: 80.0,
      },
    ];

    const clusters = clusterObservations(obsList, 20, 25);
    expect(clusters.length).toBe(0);
  });
});
