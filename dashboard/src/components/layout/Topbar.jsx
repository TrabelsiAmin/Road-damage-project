import React from 'react';
import {
  Menu,
  Search,
  RotateCcw,
  BarChart3,
  FileSpreadsheet,
  AlertTriangle,
  ShieldCheck,
  ShieldAlert,
  LogIn,
  X,
} from 'lucide-react';
import { Breadcrumbs } from './Breadcrumbs';

export function Topbar({
  activeNavTab,
  onOpenMobileSidebar,
  searchQuery = '',
  onSearchChange,
  loading = false,
  isRefreshing = false,
  onRefresh,
  lastUpdated,
  hasDemoData = false,
  onOpenMetrics,
  onExportCsv,
  currentUser,
  isAuthorityUser,
  onOpenLogin,
  lang = 'fr',
}) {
  const titles = {
    overview: { fr: 'Vue d’ensemble', en: 'Executive Overview' },
    action_center: { fr: 'Centre d’opérations', en: 'Operations Action Center' },
    gis_map: { fr: 'Carte SIG & Dégradations', en: 'Geographic Intelligence & GIS' },
    road_segments: { fr: 'Risque par tronçon', en: 'Road Segment Risk Matrix' },
    analytics: { fr: 'Analytique & tendances', en: 'Analytics & Trends' },
    data_quality: { fr: 'Qualité & modèle IA', en: 'Data Quality & AI Telemetry' },
    reports: { fr: 'Rapports & exports', en: 'Official Reports & Exports' },
    audit: { fr: 'Journal d’audit', en: 'Governance & Audit Trail' },
  };

  const currentTitle = titles[activeNavTab]
    ? (lang === 'fr' ? titles[activeNavTab].fr : titles[activeNavTab].en)
    : 'TariqMap';

  const breadcrumbs = [
    { label: 'TariqMap', onClick: () => {} },
    { label: currentTitle },
  ];

  return (
    <header className="tm-topbar">
      {/* Left side: Hamburger button + Breadcrumbs / Page Title */}
      <div className="tm-topbar-left">
        <button
          type="button"
          className="tm-btn-icon tm-hamburger-btn show-on-mobile"
          onClick={onOpenMobileSidebar}
          aria-label="Ouvrir le menu"
        >
          <Menu size={18} />
        </button>

        <div className="tm-topbar-context">
          <Breadcrumbs items={breadcrumbs} />
          <h2 className="tm-topbar-page-title">{currentTitle}</h2>
        </div>
      </div>

      {/* Center: Search Box */}
      <div className="tm-topbar-center hide-on-mobile">
        <div className="tm-search-box">
          <Search size={14} className="tm-search-icon" />
          <input
            type="search"
            className="tm-search-input"
            placeholder={
              lang === 'fr'
                ? 'Rechercher un signalement, code, commune...'
                : 'Search anomalies, codes, municipalities...'
            }
            value={searchQuery}
            onChange={(e) => onSearchChange && onSearchChange(e.target.value)}
          />
          {searchQuery && (
            <button
              type="button"
              className="tm-search-clear"
              onClick={() => onSearchChange && onSearchChange('')}
              aria-label="Effacer la recherche"
            >
              <X size={12} />
            </button>
          )}
        </div>
      </div>

      {/* Right side: Actions & Status */}
      <div className="tm-topbar-right">
        {/* Demo Data Indicator */}
        {hasDemoData && (
          <div
            className="tm-demo-pill"
            title={
              lang === 'fr'
                ? 'Observations synthétiques sur les axes tunisiens. Montants estimés.'
                : 'Synthetic demo observations on Tunisian corridors.'
            }
          >
            <AlertTriangle size={13} className="tm-demo-pill-icon" />
            <span className="tm-demo-pill-text">
              {lang === 'fr' ? 'DONNÉES DE DÉMO' : 'DEMO DATA'}
            </span>
          </div>
        )}

        {/* Refresh Action */}
        <div className="tm-refresh-group">
          <button
            type="button"
            className="btn btn-secondary tm-btn-refresh"
            onClick={onRefresh}
            disabled={loading || isRefreshing}
            title={lang === 'fr' ? 'Actualiser les données' : 'Refresh data'}
          >
            <RotateCcw
              size={13}
              className={loading || isRefreshing ? 'spin-animation' : ''}
            />
            <span className="hide-on-tablet">
              {loading || isRefreshing
                ? (lang === 'fr' ? 'Actualisation...' : 'Refreshing...')
                : (lang === 'fr' ? 'Actualiser' : 'Refresh')}
            </span>
          </button>
          {lastUpdated && (
            <span className="tm-timestamp-text hide-on-tablet">
              {lastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
            </span>
          )}
        </div>

        {/* AI Metrics Button */}
        {onOpenMetrics && (
          <button
            type="button"
            className="btn btn-secondary tm-btn-metrics hide-on-tablet"
            onClick={onOpenMetrics}
            title="Consulter les métriques de validation du modèle IA"
          >
            <BarChart3 size={14} color="var(--tm-primary)" />
            <span>{lang === 'fr' ? 'Métriques IA' : 'AI Metrics'}</span>
          </button>
        )}

        {/* Export CSV Button */}
        {onExportCsv && (
          <button
            type="button"
            className="btn btn-secondary tm-btn-export hide-on-mobile"
            onClick={onExportCsv}
            title={lang === 'fr' ? 'Exporter en CSV' : 'Export to CSV'}
          >
            <FileSpreadsheet size={14} />
            <span className="hide-on-tablet">CSV</span>
          </button>
        )}

        {/* Compact User / Authority Status for Topbar (especially visible when sidebar collapsed) */}
        {currentUser ? (
          <div
            className={`tm-topbar-auth-chip ${
              isAuthorityUser ? 'tm-chip-authority' : 'tm-chip-public'
            }`}
            title={currentUser.email}
          >
            {isAuthorityUser ? (
              <ShieldCheck size={14} color="#10B981" />
            ) : (
              <ShieldAlert size={14} color="#F59E0B" />
            )}
            <span className="hide-on-mobile tm-chip-label">
              {isAuthorityUser ? 'AUTORITÉ' : 'INVITÉ'}
            </span>
          </div>
        ) : (
          <button
            type="button"
            className="btn btn-primary tm-topbar-login-btn"
            onClick={onOpenLogin}
          >
            <LogIn size={13} />
            <span className="hide-on-mobile">Connexion</span>
          </button>
        )}
      </div>
    </header>
  );
}
