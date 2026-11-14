import React, { useState } from 'react';
import { Sidebar } from './Sidebar';
import { Topbar } from './Topbar';

export function DashboardShell({
  activeNavTab,
  onSelectNavTab,
  counts = {},
  searchQuery,
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
  onLogout,
  lang = 'fr',
  onToggleLang,
  children,
}) {
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(false);
  const [isMobileOpen, setIsMobileOpen] = useState(false);

  return (
    <div className={`tm-shell ${isSidebarCollapsed ? 'tm-shell-collapsed' : ''}`}>
      {/* 21st.dev inspired Collapsible / Responsive Sidebar */}
      <Sidebar
        activeNavTab={activeNavTab}
        onSelectNavTab={onSelectNavTab}
        isCollapsed={isSidebarCollapsed}
        onToggleCollapse={() => setIsSidebarCollapsed((prev) => !prev)}
        isMobileOpen={isMobileOpen}
        onCloseMobile={() => setIsMobileOpen(false)}
        counts={counts}
        currentUser={currentUser}
        isAuthorityUser={isAuthorityUser}
        onOpenLogin={onOpenLogin}
        onLogout={onLogout}
        lang={lang}
        onToggleLang={onToggleLang}
      />

      {/* Main Viewport */}
      <div className="tm-main-viewport">
        {/* Top Header */}
        <Topbar
          activeNavTab={activeNavTab}
          onOpenMobileSidebar={() => setIsMobileOpen(true)}
          searchQuery={searchQuery}
          onSearchChange={onSearchChange}
          loading={loading}
          isRefreshing={isRefreshing}
          onRefresh={onRefresh}
          lastUpdated={lastUpdated}
          hasDemoData={hasDemoData}
          onOpenMetrics={onOpenMetrics}
          onExportCsv={onExportCsv}
          currentUser={currentUser}
          isAuthorityUser={isAuthorityUser}
          onOpenLogin={onOpenLogin}
          lang={lang}
        />

        {/* Dynamic Content Region */}
        <main className="tm-content-area" id="main-content">
          {children}
        </main>
      </div>
    </div>
  );
}
