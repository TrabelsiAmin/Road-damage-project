import React from 'react';
import { Inbox, RotateCcw } from 'lucide-react';

export function EmptyState({
  icon: Icon = Inbox,
  title,
  description,
  actionLabel,
  onAction,
  lang = 'fr',
}) {
  const defaultTitle = lang === 'fr' ? 'Aucune donnée disponible' : 'No data available';
  const defaultDesc =
    lang === 'fr'
      ? 'Aucun enregistrement ne correspond aux filtres actifs.'
      : 'No records match the current filter criteria.';

  return (
    <div className="tm-empty-state">
      <div className="tm-empty-state-icon-wrapper">
        <Icon size={28} className="tm-empty-state-icon" />
      </div>
      <h3 className="tm-empty-state-title">{title || defaultTitle}</h3>
      <p className="tm-empty-state-desc">{description || defaultDesc}</p>
      {actionLabel && onAction && (
        <button type="button" className="btn btn-secondary tm-empty-state-btn" onClick={onAction}>
          <RotateCcw size={14} />
          <span>{actionLabel}</span>
        </button>
      )}
    </div>
  );
}
