/**
 * Export Formatters: CSV, Excel TSV, and Standard GeoJSON for GIS Tools.
 */

import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import { displayClassCode, observationClassCode, statClassCode, UNKNOWN_CLASS_LABEL } from './classCodes';
import { resolveTunisiaAdmin } from './tunisiaGeo';

/**
 * Builds formatted data rows from observations.
 */
export function buildExportRows(observations) {
  return (observations || []).map((obs) => {
    const geo = resolveTunisiaAdmin(obs.latitude, obs.longitude);
    const cls = statClassCode(observationClassCode(obs));
    const typeLabel = cls ? (DAMAGE_CLASSES[cls]?.fr || cls) : UNKNOWN_CLASS_LABEL;
    const statusLabel = STATUS_LABELS[obs.status]?.fr || obs.status || 'Non confirmé';
    const cost = cls ? DAMAGE_CLASSES[cls]?.defaultCostTnd ?? null : null;

    return {
      id: obs.id,
      date: new Date(obs.created_at || obs.captured_at || Date.now()).toISOString(),
      classCode: cls ? displayClassCode(cls) : UNKNOWN_CLASS_LABEL,
      typeLabel,
      priorityLabel: obs.priority_label ? String(obs.priority_label).toUpperCase() : '',
      priorityScore: Number.isFinite(Number(obs.priority_score)) ? Number(obs.priority_score).toFixed(1) : '',
      status: statusLabel,
      governorate: geo.governorate,
      municipality: geo.municipality,
      roadSegment: geo.roadSegment,
      latitude: Number(obs.latitude).toFixed(6),
      longitude: Number(obs.longitude).toFixed(6),
      accuracyMeters: obs.accuracy_meters ? Number(obs.accuracy_meters).toFixed(1) : 'N/A',
      estimatedCostTnd: cost,
      assignedTo: obs.assigned_to || 'Non assigné',
      dueDate: obs.due_date || 'Non définie',
      isDemo: obs.is_demo ? 'OUI' : 'NON',
    };
  });
}

/**
 * Generates CSV string with UTF-8 BOM for Microsoft Excel compatibility.
 */
export function generateCsvString(observations) {
  const rows = buildExportRows(observations);
  const headers = [
    'ID Signalement',
    'Date de détection',
    'Code Dégradation',
    'Type d\'anomalie',
    'Priorité',
    'Score Priorité',
    'Statut',
    'Gouvernorat',
    'Commune / Municipalité',
    'Axe / Tronçon',
    'Latitude',
    'Longitude',
    'Précision GPS (m)',
    'Coût estimé (TND)',
    'Assigné à',
    'Date limite',
    'Enregistrement Démo',
  ];

  const escapeCsv = (val) => {
    const s = String(val ?? '');
    if (s.includes(',') || s.includes('"') || s.includes('\n')) {
      return `"${s.replace(/"/g, '""')}"`;
    }
    return s;
  };

  const csvLines = [headers.join(',')];
  rows.forEach((r) => {
    csvLines.push(
      [
        escapeCsv(r.id),
        escapeCsv(r.date),
        escapeCsv(r.classCode),
        escapeCsv(r.typeLabel),
        escapeCsv(r.priorityLabel),
        escapeCsv(r.priorityScore),
        escapeCsv(r.status),
        escapeCsv(r.governorate),
        escapeCsv(r.municipality),
        escapeCsv(r.roadSegment),
        escapeCsv(r.latitude),
        escapeCsv(r.longitude),
        escapeCsv(r.accuracyMeters),
        escapeCsv(r.estimatedCostTnd),
        escapeCsv(r.assignedTo),
        escapeCsv(r.dueDate),
        escapeCsv(r.isDemo),
      ].join(',')
    );
  });

  // Prepend UTF-8 Byte Order Mark (BOM)
  return '\uFEFF' + csvLines.join('\r\n');
}

/**
 * Generates standard GeoJSON FeatureCollection for QGIS / ArcGIS.
 */
export function generateGeoJson(observations) {
  const rows = buildExportRows(observations);

  const features = rows
    .filter((r) => Number.isFinite(Number(r.latitude)) && Number.isFinite(Number(r.longitude)))
    .map((r) => ({
      type: 'Feature',
      geometry: {
        type: 'Point',
        coordinates: [Number(r.longitude), Number(r.latitude)],
      },
      properties: {
        id: r.id,
        created_at: r.date,
        class_code: r.classCode,
        defect_type: r.typeLabel,
        priority: r.priorityLabel,
        priority_score: r.priorityScore === '' ? null : Number(r.priorityScore),
        status: r.status,
        governorate: r.governorate,
        municipality: r.municipality,
        road_segment: r.roadSegment,
        accuracy_meters: r.accuracyMeters === 'N/A' ? null : Number(r.accuracyMeters),
        estimated_cost_tnd: r.estimatedCostTnd,
        assigned_to: r.assignedTo,
        due_date: r.dueDate === 'Non définie' ? null : r.dueDate,
        is_demo: r.isDemo === 'OUI',
      },
    }));

  return {
    type: 'FeatureCollection',
    metadata: {
      generated_at: new Date().toISOString(),
      platform: 'TariqMap Ministry Command Center',
      feature_count: features.length,
    },
    features,
  };
}

/**
 * Browser download trigger.
 */
export function downloadFile(content, filename, mimeType) {
  if (typeof window === 'undefined') return;
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/**
 * Triggers browser download of CSV.
 */
export function exportToCsv(observations, filename = 'tariqmap-export.csv') {
  const csv = generateCsvString(observations);
  downloadFile(csv, filename, 'text/csv;charset=utf-8;');
}

/**
 * Triggers browser download of Excel TSV.
 */
export function exportToExcelTsv(observations, filename = 'tariqmap-export.tsv') {
  const rows = buildExportRows(observations);
  const headers = [
    'ID', 'Date', 'Code', 'Type', 'Priorité', 'Score', 'Statut',
    'Gouvernorat', 'Commune', 'Axe', 'Latitude', 'Longitude',
    'Précision (m)', 'Coût (TND)', 'Assigné', 'Date limite', 'Démo'
  ];
  const tsvLines = [headers.join('\t')];
  rows.forEach((r) => {
    tsvLines.push([
      r.id, r.date, r.classCode, r.typeLabel, r.priorityLabel, r.priorityScore,
      r.status, r.governorate, r.municipality, r.roadSegment, r.latitude,
      r.longitude, r.accuracyMeters, r.estimatedCostTnd, r.assignedTo, r.dueDate, r.isDemo
    ].join('\t'));
  });
  downloadFile('\uFEFF' + tsvLines.join('\r\n'), filename, 'text/tab-separated-values;charset=utf-8;');
}

/**
 * Triggers browser download of GeoJSON.
 */
export function exportToGeoJson(observations, filename = 'tariqmap-sig.geojson') {
  const geojson = generateGeoJson(observations);
  downloadFile(JSON.stringify(geojson, null, 2), filename, 'application/geo+json;charset=utf-8;');
}
