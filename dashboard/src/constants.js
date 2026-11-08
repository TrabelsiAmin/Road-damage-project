// TariqMap Authority Dashboard Constants & Translations

// Stored RDD-style codes only. Common names are not verified and are not shown.
export const DAMAGE_CLASSES = {
  D40: {
    code: 'D40',
    color: '#EF4444',
    bgLight: 'rgba(239, 68, 68, 0.15)',
    weight: 1.0,
  },
  D20: {
    code: 'D20',
    color: '#F97316',
    bgLight: 'rgba(249, 115, 22, 0.15)',
    weight: 0.9,
  },
  D00: {
    code: 'D00',
    color: '#3B82F6',
    bgLight: 'rgba(59, 130, 246, 0.15)',
    weight: 0.7,
  },
  D10: {
    code: 'D10',
    color: '#10B981',
    bgLight: 'rgba(16, 185, 129, 0.15)',
    weight: 0.7,
  },
};

/** No cited repair-cost survey is in this repo. Do not display a TND amount. */
export const REPAIR_COST_STATUS = 'unavailable';
export const REPAIR_COST_UNIT = 'TND';

export function repairCostText(lang = 'fr') {
  return lang === 'fr' ? 'Indisponible' : 'Unavailable';
}

export const SEVERITY_COLORS = {
  CRITICAL: { color: '#EF4444', label: 'Critical', fr: 'Critique' },
  HIGH: { color: '#F97316', label: 'High', fr: 'Élevé' },
  MEDIUM: { color: '#EAB308', label: 'Medium', fr: 'Moyen' },
  LOW: { color: '#3B82F6', label: 'Low', fr: 'Faible' },
};

export const STATUS_LABELS = {
  unconfirmed: { en: 'Unconfirmed', fr: 'Non confirmé', badge: 'badge-gray' },
  confirmed: { en: 'Confirmed', fr: 'Confirmé', badge: 'badge-amber' },
  in_progress: { en: 'In progress', fr: 'En cours', badge: 'badge-blue' },
  scheduled: { en: 'Work Scheduled', fr: 'Planifié', badge: 'badge-blue' },
  repaired: { en: 'Repaired', fr: 'Réparé', badge: 'badge-emerald' },
  verified: { en: 'Verified by Pass', fr: 'Vérifié', badge: 'badge-green' },
  rejected: { en: 'Rejected', fr: 'Rejeté', badge: 'badge-dark' },
  dismissed: { en: 'Dismissed', fr: 'Rejeté', badge: 'badge-dark' },
};

export const I18N = {
  en: {
    title: 'Road Infrastructure Overview',
    subtitle: 'Ministry road condition, critical damage, and repair follow-up',
    demoBanner: 'DEMO DATA ACTIVE — Generated synthetic observations around Tunisian test corridors.',
    filterClass: 'Damage Type',
    filterSeverity: 'Priority Level',
    filterStatus: 'Workflow Status',
    all: 'All',
    totalDefects: 'Detected Defects',
    criticalCount: 'Critical Safety Hazards',
    healthScore: 'Road Health Index',
    healthTooltip: 'Road health index: unavailable. No measured index is stored.',
    priorityRankedList: 'Ranked Work Order Queue',
    budgetOptimizer: 'Budget & Triage Optimizer',
    exportCsv: 'Export CSV',
    printWorkOrder: 'Print Work Order',
    accountability: 'Accountability & Repair Cycle',
    repairCycleNote: 'Verified repair passes: unavailable.',
    switchLang: 'Français',
    budgetInput: 'Available Municipal Budget (TND)',
    estimatedCost: 'Repair cost (unavailable)',
    cumulativeCost: 'Cumulative Allocation',
    workOrderTitle: 'MUNICIPAL ROAD REPAIR WORK ORDER',
    issuedTo: 'Responsible Contractor / Service',
    gpsCoords: 'Coordinates (WGS84)',
    defectType: 'Identified Anomaly',
    reportedDate: 'First Detected',
    sightings: 'Confirmed Passes',
    confirmStatus: 'Update Status',
    close: 'Close',
  },
  fr: {
    title: 'Infrastructure routière',
    subtitle: 'État du réseau, dangers critiques et suivi des réparations',
    demoBanner: 'DONNÉES DE DÉMO — Observations synthétiques sur les axes tunisiens.',
    filterClass: 'Type d\'anomalie',
    filterSeverity: 'Niveau de priorité',
    filterStatus: 'Statut des travaux',
    all: 'Tous',
    totalDefects: 'Anomalies détectées',
    criticalCount: 'Dangers critiques',
    healthScore: 'Indice de Santé Routière',
    healthTooltip: 'Indice de santé routière : indisponible. Aucun indice mesuré n’est enregistré.',
    priorityRankedList: 'File des Travaux Prioritaires',
    budgetOptimizer: 'Optimisation Budgétaire & Arbitrage',
    exportCsv: 'Exporter CSV',
    printWorkOrder: 'Imprimer Ordre de Travail',
    accountability: 'Délai d\'Intervention & Audit',
    repairCycleNote: 'Passages de contrôle vérifiés : indisponible.',
    switchLang: 'English',
    budgetInput: 'Budget Municipal Disponible (TND)',
    estimatedCost: 'Coût de réparation (indisponible)',
    cumulativeCost: 'Engagement Cumulé',
    workOrderTitle: 'ORDRE DE SERVICE - RÉPARATION VOIRIE',
    issuedTo: 'Direction Régionale de l\'Équipement / Commune',
    gpsCoords: 'Coordonnées GPS (WGS84)',
    defectType: 'Désordre Identifié',
    reportedDate: 'Signalé le',
    sightings: 'Passages confirmés',
    confirmStatus: 'Modifier Statut',
    close: 'Fermer',
  },
};

// ── Basemap Configuration (Standard OpenStreetMap with env overrides) ────────
export const DEFAULT_TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
export const DEFAULT_TILE_ATTRIBUTION = '© OpenStreetMap contributors';

export const MAP_CONFIG = {
  tileUrl: import.meta.env.VITE_TILE_URL || DEFAULT_TILE_URL,
  tileAttribution: import.meta.env.VITE_TILE_ATTRIBUTION || DEFAULT_TILE_ATTRIBUTION,
  maxZoom: 19,
};

