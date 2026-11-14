import React from 'react';
import {
  LayoutDashboard,
  Inbox,
  MapPin,
  Route,
  TrendingUp,
  Cpu,
  FileSpreadsheet,
  History,
  ChevronLeft,
  ChevronRight,
  ShieldCheck,
  ShieldAlert,
  LogIn,
  LogOut,
  Globe,
  X,
} from 'lucide-react';

export const NAV_ITEMS = [
  {
    id: 'overview',
    fr: 'Vue d’ensemble',
    en: 'Executive Overview',
    icon: LayoutDashboard,
    badgeKey: null,
  },
  {
    id: 'action_center',
    fr: 'Centre d’opérations',
    en: 'Action Center',
    icon: Inbox,
    badgeKey: 'critical',
    badgeVariant: 'critical',
  },
  {
    id: 'gis_map',
    fr: 'Carte SIG',
    en: 'GIS Map',
    icon: MapPin,
    badgeKey: 'clusters',
    badgeVariant: 'primary',
  },
  {
    id: 'road_segments',
    fr: 'Risque par tronçon',
    en: 'Road Segments',
    icon: Route,
    badgeKey: null,
  },
  {
    id: 'analytics',
    fr: 'Analytique & tendances',
    en: 'Analytics & Trends',
    icon: TrendingUp,
    badgeKey: null,
  },
  {
    id: 'data_quality',
    fr: 'Qualité & modèle IA',
    en: 'Data Quality & AI',
    icon: Cpu,
    badgeKey: null,
  },
  {
    id: 'reports',
    fr: 'Rapports & exports',
    en: 'Reports & Exports',
    icon: FileSpreadsheet,
    badgeKey: null,
  },
  {
    id: 'audit',
    fr: 'Journal d’audit',
    en: 'Audit Trail',
    icon: History,
    badgeKey: null,
  },
];

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
    if (isMobileOpen && onCloseMobile) {
      onCloseMobile();
    }
  };

  return (
    <>
      {/* Mobile Drawer Backdrop */}
      {isMobileOpen && (
        <div
          className="tm-sidebar-backdrop"
          onClick={onCloseMobile}
          aria-hidden="true"
        />
      )}

      <aside
        className={`tm-sidebar ${isCollapsed ? 'tm-sidebar-collapsed' : ''} ${
          isMobileOpen ? 'tm-sidebar-mobile-open' : ''
        }`}
        aria-label="Navigation principale"
      >
        {/* Brand Header */}
        <div className="tm-sidebar-header">
          <div className="tm-sidebar-brand" onClick={() => handleNavClick('overview')}>
            <div className="tm-sidebar-logo">TM</div>
            {!isCollapsed && (
              <div className="tm-sidebar-brand-text">
                <span className="tm-brand-name">TariqMap</span>
                <span className="tm-brand-dept">DGPC · Ministère</span>
              </div>
            )}
          </div>

          {/* Mobile Close Button */}
          {isMobileOpen && (
            <button
              type="button"
              className="tm-sidebar-close-mobile"
              onClick={onCloseMobile}
              aria-label="Fermer le menu"
            >
              <X size={18} />
            </button>
          )}

          {/* Desktop Collapse Toggle Button */}
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

        {/* Navigation Items List */}
        <nav className="tm-sidebar-nav">
          <ul className="tm-sidebar-list">
            {NAV_ITEMS.map((item) => {
              const Icon = item.icon;
              const isActive = activeNavTab === item.id;
              const label = lang === 'fr' ? item.fr : item.en;
              const badgeCount = item.badgeKey ? counts[item.badgeKey] : null;

              return (
                <li key={item.id} className="tm-sidebar-item">
                  <button
                    type="button"
                    className={`tm-sidebar-link ${isActive ? 'active' : ''}`}
                    onClick={() => handleNavClick(item.id)}
                    title={isCollapsed ? label : undefined}
                    aria-current={isActive ? 'page' : undefined}
                  >
                    <Icon size={18} className="tm-sidebar-item-icon" />
                    {!isCollapsed && (
                      <span className="tm-sidebar-item-label">{label}</span>
                    )}
                    {badgeCount > 0 && (
                      <span
                        className={`tm-sidebar-badge tm-badge-${
                          item.badgeVariant || 'neutral'
                        } ${isCollapsed ? 'tm-badge-dot-only' : ''}`}
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
        </nav>

        {/* Sidebar Footer */}
        <div className="tm-sidebar-footer">
          {/* User / Authority Status */}
          <div className="tm-sidebar-user-section">
            {currentUser ? (
              <div
                className={`tm-sidebar-user-card ${
                  isAuthorityUser ? 'tm-user-authority' : 'tm-user-standard'
                }`}
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
                    <span className="tm-user-role">
                      {isAuthorityUser ? 'AUTORITÉ VOIRIE' : 'UTILISATEUR'}
                    </span>
                    <span className="tm-user-email">{currentUser.email}</span>
                  </div>
                )}
                {!isCollapsed && (
                  <button
                    type="button"
                    className="tm-btn-ghost-icon tm-logout-btn"
                    onClick={onLogout}
                    title="Déconnexion"
                    aria-label="Déconnexion"
                  >
                    <LogOut size={14} />
                  </button>
                )}
              </div>
            ) : (
              <button
                type="button"
                className="btn btn-primary tm-sidebar-login-btn"
                onClick={onOpenLogin}
                title="Connexion Autorité Municipale"
              >
                <LogIn size={15} />
                {!isCollapsed && <span>Connexion Autorité</span>}
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
