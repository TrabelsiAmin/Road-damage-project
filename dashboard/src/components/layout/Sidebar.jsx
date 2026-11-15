import React from 'react';
import {
  LayoutDashboard,
  AlertTriangle,
  Map,
  Sparkles,
  FileSpreadsheet,
  Route,
  TrendingUp,
  Cpu,
  History,
  ChevronLeft,
  ChevronRight,
  Shield,
  ShieldCheck,
  ShieldAlert,
  LogIn,
  LogOut,
  Globe,
  X,
} from 'lucide-react';

const PRIMARY_NAV = [
  { id: 'overview', fr: 'Tableau de bord', en: 'Dashboard', icon: LayoutDashboard },
  {
    id: 'action_center',
    fr: 'Incidents',
    en: 'Incidents',
    icon: AlertTriangle,
    badgeKey: 'critical',
    badgeVariant: 'critical',
  },
  {
    id: 'gis_map',
    fr: 'Cartographie',
    en: 'Map',
    icon: Map,
    badgeKey: 'clusters',
    badgeVariant: 'primary',
  },
  { id: 'assistant', fr: 'Assistant IA', en: 'AI assistant', icon: Sparkles },
  { id: 'reports', fr: 'Rapports & Synthèse', en: 'Reports & synthesis', icon: FileSpreadsheet },
];

const MORE_NAV = [
  { id: 'road_segments', fr: 'Risque par tronçon', en: 'Road segments', icon: Route },
  { id: 'analytics', fr: 'Analytique', en: 'Analytics', icon: TrendingUp },
  { id: 'data_quality', fr: 'Qualité du modèle', en: 'Model quality', icon: Cpu },
  { id: 'audit', fr: 'Journal d’audit', en: 'Audit trail', icon: History },
];

export const NAV_ITEMS = [...PRIMARY_NAV, ...MORE_NAV];

function NavList({ items, activeNavTab, lang, isCollapsed, counts, onNavigate }) {
  return (
    <ul className="tm-sidebar-list">
      {items.map((item) => {
        const Icon = item.icon;
        const isActive = activeNavTab === item.id;
        const label = lang === 'fr' ? item.fr : item.en;
        const badgeCount = item.badgeKey ? counts[item.badgeKey] : null;
        return (
          <li key={item.id} className="tm-sidebar-item">
            <button
              type="button"
              className={`tm-sidebar-link ${isActive ? 'active' : ''}`}
              onClick={() => onNavigate(item.id)}
              title={isCollapsed ? label : undefined}
              aria-current={isActive ? 'page' : undefined}
            >
              <Icon size={18} className="tm-sidebar-item-icon" />
              {!isCollapsed && <span className="tm-sidebar-item-label">{label}</span>}
              {badgeCount > 0 && (
                <span
                  className={`tm-sidebar-badge tm-badge-${item.badgeVariant || 'neutral'} ${isCollapsed ? 'tm-badge-dot-only' : ''}`}
                  title={`${badgeCount} ${label}`}
                >
                  {!isCollapsed && badgeCount}
                </span>
              )}
            </button>
          </li>
        );
      })}
    </ul>
  );
}

