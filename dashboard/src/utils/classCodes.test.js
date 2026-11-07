import { describe, it, expect } from 'vitest';
import {
  displayClassCode,
  isKnownClassCode,
  observationClassCode,
  statClassCode,
  UNKNOWN_CLASS_LABEL,
} from './classCodes';

describe('classCodes', () => {
  it('keeps the four stored codes and does not rename them', () => {
    for (const code of ['D00', 'D10', 'D20', 'D40']) {
      expect(displayClassCode(code)).toBe(code);
      expect(statClassCode(code)).toBe(code);
      expect(isKnownClassCode(code)).toBe(true);
    }
  });

  it('does not turn null, blank, or an unknown code into D40', () => {
    for (const value of [null, undefined, '', '   ', 'D99', 'pothole']) {
      expect(statClassCode(value)).toBeNull();
      expect(statClassCode(value)).not.toBe('D40');
      expect(displayClassCode(value)).toBe(UNKNOWN_CLASS_LABEL);
    }
  });

  it('reads the stored class and does not invent one', () => {
    expect(observationClassCode(null)).toBeNull();
    expect(observationClassCode({})).toBeNull();
    expect(observationClassCode({ detections: [{}] })).toBeNull();
    expect(observationClassCode({ anomaly_type: 'D10' })).toBe('D10');
    expect(observationClassCode({ detections: [{ class_code: 'D99' }] })).toBe('D99');
  });
});
