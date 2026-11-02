import React from 'react';
import {
  FileSpreadsheet,
  Printer,
  Download,
  Share2,
  MapPin,
  CheckCircle2,
  FileText,
  Table,
} from 'lucide-react';
import { exportToCsv, exportToExcelTsv, exportToGeoJson } from '../utils/exportFormats';

export function ReportsExportsView({
  filteredObservations = [],
  kpis,
  filters,
  lang = 'fr',
}) {
  const handleExportCsv = () => {
    exportToCsv(filteredObservations, `tariqmap-rapport-${new Date().toISOString().slice(0, 10)}.csv`);
  };

  const handleExportExcel = () => {
    exportToExcelTsv(filteredObservations, `tariqmap-excel-${new Date().toISOString().slice(0, 10)}.tsv`);
  };

  const handleExportGeoJson = () => {
    exportToGeoJson(filteredObservations, `tariqmap-sig-${new Date().toISOString().slice(0, 10)}.geojson`);
  };

  const handlePrint = () => {
    window.print();
  };

  return (
    <div className="reports-exports-container">
      <div className="section-intro">
        <div className="intro-title-row">
          <FileSpreadsheet size={20} color="var(--color-primary)" />
          <div>
            <h2 style={{ fontSize: '1.1rem', fontWeight: 800 }}>
              {lang === 'fr' ? 'Rapports officiels, exports SIG et fiches d\'intervention' : 'Official Reports, GIS Exports & Work Orders'}
            </h2>
            <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '2px' }}>
              {lang === 'fr'
                ? 'Exportez les données filtrées au format standard compatible SIG (QGIS/ArcGIS), tableur ministériel ou imprimez la fiche de tournée pour les brigades de terrain.'
                : 'Export filtered datasets in GIS (GeoJSON), spreadsheet (CSV/TSV) or printable work order formats.'}
            </p>
          </div>
        </div>
      </div>

      <div className="export-cards-grid">
        {/* CSV Card */}
        <div className="export-card">
          <div className="export-card-icon" style={{ background: 'rgba(59, 130, 246, 0.1)', color: '#3B82F6' }}>
            <Table size={24} />
          </div>
          <h3 className="export-card-title">CSV Standard (BOM UTF-8)</h3>
          <p className="export-card-desc">
            {lang === 'fr'
              ? 'Export complet avec délimiteur point-virgule et BOM UTF-8 pour ouverture directe sous Excel sans corruption d\'accents.'
              : 'Standard semicolon CSV with UTF-8 BOM for Microsoft Excel.'}
          </p>
          <div className="export-card-meta">
            <span>{filteredObservations.length} {lang === 'fr' ? 'lignes filtrées' : 'filtered rows'}</span>
          </div>
          <button type="button" className="btn btn-secondary btn-export-action" onClick={handleExportCsv}>
            <Download size={14} />
            <span>{lang === 'fr' ? 'Télécharger CSV' : 'Download CSV'}</span>
          </button>
        </div>

        {/* Excel TSV Card */}
        <div className="export-card">
          <div className="export-card-icon" style={{ background: 'rgba(16, 185, 129, 0.1)', color: '#10B981' }}>
            <FileSpreadsheet size={24} />
          </div>
          <h3 className="export-card-title">Excel (.tsv) Natif</h3>
          <p className="export-card-desc">
            {lang === 'fr'
              ? 'Tableur tabulé structuré avec colonnes formatées : montants budgétaires, dates ISO et classifications de dégradations.'
              : 'Tab-separated spreadsheet natively parsed by Microsoft Excel.'}
          </p>
          <div className="export-card-meta">
            <span>{filteredObservations.length} {lang === 'fr' ? 'enregistrements' : 'records'}</span>
          </div>
          <button type="button" className="btn btn-secondary btn-export-action" onClick={handleExportExcel}>
            <Download size={14} />
            <span>{lang === 'fr' ? 'Télécharger TSV' : 'Download TSV'}</span>
          </button>
        </div>

        {/* GeoJSON Card */}
        <div className="export-card">
          <div className="export-card-icon" style={{ background: 'rgba(139, 92, 246, 0.1)', color: '#8B5CF6' }}>
            <MapPin size={24} />
          </div>
          <h3 className="export-card-title">GeoJSON SIG (QGIS / ArcGIS)</h3>
          <p className="export-card-desc">
            {lang === 'fr'
              ? 'FeatureCollection géospatiale standard WGS84 avec coordonnées ponctuelles [lng, lat] et métadonnées d\'inspection pour logiciels SIG.'
              : 'Standard GeoJSON FeatureCollection with Point geometry for QGIS and ArcGIS.'}
          </p>
          <div className="export-card-meta">
            <span>{filteredObservations.length} {lang === 'fr' ? 'features spatiales' : 'spatial features'}</span>
          </div>
          <button type="button" className="btn btn-secondary btn-export-action" onClick={handleExportGeoJson}>
            <Download size={14} />
            <span>{lang === 'fr' ? 'Télécharger GeoJSON' : 'Download GeoJSON'}</span>
          </button>
        </div>

        {/* Work Order Print Card */}
        <div className="export-card">
          <div className="export-card-icon" style={{ background: 'rgba(245, 158, 11, 0.1)', color: '#F59E0B' }}>
            <Printer size={24} />
          </div>
          <h3 className="export-card-title">Fiche de tournée d'intervention</h3>
          <p className="export-card-desc">
            {lang === 'fr'
              ? 'Mise en page optimisée pour impression ou export PDF destinée aux chefs de chantier et conducteurs de travaux.'
              : 'Print-optimized operational work order sheet for maintenance teams.'}
          </p>
          <div className="export-card-meta">
            <span>{lang === 'fr' ? 'Format A4 Paysage / Portrait' : 'A4 Layout'}</span>
          </div>
          <button type="button" className="btn btn-primary btn-export-action" onClick={handlePrint}>
            <Printer size={14} />
            <span>{lang === 'fr' ? 'Imprimer / Exporter PDF' : 'Print / Export PDF'}</span>
          </button>
        </div>
      </div>

      {/* Printable Preview Section */}
      <div className="print-work-order-preview">
        <div className="work-order-header">
          <div className="wo-title-block">
            <h3 style={{ fontSize: '1.2rem', fontWeight: 900, textTransform: 'uppercase' }}>
              RÉPUBLIQUE TUNISIENNE — MINISTÈRE DE L'ÉQUIPEMENT ET DE L'HABITAT
            </h3>
            <h4 style={{ fontSize: '0.95rem', fontWeight: 700, color: 'var(--text-muted)' }}>
              Direction Générale des Ponts et Chaussées • Plateforme TariqMap
            </h4>
            <div style={{ fontSize: '0.8rem', marginTop: '4px', color: 'var(--text-dim)' }}>
              Ordre de mission et fiche de tournée d'intervention — Émis le {new Date().toLocaleDateString('fr-TN')}
            </div>
          </div>

          <div className="wo-kpis-summary">
            <div className="wo-kpi">
              <span className="wo-kpi-label">Anomalies ciblées</span>
              <strong className="wo-kpi-val">{filteredObservations.length}</strong>
            </div>
            <div className="wo-kpi">
              <span className="wo-kpi-label">Cas critiques</span>
              <strong className="wo-kpi-val" style={{ color: '#EF4444' }}>{kpis.criticalAnomalies}</strong>
            </div>
            <div className="wo-kpi">
              <span className="wo-kpi-label">Budget prévisionnel</span>
              <strong className="wo-kpi-val">{(kpis.estimatedBudgetTnd || 0).toLocaleString()} DT</strong>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