export function Sidebar({
  activeNavTab,
  onSelectNavTab,
  isCollapsed = false,
  onToggleCollapse,
  isMobileOpen = false,
  onCloseMobile,
  counts = {},
  currentUser,
  isAuthorityUser,
  onOpenLogin,
  onLogout,
  lang = 'fr',
  onToggleLang,
}) {
  const handleNavClick = (tabId) => {
    onSelectNavTab(tabId);
    if (isMobileOpen && onCloseMobile) onCloseMobile();
  };

  return (
    <>
      {isMobileOpen && (
        <div className="tm-sidebar-backdrop" onClick={onCloseMobile} aria-hidden="true" />
      )}

      <aside
        className={`tm-sidebar ${isCollapsed ? 'tm-sidebar-collapsed' : ''} ${isMobileOpen ? 'tm-sidebar-mobile-open' : ''}`}
        aria-label="Navigation principale"
      >
        <div className="tm-sidebar-header">
          <div className="tm-sidebar-brand" onClick={() => handleNavClick('overview')}>
            <div className="tm-sidebar-logo tm-sidebar-crest" aria-hidden="true">
              <Shield size={18} />
            </div>
            {!isCollapsed && (
              <div className="tm-sidebar-brand-text">
                <span className="tm-brand-name">
                  {lang === 'fr' ? 'Ministère de l’Équipement' : 'Ministry of Equipment'}
                </span>
                <span className="tm-brand-dept">TariqMap</span>
              </div>
            )}
          </div>

          {isMobileOpen && (
            <button type="button" className="tm-sidebar-close-mobile" onClick={onCloseMobile} aria-label="Fermer le menu">
              <X size={18} />
            </button>
          )}

          {!isMobileOpen && (
            <button
              type="button"
              className="tm-sidebar-toggle-btn hide-on-mobile"
              onClick={onToggleCollapse}
              title={isCollapsed ? 'Développer la barre latérale' : 'Réduire la barre latérale'}
              aria-label={isCollapsed ? 'Développer' : 'Réduire'}
            >
              {isCollapsed ? <ChevronRight size={15} /> : <ChevronLeft size={15} />}
            </button>
          )}
        </div>

        <nav className="tm-sidebar-nav">
          <NavList
            items={PRIMARY_NAV}
            activeNavTab={activeNavTab}
            lang={lang}
            isCollapsed={isCollapsed}
            counts={counts}
            onNavigate={handleNavClick}
          />
          {!isCollapsed && (
            <p className="tm-sidebar-section">{lang === 'fr' ? 'Autres vues' : 'More views'}</p>
          )}
          <NavList
            items={MORE_NAV}
            activeNavTab={activeNavTab}
            lang={lang}
            isCollapsed={isCollapsed}
            counts={counts}
            onNavigate={handleNavClick}
          />
        </nav>

        <div className="tm-sidebar-footer">
          <div className="tm-sidebar-user-section">
            {currentUser ? (
              <div
                className={`tm-sidebar-user-card ${isAuthorityUser ? 'tm-user-authority' : 'tm-user-standard'}`}
                title={currentUser.email}
              >
                <div className="tm-sidebar-user-avatar">
                  {isAuthorityUser ? (
                    <ShieldCheck size={16} className="tm-avatar-icon tm-icon-success" />
                  ) : (
                    <ShieldAlert size={16} className="tm-avatar-icon tm-icon-warning" />
                  )}
                </div>
                {!isCollapsed && (
                  <div className="tm-sidebar-user-info">
                    <span className="tm-user-role">{isAuthorityUser ? 'AUTORITÉ VOIRIE' : 'UTILISATEUR'}</span>
                    <span className="tm-user-email">{currentUser.email}</span>
                  </div>
                )}
                {!isCollapsed && (
                  <button type="button" className="tm-btn-ghost-icon tm-logout-btn" onClick={onLogout} title="Déconnexion" aria-label="Déconnexion">
                    <LogOut size={14} />
                  </button>
                )}
              </div>
            ) : (
              <button type="button" className="btn btn-primary tm-sidebar-login-btn" onClick={onOpenLogin} title="Connexion Autorité Municipale">
                <LogIn size={15} />
                {!isCollapsed && <span>Connexion</span>}
              </button>
            )}
          </div>

          <div className="tm-sidebar-controls-row">
            <button
              type="button"
              className="tm-sidebar-control-btn"
              onClick={onToggleLang}
              title={lang === 'fr' ? 'Switch to English' : 'Passer en français'}
              aria-label="Changer de langue"
            >
              <Globe size={14} />
              {!isCollapsed && <span>{lang === 'fr' ? 'FR' : 'EN'}</span>}
            </button>
          </div>
        </div>
      </aside>
    </>
  );
}
