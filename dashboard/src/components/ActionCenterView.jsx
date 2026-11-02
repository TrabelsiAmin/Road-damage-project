import React, { useState, useMemo } from 'react';
import {
  Flame,
  Inbox,
  Clock,
  UserX,
  Wrench,
  CheckCircle2,
  CopyCheck,
  Compass,
  FileQuestion,
  CheckSquare,
  Square,
  AlertCircle,
  ExternalLink,
  ChevronRight,
  Filter,
  Check,
  X,
  FileSpreadsheet,
} from 'lucide-react';
import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import { resolveTunisiaAdmin } from '../utils/tunisiaGeo';
import { ORGANIZATIONS_LIST } from './GlobalFilterBar';
import { exportToCsv } from '../utils/exportFormats';

const QUEUE_TABS = [
  { id: 'critical', fr: 'Critiques', en: 'Critical', icon: Flame, color: '#EF4444' },
  { id: 'awaiting_validation', fr: 'En attente validation', en: 'Awaiting Validation', icon: Inbox, color: '#8B5CF6' },
  { id: 'overdue', fr: 'En retard (>14j)', en: 'Overdue', icon: Clock, color: '#DC2626' },
  { id: 'unassigned', fr: 'Non assignées', en: 'Unassigned', icon: UserX, color: '#F59E0B' },
  { id: 'in_progress', fr: 'En cours', en: 'In Progress', icon: Wrench, color: '#06B6D4' },
  { id: 'awaiting_verification', fr: 'À vérifier', en: 'Awaiting Verification', icon: CheckCircle2, color: '#10B981' },
  { id: 'repeated_reports', fr: 'Répétés (>1)', en: 'Multi-report', icon: CopyCheck, color: '#6366F1' },
  { id: 'poor_gps', fr: 'GPS faible (>25m)', en: 'Poor GPS', icon: Compass, color: '#E11D48' },
];

