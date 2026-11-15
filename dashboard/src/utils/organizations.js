/**
 * Organization choices come from rows already stored in the database.
 * Rows without an id and a name are dropped. Nothing is invented here.
 */
export function usableOrganizations(rows) {
  if (!Array.isArray(rows)) return [];
  const seen = new Set();
  const result = [];
  for (const row of rows) {
    const id = typeof row?.id === 'string' ? row.id.trim() : '';
    const name = typeof row?.name === 'string' ? row.name.trim() : '';
    if (!id || !name || seen.has(id)) continue;
    seen.add(id);
    result.push({
      id,
      name,
      typeCode: typeof row.type_code === 'string' ? row.type_code : null,
    });
  }
  return result;
}
