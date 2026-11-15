import { describe, expect, it } from 'vitest';
import { usableOrganizations } from './organizations';

describe('usableOrganizations', () => {
  it('keeps only rows that already have an id and a name', () => {
    const rows = usableOrganizations([
      { id: 'org-ministry', name: ' Ministère ', type_code: 'ministry' },
      { id: '', name: 'Sans identifiant' },
      { id: 'org-blank', name: '   ' },
      { name: 'Sans id' },
      null,
    ]);
    expect(rows).toEqual([
      { id: 'org-ministry', name: 'Ministère', typeCode: 'ministry' },
    ]);
  });

  it('returns an empty list instead of substitute organizations', () => {
    expect(usableOrganizations(null)).toEqual([]);
    expect(usableOrganizations([])).toEqual([]);
  });
});
