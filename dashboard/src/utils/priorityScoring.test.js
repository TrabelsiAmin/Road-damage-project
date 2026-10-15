import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { calculatePriorityScore, PRIORITY_CONFIG } from './priorityScoring.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('Priority Scoring v2 - JS Core Requirements', () => {
  it('Empty detections returns score 0 and LOW label', () => {
    const res = calculatePriorityScore([]);
    expect(res.score).toBe(0.0);
    expect(res.label).toBe('LOW');
  });

  it('Detections below 0.25 confidence are ignored', () => {
    const res = calculatePriorityScore([
      { classCode: 'D40', confidence: 0.24, box: { width: 0.3, height: 0.3 } },
      { classCode: 'D20', confidence: 0.15, box: { width: 0.4, height: 0.4 } },
    ]);
    expect(res.score).toBe(0.0);
    expect(res.label).toBe('LOW');
  });

  it('A single D40 at 0.41 is not HIGH (the pothole model is weak)', () => {
    const res = calculatePriorityScore([
      { classCode: 'D40', confidence: 0.41, box: { width: 0.35, height: 0.35 } },
    ]);
    expect(res.score).toBeLessThanOrEqual(PRIORITY_CONFIG.highThreshold);
    expect(res.label).toBe('MEDIUM');
  });

  it('1 pothole at 0.9 beats 9 faint cracks at 0.3', () => {
    // 1 pothole at 0.9
    const potholeRes = calculatePriorityScore([
      { classCode: 'D40', confidence: 0.90, box: { width: 0.35, height: 0.35 } },
    ]);

    // 9 faint cracks at 0.3
    const faintCracks = [];
    for (let i = 0; i < 9; i++) {
      faintCracks.push({
        classCode: i % 2 === 0 ? 'D10' : 'D00',
        confidence: 0.30,
        box: { width: 0.1, height: 0.1 },
      });
    }
    const faintCracksRes = calculatePriorityScore(faintCracks);

    expect(potholeRes.score).toBeGreaterThan(faintCracksRes.score);
    expect(potholeRes.score).toBe(90.0);
    expect(potholeRes.label).toBe('HIGH');
    expect(faintCracksRes.score).toBeLessThan(PRIORITY_CONFIG.lowThreshold);
    expect(faintCracksRes.label).toBe('LOW');
  });

  it('Score is monotonic in confidence', () => {
    const confidences = [0.26, 0.35, 0.45, 0.55, 0.70, 0.85, 0.98];
    let previousScore = -1.0;

    for (const conf of confidences) {
      const res = calculatePriorityScore([
        { classCode: 'D20', confidence: conf, box: { width: 0.4, height: 0.4 } },
      ]);
      expect(res.score).toBeGreaterThanOrEqual(previousScore);
      previousScore = res.score;
    }
  });
});

describe('Priority Scoring v2 - Shared Golden Test Vectors (JS)', () => {
  it('Matches shared/priority_golden.json vector values exactly', () => {
    const goldenPath = path.resolve(__dirname, '../../../shared/priority_golden.json');
    expect(fs.existsSync(goldenPath)).toBe(true);

    const goldenVectors = JSON.parse(fs.readFileSync(goldenPath, 'utf8'));

    for (const entry of goldenVectors) {
      const res = calculatePriorityScore(entry.detections);
      const diff = Math.abs(res.score - entry.expectedScore);
      expect(diff).toBeLessThanOrEqual(0.01);
      expect(res.label).toBe(entry.expectedLabel);
    }
  });
});
