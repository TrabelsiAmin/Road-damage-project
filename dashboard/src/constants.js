// TariqMap Authority Dashboard Constants & Translations

export const DAMAGE_CLASSES = {
  D40: {
    code: 'D40',
    en: 'Pothole',
    fr: 'Nid-de-poule',
    color: '#EF4444', // Red
    bgLight: 'rgba(239, 68, 68, 0.15)',
    weight: 1.0,
    defaultCostTnd: 280, // Average cost in Tunisian Dinars to mill & asphalt fill a pothole
  },
  D20: {
    code: 'D20',
    en: 'Alligator Crack',
    fr: 'Faïençage (Fatigue)',
    color: '#F97316', // Orange
    bgLight: 'rgba(249, 115, 22, 0.15)',
    weight: 0.9,
    defaultCostTnd: 450, // Resurfacing / seal-coating patch
  },
  D00: {
    code: 'D00',
    en: 'Longitudinal Crack',
    fr: 'Fissure longitudinale',
    color: '#3B82F6', // Blue
    bgLight: 'rgba(59, 130, 246, 0.15)',
    weight: 0.7,
    defaultCostTnd: 120, // Crack sealing
  },
  D10: {
    code: 'D10',
    en: 'Transverse Crack',
    fr: 'Fissure transversale',
    color: '#10B981', // Emerald
    bgLight: 'rgba(16, 185, 129, 0.15)',
    weight: 0.7,
    defaultCostTnd: 120, // Crack sealing
  },
};

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
    demoBanner: 'DEMO DATA ACTIVE — Generated synthetic observations around Tunisian test corridors. Values labeled estimates.',
    filterClass: 'Damage Type',
    filterSeverity: 'Priority Level',
    filterStatus: 'Workflow Status',
    all: 'All',
    totalDefects: 'Detected Defects',
    criticalCount: 'Critical Safety Hazards',
    healthScore: 'Road Health Index',
    healthTooltip: 'Index = 100 - (Sum of defect severity weights per km / baseline). 100 = Perfect road.',
    priorityRankedList: 'Ranked Work Order Queue',
    budgetOptimizer: 'Budget & Triage Optimizer',
    exportCsv: 'Export CSV',
    printWorkOrder: 'Print Work Order',
    accountability: 'Accountability & Repair Cycle',
    repairCycleNote: 'Phase 3 Verification loop active: 0 verified passes logged in test session.',
    switchLang: 'Français',
    budgetInput: 'Available Municipal Budget (TND)',
    estimatedCost: 'Est. Fix Cost',
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
    demoBanner: 'DONNÉES DE DÉMO — Observations synthétiques sur les axes tunisiens. Montants estimés.',
    filterClass: 'Type d\'anomalie',
    filterSeverity: 'Niveau de priorité',
    filterStatus: 'Statut des travaux',
    all: 'Tous',
    totalDefects: 'Anomalies détectées',
    criticalCount: 'Dangers critiques',
    healthScore: 'Indice de Santé Routière',
    healthTooltip: 'Indice = 100 - (Somme pondérée des sévérités par km / référence). 100 = Route neuve.',
    priorityRankedList: 'File des Travaux Prioritaires',
    budgetOptimizer: 'Optimisation Budgétaire & Arbitrage',
    exportCsv: 'Exporter CSV',
    printWorkOrder: 'Imprimer Ordre de Travail',
    accountability: 'Délai d\'Intervention & Audit',
    repairCycleNote: 'Boucle de vérification Phase 3 : 0 passage de contrôle enregistré en session test.',
    switchLang: 'English',
    budgetInput: 'Budget Municipal Disponible (TND)',
    estimatedCost: 'Coût Estimé',
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