export function ActionCenterView({
  queues,
  activeQueue = 'critical',
  onSelectQueue,
  isAuthorityUser,
  onOpenDetail,
  onUpdateStatus,
  onBulkUpdate,
  lang = 'fr',
}) {
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [bulkAction, setBulkAction] = useState('');
  const [bulkTargetValue, setBulkTargetValue] = useState('');
  const [showBulkConfirm, setShowBulkConfirm] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');

  const currentList = queues[activeQueue] || [];

  // Filter list by local search if specified
  const filteredList = useMemo(() => {
    if (!searchTerm.trim()) return currentList;
    const term = searchTerm.toLowerCase();
    return currentList.filter((item) => {
      const id = String(item.id || '').toLowerCase();
      const cls = String(item.anomaly_type || item.dominantClass || '').toLowerCase();
      const status = String(item.status || '').toLowerCase();
      const muni = String(item.municipality || '').toLowerCase();
      const gov = String(item.governorate || '').toLowerCase();
      const road = String(item.roadSegment || '').toLowerCase();
      return id.includes(term) || cls.includes(term) || status.includes(term) || muni.includes(term) || gov.includes(term) || road.includes(term);
    });
  }, [currentList, searchTerm]);

  // Bulk selection handlers
  const handleToggleSelect = (id) => {
    const next = new Set(selectedIds);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelectedIds(next);
  };

  const handleSelectAll = () => {
    if (selectedIds.size === filteredList.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filteredList.map((item) => item.id)));
    }
  };

  const handleExecuteBulk = () => {
    if (selectedIds.size === 0 || !bulkAction) return;
    const ids = Array.from(selectedIds);

    if (bulkAction === 'export') {
      const selectedItems = filteredList.filter((item) => selectedIds.has(item.id));
      exportToCsv(selectedItems, `tariqmap-export-selection-${ids.length}.csv`);
      setShowBulkConfirm(false);
      setBulkAction('');
      return;
    }

    if (bulkAction === 'status') {
      onBulkUpdate({ action: 'status', ids, value: bulkTargetValue });
    } else if (bulkAction === 'priority') {
      onBulkUpdate({ action: 'priority', ids, value: bulkTargetValue });
    } else if (bulkAction === 'assign') {
      onBulkUpdate({ action: 'assign', ids, value: bulkTargetValue });
    }

    setSelectedIds(new Set());
    setShowBulkConfirm(false);
    setBulkAction('');
    setBulkTargetValue('');
  };

  return (
    <div className="action-center-container">
      {/* ── Queue Navigation Tabs ── */}
      <div className="queue-tabs-bar">
        {QUEUE_TABS.map((tab) => {
          const Icon = tab.icon;
          const count = (queues[tab.id] || []).length;
          const isActive = activeQueue === tab.id;
          return (
            <button
              key={tab.id}
              type="button"
              className={`queue-tab-btn ${isActive ? 'active' : ''}`}
              onClick={() => {
                onSelectQueue(tab.id);
                setSelectedIds(new Set());
              }}
            >
              <div className="queue-tab-icon" style={{ color: tab.color }}>
                <Icon size={14} />
              </div>
              <span className="queue-tab-label">{lang === 'fr' ? tab.fr : tab.en}</span>
              <span
                className={`queue-count-pill ${count > 0 && (tab.id === 'critical' || tab.id === 'overdue') ? 'urgent' : ''}`}
              >
                {count}
              </span>
            </button>
          );
        })}
      </div>

      {/* ── Operational Queue Header & Bulk Toolbar ── */}
      <div className="action-center-toolbar">
        <div className="toolbar-left">
          <input
            type="text"
            className="search-input"
            placeholder={lang === 'fr' ? 'Rechercher par ID, route, commune...' : 'Search by ID, road, city...'}
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
          <span className="queue-summary-text">
            {filteredList.length} {lang === 'fr' ? 'cas dans cette file' : 'cases in this queue'}
          </span>
        </div>

        {isAuthorityUser && selectedIds.size > 0 && (
          <div className="bulk-toolbar">
            <span className="bulk-selected-badge">
              <CheckSquare size={14} />
              <span>{selectedIds.size} {lang === 'fr' ? 'sélectionnés' : 'selected'}</span>
            </span>

            <select
              className="select-input select-bulk"
              value={bulkAction}
              onChange={(e) => {
                setBulkAction(e.target.value);
                setBulkTargetValue('');
              }}
            >
              <option value="">{lang === 'fr' ? 'Action groupée...' : 'Bulk action...'}</option>
              <option value="status">{lang === 'fr' ? 'Changer statut' : 'Change status'}</option>
              <option value="priority">{lang === 'fr' ? 'Changer priorité' : 'Change priority'}</option>
              <option value="assign">{lang === 'fr' ? 'Assigner service' : 'Assign service'}</option>
              <option value="export">{lang === 'fr' ? 'Exporter sélection (CSV)' : 'Export selected (CSV)'}</option>
            </select>

            {bulkAction === 'status' && (
              <select
                className="select-input select-bulk"
                value={bulkTargetValue}
                onChange={(e) => setBulkTargetValue(e.target.value)}
              >
                <option value="">{lang === 'fr' ? 'Nouveau statut...' : 'New status...'}</option>
                <option value="confirmed">Confirmer</option>
                <option value="in_progress">En cours de réparation</option>
                <option value="repaired">Marquer réparé</option>
                <option value="rejected">Rejeter</option>
              </select>
            )}

            {bulkAction === 'priority' && (
              <select
                className="select-input select-bulk"
                value={bulkTargetValue}
                onChange={(e) => setBulkTargetValue(e.target.value)}
              >
                <option value="">{lang === 'fr' ? 'Nouvelle priorité...' : 'New priority...'}</option>
                <option value="HIGH">HIGH (Critique)</option>
                <option value="MEDIUM">MEDIUM (Moyen)</option>
                <option value="LOW">LOW (Surveillance)</option>
              </select>
            )}

            {bulkAction === 'assign' && (
              <select
                className="select-input select-bulk"
                value={bulkTargetValue}
                onChange={(e) => setBulkTargetValue(e.target.value)}
              >
                <option value="">{lang === 'fr' ? 'Choisir service...' : 'Choose service...'}</option>
                {ORGANIZATIONS_LIST.map((org) => (
                  <option key={org.id} value={org.id}>{org.name}</option>
                ))}
              </select>
            )}

            <button
              type="button"
              className="btn btn-primary btn-sm"
              disabled={!bulkAction || (bulkAction !== 'export' && !bulkTargetValue)}
              onClick={() => setShowBulkConfirm(true)}
            >
              {lang === 'fr' ? 'Appliquer' : 'Apply'}
            </button>
          </div>
        )}
      </div>

      {/* ── Operational Table ── */}
      <div className="action-table-wrap">
        <table className="action-table">
          <thead>
            <tr>
              {isAuthorityUser && (
                <th style={{ width: '38px', textAlign: 'center' }}>
                  <input
                    type="checkbox"
                    checked={filteredList.length > 0 && selectedIds.size === filteredList.length}
                    onChange={handleSelectAll}
                    aria-label="Sélectionner tous les cas"
                  />
                </th>
              )}
              <th>ID</th>
              <th>{lang === 'fr' ? 'Type d\'anomalie' : 'Anomaly Class'}</th>
              <th>{lang === 'fr' ? 'Priorité' : 'Priority'}</th>
              <th>{lang === 'fr' ? 'Localisation & Corridor' : 'Location & Corridor'}</th>
              <th>{lang === 'fr' ? 'Passages' : 'Reports'}</th>
              <th>{lang === 'fr' ? 'Signalé le' : 'Reported'}</th>
              <th>{lang === 'fr' ? 'Statut' : 'Status'}</th>
              <th>{lang === 'fr' ? 'Assigné à' : 'Assigned to'}</th>
              <th>{lang === 'fr' ? 'Coût est.' : 'Est. Cost'}</th>
              <th style={{ textAlign: 'right' }}>{lang === 'fr' ? 'Actions' : 'Actions'}</th>
            </tr>
          </thead>
          <tbody>
            {filteredList.length === 0 ? (
              <tr>
                <td colSpan={isAuthorityUser ? 11 : 10} className="table-empty-row">
                  <div className="table-empty-state">
                    <CheckCircle2 size={24} color="var(--color-success)" />
                    <span>{lang === 'fr' ? 'Aucun cas dans cette file opérationnelle.' : 'No cases in this queue.'}</span>
                  </div>
                </td>
              </tr>
            ) : (
              filteredList.map((item) => {
                const isSelected = selectedIds.has(item.id);
                const clsCode = item.anomaly_type || item.dominantClass || 'D40';
                const clsInfo = DAMAGE_CLASSES[clsCode] || { fr: clsCode, en: clsCode, color: '#64748b' };
                const prio = item.priority_label || (item.priority_score > 65 ? 'HIGH' : item.priority_score > 35 ? 'MEDIUM' : 'LOW');
                const prioColor = prio === 'HIGH' ? '#EF4444' : prio === 'MEDIUM' ? '#F59E0B' : '#3B82F6';
                const muni = item.municipality || '—';
                const gov = item.governorate || '—';
                const road = item.roadSegment || 'Voirie locale';
                const reportCount = item.reportsCount || 1;
                const dateStr = item.created_at ? new Date(item.created_at).toLocaleDateString() : '—';
                const statusLabel = STATUS_LABELS[item.status]?.fr || item.status || 'Non confirmé';

                // Cost estimation
                const costEst = clsCode === 'D40' ? 180 : clsCode === 'D20' ? 450 : 100;

                return (
                  <tr key={item.id} className={isSelected ? 'row-selected' : ''}>
                    {isAuthorityUser && (
                      <td style={{ textAlign: 'center' }}>
                        <input
                          type="checkbox"
                          checked={isSelected}
                          onChange={() => handleToggleSelect(item.id)}
                          aria-label={`Sélectionner cas ${item.id}`}
                        />
                      </td>
                    )}
                    <td>
                      <span className="mono table-id" onClick={() => onOpenDetail(item)} title="Ouvrir la fiche d'intervention">
                        #{String(item.id).substring(0, 8)}
                      </span>
                    </td>
                    <td>
                      <span className="class-badge" style={{ borderColor: `${clsInfo.color}40`, color: clsInfo.color, background: `${clsInfo.color}15` }}>
                        <strong>{clsCode}</strong> — {lang === 'fr' ? clsInfo.fr : clsInfo.en}
                      </span>
                    </td>
                    <td>
                      <span className="priority-badge" style={{ color: prioColor, background: `${prioColor}15` }}>
                        {prio} ({Number(item.priority_score || 0).toFixed(0)})
                      </span>
                    </td>
                    <td>
                      <div className="loc-cell">
                        <span className="loc-corridor">{road}</span>
                        <span className="loc-admin">{muni}, {gov}</span>
                      </div>
                    </td>
                    <td style={{ textAlign: 'center' }}>
                      <span className="report-count-pill">{reportCount}</span>
                    </td>
                    <td>
                      <span className="date-cell">{dateStr}</span>
                    </td>
                    <td>
                      <span className={`status-pill status-${item.status || 'unconfirmed'}`}>
                        {statusLabel}
                      </span>
                    </td>
                    <td>
                      <span className="assigned-text">
                        {item.assigned_to_name || (item.organization_id ? 'Direction Voirie' : 'Non assigné')}
                      </span>
                    </td>
                    <td>
                      <span className="mono cost-text">{costEst * reportCount} DT</span>
                    </td>
                    <td style={{ textAlign: 'right' }}>
                      <div className="table-actions-cell">
                        <button
                          type="button"
                          className="btn-action-icon"
                          onClick={() => onOpenDetail(item)}
                          title="Consulter le dossier d'intervention complet"
                        >
                          <ExternalLink size={14} />
                        </button>
                        {isAuthorityUser && item.status === 'unconfirmed' && (
                          <button
                            type="button"
                            className="btn-action-pill btn-confirm-pill"
                            onClick={() => onUpdateStatus(item.id, 'confirmed')}
                            title="Valider et confirmer l'anomalie"
                          >
                            <Check size={12} />
                            <span>Valider</span>
                          </button>
                        )}
                        {isAuthorityUser && (item.status === 'confirmed' || item.status === 'in_progress') && (
                          <button
                            type="button"
                            className="btn-action-pill btn-repair-pill"
                            onClick={() => onUpdateStatus(item.id, 'repaired')}
                            title="Marquer réparé"
                          >
                            <Wrench size={12} />
                            <span>Réparé</span>
                          </button>
                        )}
                        {isAuthorityUser && item.status !== 'rejected' && item.status !== 'repaired' && (
                          <button
                            type="button"
                            className="btn-action-pill btn-reject-pill"
                            onClick={() => onUpdateStatus(item.id, 'rejected')}
                            title="Rejeter (Faux positif / Pas d'anomalie)"
                          >
                            <X size={12} />
                            <span>Rejeter</span>
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* ── Bulk Confirmation Dialog ── */}
      {showBulkConfirm && (
        <div className="modal-overlay" onClick={() => setShowBulkConfirm(false)}>
          <div className="modal-card" style={{ maxWidth: '440px' }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: '24px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '14px' }}>
                <AlertCircle size={22} color="var(--color-warning)" />
                <h3 style={{ fontSize: '1.05rem', fontWeight: 800 }}>
                  {lang === 'fr' ? 'Confirmation d\'action groupée' : 'Confirm Bulk Action'}
                </h3>
              </div>

              <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)', lineHeight: 1.5, marginBottom: '16px' }}>
                {lang === 'fr'
                  ? `Vous êtes sur le point d'appliquer l'action "${bulkAction}" à ${selectedIds.size} signalement(s) sélectionné(s).`
                  : `You are about to apply "${bulkAction}" to ${selectedIds.size} selected case(s).`}
              </p>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '8px' }}>
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setShowBulkConfirm(false)}
                >
                  {lang === 'fr' ? 'Annuler' : 'Cancel'}
                </button>
                <button
                  type="button"
                  className="btn btn-primary"
                  onClick={handleExecuteBulk}
                >
                  {lang === 'fr' ? 'Confirmer et appliquer' : 'Confirm and apply'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
