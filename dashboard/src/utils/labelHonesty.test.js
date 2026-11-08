import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';
import { DAMAGE_CLASSES, I18N, REPAIR_COST_STATUS, REPAIR_COST_UNIT, repairCostText } from '../constants';
import { displayClassCode, statClassCode } from './classCodes';

const ROOT = path.resolve(__dirname, '..');

const DISPLAY_FILES = [
  'constants.js',
  'App.jsx',
  'components/ActionCenterView.jsx',
  'components/ExecutiveKpiGrid.jsx',
  'components/ReportsExportsView.jsx',
  'components/RoadSegmentRiskView.jsx',
  'components/CaseDetailModal.jsx',
  'components/DataQualityView.jsx',
  'components/GlobalFilterBar.jsx',
  'components/MinistryOverview.jsx',
  'components/TechnicalRecommendation.jsx',
  'utils/exportFormats.js',
  'utils/commandCenterAnalytics.js',
  'utils/roadSegmentRisk.js',
  'utils/ragClient.js',
];

const UNVERIFIED_NAMES = [
  'Nid-de-poule',
  'Pothole',
  'Alligator',
  'Faïençage',
  'Fissure longitudinale',
  'Fissure transversale',
  'Longitudinal Crack',
  'Transverse Crack',
];

describe('class-label honesty and repair-cost consistency', () => {
  it('keeps the class mapping unknown and shows the stored code only', () => {
    for (const code of ['D00', 'D10', 'D20', 'D40']) {
      expect(DAMAGE_CLASSES[code].code).toBe(code);
      expect(DAMAGE_CLASSES[code].en).toBeUndefined();
      expect(DAMAGE_CLASSES[code].fr).toBeUndefined();
      expect(displayClassCode(code)).toBe(code);
    }
    expect(displayClassCode('D99')).toBe('Unknown class');
    expect(statClassCode('D99')).toBeNull();
    expect(statClassCode(undefined)).toBeNull();
  });

  it('marks repair cost unavailable instead of a confirmed TND price', () => {
    expect(REPAIR_COST_STATUS).toBe('unavailable');
    expect(REPAIR_COST_UNIT).toBe('TND');
    expect(repairCostText('fr')).toBe('Indisponible');
    expect(repairCostText('en')).toBe('Unavailable');
    expect(repairCostText('fr')).not.toMatch(/\d/);
    expect(repairCostText('en')).not.toMatch(/\d/);
    expect(I18N.en.repairCycleNote).not.toMatch(/\d/);
    expect(I18N.fr.repairCycleNote).not.toMatch(/0/);
    expect(I18N.en.healthTooltip).not.toContain('100 -');
    expect(I18N.fr.healthTooltip).not.toContain('100 -');
    expect(I18N.en.repairCycleNote.toLowerCase()).toContain('unavailable');
    expect(I18N.fr.repairCycleNote.toLowerCase()).toContain('indisponible');
  });

  it('uses one unavailable cost source in the Action Center and the KPI tooltip', () => {
    const action = fs.readFileSync(path.join(ROOT, 'components/ActionCenterView.jsx'), 'utf8');
    const kpi = fs.readFileSync(path.join(ROOT, 'components/ExecutiveKpiGrid.jsx'), 'utf8');
    const reports = fs.readFileSync(path.join(ROOT, 'components/ReportsExportsView.jsx'), 'utf8');
    const corridors = fs.readFileSync(path.join(ROOT, 'components/RoadSegmentRiskView.jsx'), 'utf8');
    const constants = fs.readFileSync(path.join(ROOT, 'constants.js'), 'utf8');

    for (const source of [action, kpi, reports, corridors]) {
      expect(source).toContain('repairCostText(lang)');
      expect(source).not.toMatch(/\d+\s*DT/);
      expect(source).not.toContain('180');
      expect(source).not.toContain('280');
      expect(source).not.toContain('450');
      expect(source).not.toContain('defaultCostTnd');
    }
    expect(constants).not.toContain('defaultCostTnd');
    expect(kpi).not.toContain('DGPC unit cost');
    expect(kpi).not.toContain('Base barème');
    expect(kpi).not.toContain('nid-de-poule');
    expect(action).toContain('Cost (TND)');
    expect(action).toContain('Coût (TND)');
  });

  it('does not show unverified class names on dashboard displays', () => {
    for (const rel of DISPLAY_FILES) {
      const content = fs.readFileSync(path.join(ROOT, rel), 'utf8');
      for (const name of UNVERIFIED_NAMES) {
        expect(content, `${rel} contains ${name}`).not.toContain(name);
      }
      expect(content, rel).not.toContain('defaultCostTnd');
      expect(content, rel).not.toContain('0 verified passes');
      expect(content, rel).not.toContain('0 passage de contrôle');
      expect(content, rel).not.toContain('validation_metrics.json');
    }
  });
});
