import React from 'react';
import { Flame, AlertTriangle, ShieldCheck } from 'lucide-react';

export function PriorityBadge({ priority = 'LOW', score = null, lang = 'fr', size = 'normal' }) {
  const norm = String(priority || 'LOW').toUpperCase();

  let labelFr = 'Faible';
  let labelEn = 'Low';
  let colorClass = 'tm-priority-low';
  let Icon = ShieldCheck;

  if (norm === 'HIGH' || norm === 'CRITICAL') {
    labelFr = norm === 'CRITICAL' ? 'Critique' : 'Élevée';
    labelEn = norm === 'CRITICAL' ? 'Critical' : 'High';
    colorClass = 'tm-priority-high';
    Icon = Flame;
  } else if (norm === 'MEDIUM') {
    labelFr = 'Moyenne';
    labelEn = 'Medium';
    colorClass = 'tm-priority-medium';
    Icon = AlertTriangle;
  }

  const label = lang === 'fr' ? labelFr : labelEn;

  return (
    <span className={`tm-priority-badge ${colorClass} tm-priority-${size}`}>
      <Icon size={size === 'sm' ? 11 : 13} className="tm-priority-icon" />
      <span>{label}</span>
      {score != null && Number.isFinite(Number(score)) && (
        <span className="tm-priority-score">({Number(score).toFixed(0)})</span>
      )}
    </span>
  );
}
