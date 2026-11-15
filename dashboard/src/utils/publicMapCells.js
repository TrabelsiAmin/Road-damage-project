/**
 * Coarse public map cells. A cell center is not a measured GPS point.
 * Demonstrations and rejected reports stay off this grid.
 * The result has no observation id and no original coordinate.
 */

const MIN_CELL_DEGREES = 0.01;

export function publicCellSize(cellDegrees = MIN_CELL_DEGREES) {
  const size = Number(cellDegrees);
  if (!Number.isFinite(size) || size < MIN_CELL_DEGREES) return MIN_CELL_DEGREES;
  return size;
}

function cellCenter(value, size) {
  const scaled = Number(value) / size;
  const index = Math.floor(scaled + 1e-8);
  return Math.round((index + 0.5) * size * 1e6) / 1e6;
}

/**
 * A catalogue point can sit on the public grid.
 * Demonstrations, rejections, and missing coordinates stay out.
 * The test is the same one that produces the map caption count.
 */
export function isCatalogueMapPoint(point) {
  if (point?.is_demo !== false) return false;
  if (point?.status === 'rejected') return false;
  const latitude = Number(point?.latitude);
  const longitude = Number(point?.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return false;
  if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return false;
  if (latitude === 0 && longitude === 0) return false;
  return true;
}

export function catalogueReportCount(cells) {
  if (!Array.isArray(cells) || cells.length === 0) return null;
  const total = cells.reduce((sum, cell) => sum + (Number(cell?.report_count) || 0), 0);
  return total > 0 ? total : null;
}

/**
 * Class totals for the same points that become cells.
 * No observation id and no coordinate is returned.
 */
export function catalogueVisibleStats(points) {
  const classCounts = new Map();
  let reports = 0;
  for (const point of points || []) {
    if (!isCatalogueMapPoint(point)) continue;
    reports += 1;
    const code = point?.anomaly_type == null ? null : String(point.anomaly_type);
    classCounts.set(code, (classCounts.get(code) || 0) + 1);
  }
  return {
    reports,
    classes: [...classCounts.entries()].map(([anomaly_type, count]) => ({ anomaly_type, count })),
  };
}

/**
 * Keeps the wider visible catalogue. A later empty or shorter fetch
 * must not wipe a count the screen has already shown.
 */
export function preferWiderCells(currentCells, nextCells) {
  const currentCount = catalogueReportCount(currentCells) || 0;
  const nextCount = catalogueReportCount(nextCells) || 0;
  if (nextCount < currentCount) return currentCells || [];
  return nextCells || [];
}

function classRank(left, right) {
  const leftName = left[0] == null ? '\uffff' : String(left[0]);
  const rightName = right[0] == null ? '\uffff' : String(right[0]);
  return leftName.localeCompare(rightName);
}

/**
 * @param {Array<object>} points joined catalogue rows, already without ids
 * @returns {Array<{cell_lat:number, cell_lng:number, report_count:number, dominant_class:string|null}>}
 */
export function aggregatePublicMapCells(points, cellDegrees = MIN_CELL_DEGREES) {
  const size = publicCellSize(cellDegrees);
  const cells = new Map();
  for (const point of points || []) {
    if (!isCatalogueMapPoint(point)) continue;
    const latitude = Number(point.latitude);
    const longitude = Number(point.longitude);
    const cellLat = cellCenter(latitude, size);
    const cellLng = cellCenter(longitude, size);
    const key = `${cellLat}|${cellLng}`;
    let bucket = cells.get(key);
    if (!bucket) {
      bucket = {
        cell_lat: cellLat,
        cell_lng: cellLng,
        report_count: 0,
        classes: new Map(),
      };
      cells.set(key, bucket);
    }
    bucket.report_count += 1;
    const code = point?.anomaly_type == null ? null : String(point.anomaly_type);
    bucket.classes.set(code, (bucket.classes.get(code) || 0) + 1);
  }

  return [...cells.values()]
    .map((bucket) => {
      const ranked = [...bucket.classes.entries()].sort((left, right) => {
        if (right[1] !== left[1]) return right[1] - left[1];
        return classRank(left, right);
      });
      return {
        cell_lat: bucket.cell_lat,
        cell_lng: bucket.cell_lng,
        report_count: bucket.report_count,
        dominant_class: ranked[0] ? ranked[0][0] : null,
      };
    })
    .sort((left, right) => right.report_count - left.report_count
      || left.cell_lat - right.cell_lat
      || left.cell_lng - right.cell_lng);
}

export function catalogueMapNote({ cells = 0, reports = 0, lang = 'fr' } = {}) {
  const cellCount = Math.max(0, Number(cells) || 0);
  const reportCount = Math.max(0, Number(reports) || 0);
  if (lang === 'fr') {
    const cellWord = cellCount > 1 ? 'mailles' : 'maille';
    const reportWord = reportCount > 1 ? 'signalements réels' : 'signalement réel';
    return `${reportCount} ${reportWord} regroupés en ${cellCount} ${cellWord} d’environ 1 km, d’après le catalogue visible (hors démonstration et hors rejets). Le total public officiel est indisponible (HTTP 404).`;
  }
  const cellWord = cellCount === 1 ? 'cell' : 'cells';
  const reportWord = reportCount === 1 ? 'real report' : 'real reports';
  return `${reportCount} ${reportWord} grouped into ${cellCount} roughly 1 km ${cellWord} from the visible catalogue (demonstrations and rejections excluded). The official public total is unavailable (HTTP 404).`;
}
