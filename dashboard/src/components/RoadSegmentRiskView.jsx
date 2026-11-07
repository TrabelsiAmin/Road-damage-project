import React, { useState } from 'react';
import {
  Route,
  AlertTriangle,
  Flame,
  ChevronDown,
  ChevronRight,
  ExternalLink,
  Coins,
  Clock,
  Shield,
  Layers,
  Info,
} from 'lucide-react';
import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import { displayClassCode, statClassCode, UNKNOWN_CLASS_LABEL } from '../utils/classCodes';

export function RoadSegmentRiskView({
  corridorRisks = [],
  lang = 'fr',
  onSelectAnomaly,
}) {
  const [expandedCode, setExpandedCode] = useState(null);

  const toggleExpand = (code) => {
    setExpandedCode(expandedCode === code ? null : code);
  };

  return (
    <div className="road-segments-container">
      <div className="section-intro">
        <div className="intro-title-row">
          <Route size={20} color="var(--color-primary)" />
          <div>
            <h2 style={{ fontSize: '1.1rem', fontWeight: 800 }}>
              {lang === 'fr' ? 'Matrice de risque par corridor routier' : 'Road Corridor Risk Matrix'}
            </h2>
            <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '2px' }}>
              {lang === 'fr'
                ? 'Agrégation spatiale déterministe basée sur la gravité des nids-de-poule, la récurrence des passages, l\'ancienneté des dossiers et la qualité géodésique.'
                : 'Deterministic spatial corridor aggregation based on pothole severity, report counts, backlog age, and GPS accuracy.'}
            </p>
          </div>
        </div>
      </div>

      <div className="corridor-cards-list">
        {corridorRisks.length === 0 ? (
          <div className="panel-empty-state" style={{ height: '240px' }}>
            <Route size={32} style={{ opacity: 0.3 }} />
            <p>{lang === 'fr' ? 'Aucun corridor n\'enregistre d\'anomalie pour ces filtres.' : 'No corridor anomalies for selected filters.'}</p>
          </div>
        ) : (
          corridorRisks.map((corridor, idx) => {
            const isExpanded = expandedCode === corridor.code;
            const riskColor = corridor.levelColor || '#F59E0B';
            const domCls = displayClassCode(corridor.dominantClass);
            const knownDom = statClassCode(corridor.dominantClass);
            const clsInfo = (knownDom && DAMAGE_CLASSES[knownDom]) || { fr: UNKNOWN_CLASS_LABEL, color: '#64748b' };

            return (
              <div key={corridor.code || idx} className={`corridor-risk-card ${isExpanded ? 'expanded' : ''}`}>
                <div className="corridor-card-main" onClick={() => toggleExpand(corridor.code)}>
                  <div className="corridor-card-left">
                    <span className="corridor-rank-badge">#{idx + 1}</span>
                    <div className="corridor-info">
                      <div className="corridor-name-row">
                        <strong className="corridor-name">{corridor.name}</strong>
                        <span className="corridor-code-pill">{corridor.code}</span>
                      </div>
                      <div className="corridor-meta-row">
                        <span>{corridor.reportCount} {lang === 'fr' ? 'signalement(s)' : 'report(s)'}</span>
                        <span>•</span>
                        <span>{corridor.anomaliesCount} {lang === 'fr' ? 'anomalie(s) distincte(s)' : 'distinct anomalies'}</span>
                        <span>•</span>
                        <span style={{ color: clsInfo.color, fontWeight: 700 }}>
                          Dom: {domCls} ({lang === 'fr' ? clsInfo.fr : domCls})
                        </span>
                      </div>
                    </div>
                  </div>

                  <div className="corridor-card-right">
                    <div className="corridor-stat">
                      <span className="stat-label">{lang === 'fr' ? 'Ancienneté max' : 'Max Age'}</span>
                      <span className="stat-val">{corridor.maxAgeDays}j</span>
                    </div>

                    <div className="corridor-stat">
                      <span className="stat-label">{lang === 'fr' ? 'Budget estimé' : 'Est. Budget'}</span>
                      <span className="stat-val mono">{(corridor.estimatedBudgetTnd || 0).toLocaleString()} DT</span>
                    </div>

                    <div className="corridor-risk-badge-wrap">
                      <div
                        className="corridor-risk-pill"
                        style={{ color: riskColor, borderColor: `${riskColor}50`, background: `${riskColor}15` }}
                      >
                        <Flame size={14} />
                        <span className="risk-score-num">{corridor.riskScore}</span>
                        <span className="risk-score-label">/100</span>
                      </div>
                      <span className="risk-level-name" style={{ color: riskColor }}>
                        {corridor.riskLevel}
                      </span>
                    </div>

                    <div className="corridor-chevron">
                      {isExpanded ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
                    </div>
                  </div>
                </div>

                {/* Score Explanation Sub-bar */}
                <div className="corridor-explanation-bar">
                  <Info size={13} style={{ flexShrink: 0, marginTop: '2px', color: 'var(--color-primary)' }} />
                  <span className="explanation-text">{corridor.scoreExplanation}</span>
                </div>

                {/* Expanded Anomalies Table */}
                {isExpanded && (
                  <div className="corridor-anomalies-expanded">
                    <div className="expanded-title">
                      <Layers size={13} />
                      <span>
                        {lang === 'fr'
                          ? `Détail des ${corridor.anomalies.length} signalements sur ${corridor.name}`
                          : `Breakdown of ${corridor.anomalies.length} reports on ${corridor.name}`}
                      </span>
                    </div>
                    <div className="expanded-table-wrap">
                      <table className="expanded-table">
                        <thead>
                          <tr>
                            <th>ID</th>
                            <th>{lang === 'fr' ? 'Classe' : 'Class'}</th>
                            <th>{lang === 'fr' ? 'Priorité' : 'Priority'}</th>
                            <th>{lang === 'fr' ? 'Délégation' : 'Municipality'}</th>
                            <th>{lang === 'fr' ? 'Date' : 'Date'}</th>
                            <th>{lang === 'fr' ? 'Statut' : 'Status'}</th>
                            <th style={{ textAlign: 'right' }}>{lang === 'fr' ? 'Dossier' : 'Case'}</th>
                          </tr>
                        </thead>
                        <tbody>
                          {corridor.anomalies.map((a) => {
                            const cCode = displayClassCode(a.anomaly_type);
                            const cCol = DAMAGE_CLASSES[statClassCode(a.anomaly_type)]?.color || '#64748b';
                            return (
                              <tr key={a.id}>
                                <td><span className="mono table-id">#{String(a.id).substring(0, 8)}</span></td>
                                <td>
                                  <span className="class-badge" style={{ color: cCol, background: `${cCol}15` }}>
                                    {cCode}
                                  </span>
                                </td>
                                <td>
                                  <span className="mono" style={{ fontWeight: 700 }}>
                                    {Number(a.priority_score || 0).toFixed(1)}
                                  </span>
                                </td>
                                <td>{a.municipality || '—'}</td>
                                <td>{a.created_at ? new Date(a.created_at).toLocaleDateString() : '—'}</td>
                                <td>
                                  <span className={`status-pill status-${a.status || 'unconfirmed'}`}>
                                    {STATUS_LABELS[a.status]?.fr || a.status}
                                  </span>
                                </td>
                                <td style={{ textAlign: 'right' }}>
                                  <button
                                    type="button"
                                    className="btn-action-icon"
                                    onClick={() => onSelectAnomaly(a)}
                                    title="Ouvrir la fiche d'intervention"
                                  >
                                    <ExternalLink size={13} />
                                  </button>
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
