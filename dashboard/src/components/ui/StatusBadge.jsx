import React from 'react';
import { STATUS_LABELS } from '../../constants';
import { AlertCircle, CheckCircle2, Wrench, Clock, XCircle } from 'lucide-react';

const STATUS_ICONS = {
  unconfirmed: AlertCircle,
  confirmed: CheckCircle2,
  in_progress: Wrench,
  repaired: CheckCircle2,
  rejected: XCircle,
};

export function StatusBadge({ status = 'unconfirmed', lang = 'fr', size = 'normal' }) {
  const normStatus = status?.toLowerCase() || 'unconfirmed';
  const meta = STATUS_LABELS[normStatus] || { fr: normStatus, en: normStatus, color: '#64748b' };
  const label = lang === 'fr' ? meta.fr : meta.en;
  const Icon = STATUS_ICONS[normStatus] || AlertCircle;

  return (
    <span className={`tm-status-badge tm-status-${normStatus} tm-status-${size}`}>
      <Icon size={size === 'sm' ? 11 : 13} className="tm-status-icon" />
      <span>{label}</span>
    </span>
  );
}
