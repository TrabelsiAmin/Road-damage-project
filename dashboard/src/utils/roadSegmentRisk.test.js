import { describe, it, expect } from 'vitest';
import {
  getRiskLevel,
  generateRiskExplanation,
  computeRoadSegmentsRisk,
} from './roadSegmentRisk';

describe('roadSegmentRisk calculations', () => {
  it('correctly maps numeric scores to risk levels', () => {
    expect(getRiskLevel(85)).toBe('CRITICAL');
    expect(getRiskLevel(70)).toBe('CRITICAL');
    expect(getRiskLevel(65)).toBe('HIGH');
    expect(getRiskLevel(50)).toBe('HIGH');
    expect(getRiskLevel(45)).toBe('MEDIUM');
    expect(getRiskLevel(30)).toBe('MEDIUM');
    expect(getRiskLevel(20)).toBe('LOW');
  });

  it('generates clear, transparent explanations', () => {
    const explanation = generateRiskExplanation({
      activeReportsCount: 4,
      dominantClass: 'D40',
      potholeCount: 3,
      maxPriorityScore: 78.5,
      oldestAgeDays: 32,
      importanceWeight: 1.25,
    });

    expect(explanation).toContain('4 signalements');
    expect(explanation).toContain('3 signalements de classe D40');
    expect(explanation).not.toContain('nid');
    expect(explanation).toContain('32 jours');
    expect(explanation).toContain('Score de sévérité maximal élevé');
  });

  it('aggregates observations and ranks segments by risk score', () => {
    const mockObs = [
      {
        id: 'obs-1',
        latitude: 36.8000,
        longitude: 10.1800,
        anomaly_type: 'D40',
        priority_score: 90,
        status: 'unconfirmed',
        created_at: new Date(Date.now() - 40 * 86400000).toISOString(),
      },
      {
        id: 'obs-2',
        latitude: 36.8005,
        longitude: 10.1805,
        anomaly_type: 'D40',
        priority_score: 85,
        status: 'confirmed',
        created_at: new Date(Date.now() - 20 * 86400000).toISOString(),
      },
      {
        id: 'obs-3',
        latitude: 36.8800,
        longitude: 10.3200,
        anomaly_type: 'D00',
        priority_score: 30,
        status: 'unconfirmed',
        created_at: new Date().toISOString(),
      },
    ];

    const segments = computeRoadSegmentsRisk(mockObs);
    expect(segments.length).toBeGreaterThan(0);

    // First segment must have highest risk
    expect(segments[0].riskScore).toBeGreaterThanOrEqual(segments[segments.length - 1].riskScore);
    expect(segments[0].dominantClass).toBe('D40');
    expect(segments[0].estimatedBudgetTnd).toBeNull();
  });
});
