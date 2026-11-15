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
  Moon,
  Sun,
  X,
} from 'lucide-react';
const PERIODS = [
  { id: 'today', fr: "Aujourd'hui", en: 'Today' },
  { id: '7d', fr: '7 jours', en: '7 days' },
  { id: '30d', fr: '30 jours', en: '30 days' },
  { id: '90d', fr: '90 jours', en: '90 days' },
  { id: 'year', fr: 'Cette année', en: 'This year' },
  { id: 'all', fr: 'Historique complet', en: 'All time' },
];

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
  exportDisabled = false,
  currentUser,
  isAuthorityUser,
  onOpenLogin,
  lang = 'fr',
  theme = 'light',
  onToggleTheme,
  period = 'all',
  onPeriodChange,
}) {
  return (
    <header className="tm-topbar" data-view={activeNavTab || 'overview'}>
      <div className="tm-topbar-left">
        <button
          type="button"
          className="tm-btn-icon tm-hamburger-btn show-on-mobile"
          onClick={onOpenMobileSidebar}
          aria-label="Ouvrir le menu"
        >
          <Menu size={18} />
        </button>

        <p className="tm-topbar-tagline">
          {lang === 'fr'
            ? 'Des données fiables pour des décisions éclairées'
            : 'Reliable data for informed decisions'}
        </p>
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
        <label className="tm-period">
          <span className="hide-on-mobile">
            {lang === 'fr' ? 'Période' : 'Period'}
          </span>
          <select
            className="tm-period-select"
            value={period || 'all'}
            aria-label={lang === 'fr' ? 'Période' : 'Period'}
            onChange={(event) => onPeriodChange && onPeriodChange(event.target.value)}
          >
            {PERIODS.map((item) => (
              <option key={item.id} value={item.id}>
                {lang === 'fr' ? item.fr : item.en}
              </option>
            ))}
          </select>
        </label>
        <button
          type="button"
          className="btn btn-secondary tm-btn-theme"
          onClick={onToggleTheme}
          aria-pressed={theme === 'dark'}
          aria-label={theme === 'dark'
            ? (lang === 'fr' ? 'Mode clair' : 'Light mode')
            : (lang === 'fr' ? 'Mode sombre' : 'Dark mode')}
          title={theme === 'dark'
            ? (lang === 'fr' ? 'Mode clair' : 'Light mode')
            : (lang === 'fr' ? 'Mode sombre' : 'Dark mode')}
        >
          {theme === 'dark' ? <Sun size={14} /> : <Moon size={14} />}
          <span className="hide-on-tablet">
            {theme === 'dark'
              ? (lang === 'fr' ? 'Mode clair' : 'Light mode')
              : (lang === 'fr' ? 'Mode sombre' : 'Dark mode')}
          </span>
        </button>

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
            title={lang === 'fr'
              ? 'Précision et mAP non disponibles : pas d’évaluation étiquetée dans ce dépôt'
              : 'Precision and mAP are not available: no labeled eval in this repo'}
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
            disabled={exportDisabled}
            title={exportDisabled
              ? (lang === 'fr' ? 'Indisponible' : 'Unavailable')
              : (lang === 'fr' ? 'Exporter en CSV' : 'Export to CSV')}
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
