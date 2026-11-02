import React from 'react';

export function PageHeader({
  title,
  subtitle,
  badge,
  icon: Icon,
  actions,
  children,
}) {
  return (
    <div className="tm-page-header">
      <div className="tm-page-header-content">
        <div className="tm-page-header-title-row">
          {Icon && (
            <div className="tm-page-header-icon-box">
              <Icon size={20} />
            </div>
          )}
          <h1 className="tm-page-header-title">{title}</h1>
          {badge && <span className="tm-page-header-badge">{badge}</span>}
        </div>
        {subtitle && <p className="tm-page-header-subtitle">{subtitle}</p>}
        {children}
      </div>

      {actions && <div className="tm-page-header-actions">{actions}</div>}
    </div>
  );
}
