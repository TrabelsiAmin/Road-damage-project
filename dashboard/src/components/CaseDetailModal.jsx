import React, { useState, useEffect } from 'react';
import {
  X,
  MapPin,
  Calendar,
  Shield,
  CheckCircle2,
  AlertTriangle,
  Clock,
  Wrench,
  XCircle,
  Camera,
  Layers,
  History,
  Building2,
  FileText,
  UserCheck,
  Send,
} from 'lucide-react';
import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import { displayClassCode, observationClassCode, statClassCode, UNKNOWN_CLASS_LABEL } from '../utils/classCodes';
import { getSignedMediaUrl, getPublicMediaUrl } from '../supabase';
import { ORGANIZATIONS_LIST } from './GlobalFilterBar';

export function CaseDetailModal({
  observation,
  isAuthorityUser,
  onClose,
  onUpdateStatus,
  onAssignCase,
  onOpenLightbox,
  lang = 'fr',
}) {
  const [activeTab, setActiveTab] = useState('overview'); // 'overview' | 'evidence' | 'workflow' | 'audit'
  const [imageUrl, setImageUrl] = useState(null);
  const [imageLoading, setImageLoading] = useState(false);
  const [imageError, setImageError] = useState(null);
  const [imageAttempt, setImageAttempt] = useState(0);
  const [assignedOrg, setAssignedOrg] = useState(observation?.organization_id || '');
  const [repairNotes, setRepairNotes] = useState('');
  const [dueDate, setDueDate] = useState('');

  const storedClass = observationClassCode(observation);
  const knownClass = statClassCode(storedClass);
  const clsCode = displayClassCode(storedClass);
  const clsInfo = (knownClass && DAMAGE_CLASSES[knownClass]) || {
    fr: UNKNOWN_CLASS_LABEL,
    en: UNKNOWN_CLASS_LABEL,
    color: '#64748b',
  };
  const prio = observation?.priority_label || (observation?.priority_score > 65 ? 'HIGH' : observation?.priority_score > 35 ? 'MEDIUM' : 'LOW');
  const prioColor = prio === 'HIGH' ? '#EF4444' : prio === 'MEDIUM' ? '#F59E0B' : '#3B82F6';

  // Load image
  useEffect(() => {
    let active = true;
    async function loadImage() {
      const orig = observation?.original_media;
      const thumb = observation?.thumbnail_media;
      if (active) {
        setImageError(null);
        setImageUrl(null);
      }

      if (isAuthorityUser && orig?.storage_path) {
        setImageLoading(true);
        try {
          const res = await getSignedMediaUrl(orig.storage_path, 'observation-images', 600);
          if (active) {
            setImageUrl(res.signedUrl);
            setImageLoading(false);
          }
        } catch (err) {
          if (active) {
            setImageLoading(false);
            setImageError(lang === 'fr' ? 'Impossible de charger la photo.' : 'Could not load the photo.');
          }
        }
      } else if (thumb?.storage_path) {
        const url = getPublicMediaUrl(thumb.storage_path, 'public-photos');
        if (active) {
          if (url) setImageUrl(url);
          else setImageError(lang === 'fr' ? 'Impossible de charger la photo.' : 'Could not load the photo.');
        }
      }
    }
    loadImage();
    return () => {
      active = false;
    };
  }, [observation, isAuthorityUser, imageAttempt, lang]);

  if (!observation) return null;

  const handleSaveAssignment = () => {
    if (onAssignCase) {
      onAssignCase(observation.id, {
        organizationId: assignedOrg,
        notes: repairNotes,
        dueDate,
      });
    }
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-card case-detail-modal" onClick={(e) => e.stopPropagation()}>
        {/* Modal Header */}
        <div className="modal-header">
          <div className="case-title-row">
            <span className="case-class-chip" style={{ color: clsInfo.color, borderColor: `${clsInfo.color}50`, background: `${clsInfo.color}15` }}>
              {clsCode}
            </span>
            <div className="case-title-text">
              <h3 style={{ fontSize: '1.05rem', fontWeight: 800 }}>
                {lang === 'fr' ? 'Dossier d\'intervention voirie' : 'Road Maintenance Case'} #{String(observation.id).substring(0, 8)}
              </h3>
              <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                {observation.roadSegment || 'Voirie non répertoriée'} • {observation.municipality || '—'}, {observation.governorate || '—'}
              </span>
            </div>
          </div>
          <button type="button" className="icon-btn" onClick={onClose} title="Fermer">
            <X size={18} />
          </button>
        </div>

        {/* Navigation Tabs */}
        <div className="case-nav-tabs">
          <button
            type="button"
            className={`case-tab-btn ${activeTab === 'overview' ? 'active' : ''}`}
            onClick={() => setActiveTab('overview')}
          >
            <FileText size={14} />
            <span>{lang === 'fr' ? 'Vue générale' : 'Overview'}</span>
          </button>
          <button
            type="button"
            className={`case-tab-btn ${activeTab === 'evidence' ? 'active' : ''}`}
            onClick={() => setActiveTab('evidence')}
          >
            <Camera size={14} />
            <span>{lang === 'fr' ? 'Preuve photographique' : 'Evidence'}</span>
          </button>
          {isAuthorityUser && (
            <button
              type="button"
              className={`case-tab-btn ${activeTab === 'workflow' ? 'active' : ''}`}
              onClick={() => setActiveTab('workflow')}
            >
              <Wrench size={14} />
              <span>{lang === 'fr' ? 'Affectation & Travaux' : 'Workflow & Repair'}</span>
            </button>
          )}
        </div>

        {/* Tab Body */}
        <div className="case-modal-body">
          {activeTab === 'overview' && (
            <div className="case-overview-grid">
              <div className="detail-item">
                <span className="detail-label">{lang === 'fr' ? 'Type de dégradation' : 'Damage Type'}</span>
                <span className="detail-value">{clsCode} — {lang === 'fr' ? clsInfo.fr : clsInfo.en}</span>
              </div>
              <div className="detail-item">
                <span className="detail-label">{lang === 'fr' ? 'Priorité de danger' : 'Priority'}</span>
                <span className="detail-value" style={{ color: prioColor, fontWeight: 700 }}>
                  {prio} ({Number(observation.priority_score || 0).toFixed(1)} / 100)
                </span>
              </div>
              <div className="detail-item">
                <span className="detail-label">{lang === 'fr' ? 'Statut du cycle' : 'Lifecycle Status'}</span>
                <span className={`status-pill status-${observation.status || 'unconfirmed'}`}>
                  {STATUS_LABELS[observation.status]?.fr || observation.status}
                </span>
              </div>
              <div className="detail-item">
                <span className="detail-label">{lang === 'fr' ? 'Coordonnées GPS' : 'GPS Coordinates'}</span>
                <span className="detail-value mono">
                  {Number(observation.latitude || 0).toFixed(6)}, {Number(observation.longitude || 0).toFixed(6)}
                </span>
              </div>
              <div className="detail-item">
                <span className="detail-label">{lang === 'fr' ? 'Précision GNSS' : 'GNSS Accuracy'}</span>
                <span className="detail-value mono">±{observation.accuracy_meters || '—'} mètres</span>
              </div>
              <div className="detail-item">
                <span className="detail-label">{lang === 'fr' ? 'Date de détection' : 'Detected on'}</span>
                <span className="detail-value">
                  {observation.created_at ? new Date(observation.created_at).toLocaleString() : '—'}
                </span>
              </div>
            </div>
          )}

          {activeTab === 'evidence' && (
            <div className="case-evidence-pane">
              {imageLoading ? (
                <div className="panel-empty-state" style={{ height: '220px' }}>
                  <div className="spinner-sm" />
                  <p>{lang === 'fr' ? 'Génération de l\'URL signée sécurisée (10 min)...' : 'Loading signed image...'}</p>
                </div>
              ) : imageError ? (
                <div className="panel-empty-state" style={{ height: '200px' }}>
                  <Camera size={32} style={{ opacity: 0.3 }} />
                  <p>{imageError}</p>
                  <button type="button" className="btn btn-secondary" onClick={() => setImageAttempt((n) => n + 1)}>
                    {lang === 'fr' ? 'Réessayer' : 'Retry'}
                  </button>
                </div>
              ) : imageUrl ? (
                <div className="evidence-image-wrap" onClick={() => onOpenLightbox && onOpenLightbox({ url: imageUrl, title: `#${observation.id}`, badge: clsCode })}>
                  <img
                    src={imageUrl}
                    alt="Cliché terrain"
                    className="evidence-img"
                    onError={() => setImageError(lang === 'fr' ? 'Impossible de charger la photo.' : 'Could not load the photo.')}
                  />
                  <span className="evidence-badge">
                    {isAuthorityUser ? 'Original certifié (Autorité)' : 'Vignette publique floutée'}
                  </span>
                </div>
              ) : (
                <div className="panel-empty-state" style={{ height: '200px' }}>
                  <Camera size={32} style={{ opacity: 0.3 }} />
                  <p>{lang === 'fr' ? 'Aucune preuve visuelle rattachée à cette observation.' : 'No photo uploaded.'}</p>
                </div>
              )}
            </div>
          )}

          {activeTab === 'workflow' && isAuthorityUser && (
            <div className="case-workflow-pane">
              <div className="workflow-form-group">
                <label className="workflow-label">
                  <Building2 size={13} />
                  <span>{lang === 'fr' ? 'Assigner à une brigade / direction' : 'Assign to organization'}</span>
                </label>
                <select
                  className="select-input"
                  value={assignedOrg}
                  onChange={(e) => setAssignedOrg(e.target.value)}
                >
                  <option value="">{lang === 'fr' ? 'Non assigné' : 'Unassigned'}</option>
                  {ORGANIZATIONS_LIST.map((org) => (
                    <option key={org.id} value={org.id}>{org.name}</option>
                  ))}
                </select>
              </div>

              <div className="workflow-form-group">
                <label className="workflow-label">
                  <Calendar size={13} />
                  <span>{lang === 'fr' ? 'Date limite d\'intervention (SLA)' : 'Due date'}</span>
                </label>
                <input
                  type="date"
                  className="search-input"
                  value={dueDate}
                  onChange={(e) => setDueDate(e.target.value)}
                />
              </div>

              <div className="workflow-form-group">
                <label className="workflow-label">
                  <FileText size={13} />
                  <span>{lang === 'fr' ? 'Instructions pour l\'équipe de voirie' : 'Work notes'}</span>
                </label>
                <textarea
                  className="search-input"
                  rows={3}
                  placeholder={lang === 'fr' ? 'Détails des fournitures d\'enrobé, contraintes de circulation...' : 'Work details...'}
                  value={repairNotes}
                  onChange={(e) => setRepairNotes(e.target.value)}
                />
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '12px' }}>
                <button
                  type="button"
                  className="btn btn-primary btn-sm"
                  onClick={handleSaveAssignment}
                >
                  <Send size={13} />
                  <span>{lang === 'fr' ? 'Enregistrer l\'affectation' : 'Save Assignment'}</span>
                </button>
              </div>
            </div>
          )}
        </div>

        {/* Modal Footer Actions */}
        {isAuthorityUser && (
          <div className="modal-footer">
            <div className="footer-actions-left">
              {observation.status === 'unconfirmed' && (
                <button
                  type="button"
                  className="btn btn-primary btn-sm"
                  onClick={() => onUpdateStatus(observation.id, 'confirmed')}
                >
                  <CheckCircle2 size={14} />
                  <span>{lang === 'fr' ? 'Valider le signalement' : 'Validate'}</span>
                </button>
              )}
              {observation.status === 'confirmed' && (
                <button
                  type="button"
                  className="btn btn-secondary btn-sm"
                  onClick={() => onUpdateStatus(observation.id, 'in_progress')}
                >
                  <Clock size={14} />
                  <span>{lang === 'fr' ? 'Lancer travaux' : 'Start Repair'}</span>
                </button>
              )}
              {(observation.status === 'confirmed' || observation.status === 'in_progress') && (
                <button
                  type="button"
                  className="btn btn-primary btn-sm"
                  style={{ background: 'var(--color-success)', borderColor: 'var(--color-success)' }}
                  onClick={() => onUpdateStatus(observation.id, 'repaired')}
                >
                  <Wrench size={14} />
                  <span>{lang === 'fr' ? 'Clôturer réparation' : 'Mark Repaired'}</span>
                </button>
              )}
            </div>

            <div className="footer-actions-right">
              {observation.status !== 'rejected' && observation.status !== 'repaired' && (
                <button
                  type="button"
                  className="btn-status btn-reject"
                  onClick={() => onUpdateStatus(observation.id, 'rejected')}
                >
                  <XCircle size={14} />
                  <span>{lang === 'fr' ? 'Rejeter (Faux positif)' : 'Reject'}</span>
                </button>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
