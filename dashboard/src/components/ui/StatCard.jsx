import React from 'react';
import { ArrowUpRight, ArrowDownRight, Minus } from 'lucide-react';

export function StatCard({
  title,
  value,
  sub,
  delta,
  deltaType = 'neutral', // 'positive' | 'negative' | 'warning' | 'neutral'
  icon: Icon,
  color = '#2563eb',
  loading = false,
  clickable = false,
  onClick,
  badge,
}) {
  if (loading) {
    return (
      <div className="tm-stat-card tm-stat-card-loading">
        <div className="tm-stat-card-header">
          <div className="skeleton-line" style={{ width: '45%', height: '14px' }} />
          <div className="skeleton-line" style={{ width: '28px', height: '28px', borderRadius: '50%' }} />
        </div>
        <div className="skeleton-line" style={{ width: '60%', height: '32px', margin: '12px 0 8px' }} />
        <div className="skeleton-line" style={{ width: '80%', height: '12px' }} />
      </div>
    );
  }

  const renderDeltaIcon = () => {
    if (deltaType === 'positive') return <ArrowUpRight size={13} />;
    if (deltaType === 'negative') return <ArrowDownRight size={13} />;
    return <Minus size={13} />;
  };

  return (
    <div
      className={`tm-stat-card ${clickable ? 'tm-stat-card-clickable' : ''}`}
      onClick={clickable ? onClick : undefined}
      role={clickable ? 'button' : undefined}
      tabIndex={clickable ? 0 : undefined}
      onKeyDown={
        clickable
          ? (e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                onClick && onClick();
              }
            }
          : undefined
      }
    >
      <div className="tm-stat-card-header">
        <span className="tm-stat-card-title">{title}</span>
        {Icon && (
          <div
            className="tm-stat-card-icon-badge"
            style={{
              backgroundColor: `${color}18`,
              color: color,
            }}
          >
            <Icon size={16} />
          </div>
        )}
      </div>

      <div className="tm-stat-card-body">
        <div className="tm-stat-card-value-row">
          <span className="tm-stat-card-value">{value ?? '--'}</span>
          {badge && <span className="tm-stat-card-badge">{badge}</span>}
        </div>

        {(delta || sub) && (
          <div className="tm-stat-card-footer">
            {delta && (
              <span className={`tm-stat-delta tm-delta-${deltaType}`}>
                {renderDeltaIcon()}
                <span>{delta}</span>
              </span>
            )}
            {sub && <span className="tm-stat-card-sub">{sub}</span>}
          </div>
        )}
      </div>
    </div>
  );
}
