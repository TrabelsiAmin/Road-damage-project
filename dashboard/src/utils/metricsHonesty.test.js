import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

describe('dashboard does not present hardcoded mAP as measured', () => {
  it('keeps the metrics title and shows an unavailable state', () => {
    const appPath = path.resolve(__dirname, '../App.jsx');
    const content = fs.readFileSync(appPath, 'utf-8');

    expect(content).toContain('Métriques IA & Limites');
    expect(content).toContain('Not available');
    expect(content).toContain('No labeled evaluation set is in this repo');
    expect(content).not.toContain('row.map50');
    expect(content).not.toContain('0.964');
    expect(content).not.toContain('validation_metrics.json');
  });

  it('does not badge the quality view as a RoadSense accuracy bundle', () => {
    const viewPath = path.resolve(__dirname, '../components/DataQualityView.jsx');
    const content = fs.readFileSync(viewPath, 'utf-8');
    expect(content).not.toContain('Bundle v2.1 RoadSense');
    expect(content).not.toContain('highConfidencePct');
    expect(content).toContain('Not available');
  });
});
