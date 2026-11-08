import React, { useState } from 'react';
import {
  Cpu,
  Compass,
  Camera,
  MessageSquare,
  AlertTriangle,
  CheckCircle2,
  FileCheck,
  Send,
  Sparkles,
} from 'lucide-react';
import { DAMAGE_CLASSES } from '../constants';

export function DataQualityView({
  metrics,
  isAuthorityUser,
  onSubmitFeedback,
  lang = 'fr',
}) {
  const [feedbackCaseId, setFeedbackCaseId] = useState('');
  const [feedbackType, setFeedbackType] = useState('false_positive');
  const [feedbackComment, setFeedbackComment] = useState('');
  const [feedbackSuccess, setFeedbackSuccess] = useState(false);

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!feedbackCaseId.trim()) return;
    if (onSubmitFeedback) {
      onSubmitFeedback({
        caseId: feedbackCaseId.trim(),
        type: feedbackType,
        comment: feedbackComment,
        timestamp: new Date().toISOString(),
      });
      setFeedbackSuccess(true);
      setTimeout(() => {
        setFeedbackSuccess(false);
        setFeedbackCaseId('');
        setFeedbackComment('');
      }, 3000);
    }
  };

  return (
    <div className="data-quality-container">
      <div className="section-intro">
        <div className="intro-title-row">
          <Cpu size={20} color="var(--color-primary)" />
          <div>
            <h2 style={{ fontSize: '1.1rem', fontWeight: 800 }}>
              {lang === 'fr' ? 'Télémétrie IA et assurance qualité terrain' : 'AI Model Telemetry & Field Quality Assurance'}
            </h2>
            <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '2px' }}>
              {lang === 'fr'
                ? 'Parts des confiances et des précisions GPS déjà stockées. Ce n’est pas une précision, un rappel ou un mAP mesuré.'
                : 'Shares of confidences and GPS accuracies already stored. This is not measured precision, recall, or mAP.'}
            </p>
          </div>
        </div>
      </div>

      <div className="quality-grid-two">
        {/* Left Column: AI Model Telemetry */}
        <div className="quality-card">
          <div className="quality-card-header">
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Sparkles size={16} color="var(--color-primary)" />
              <h3 style={{ fontSize: '0.92rem', fontWeight: 700 }}>
                {lang === 'fr' ? 'Confiances stockées' : 'Stored detection confidence'}
              </h3>
            </div>
            <span className="bundle-badge mono">
              {lang === 'fr' ? 'Observations stockées' : 'Stored observations'}
            </span>
          </div>

          {(metrics.scoredDetectionCount || 0) === 0 ? (
            <div className="metric-unavailable" role="status">
              <strong>Not available</strong>
              <span>
                {lang === 'fr'
                  ? 'Aucune confiance de détection stockée à résumer.'
                  : 'No stored detection confidences to summarize.'}
              </span>
            </div>
          ) : (
            <div className="confidence-breakdown">
              <ConfidenceBar
                label={lang === 'fr' ? 'Haute (≥ 65 %)' : 'High (≥ 65%)'}
                percent={metrics.highConfidencePercent}
                count={metrics.highConfidenceCount}
                color="var(--color-success)"
              />
              <ConfidenceBar
                label={lang === 'fr' ? 'Moyenne (45–65 %)' : 'Medium (45–65%)'}
                percent={metrics.mediumConfidencePercent}
                count={metrics.mediumConfidenceCount}
                color="var(--color-warning)"
              />
              <ConfidenceBar
                label={lang === 'fr' ? 'Faible (< 45 %)' : 'Low (< 45%)'}
                percent={metrics.lowConfidencePercent}
                count={metrics.lowConfidenceCount}
                color="#EF4444"
              />
              <p style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginTop: '8px' }}>
                {lang === 'fr'
                  ? 'Part des scores déjà enregistrés. Ce n’est pas une précision ni un mAP.'
                  : 'Share of scores already stored. This is not precision or mAP.'}
              </p>
            </div>
          )}

          <div className="class-dist-section">
            <h4 style={{ fontSize: '0.8rem', fontWeight: 700, marginBottom: '8px' }}>
              {lang === 'fr' ? 'Codes de classe stockés' : 'Stored class codes'}
            </h4>
            <p style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginBottom: '8px' }}>
              {lang === 'fr'
                ? 'Le nom courant de ces codes n’est pas vérifié. Seul le code stocké est affiché.'
                : 'Common names for these codes are not verified. Only the stored code is shown.'}
            </p>
            <div className="class-pills-row">
              {Object.entries(metrics.classesBreakdown || {}).map(([code, count]) => {
                const cls = DAMAGE_CLASSES[code] || { color: '#64748b' };
                return (
                  <div key={code} className="class-dist-chip" style={{ borderColor: `${cls.color}40` }}>
                    <span className="chip-code" style={{ color: cls.color }}>{code}</span>
                    <strong className="chip-count mono">{count}</strong>
                  </div>
                );
              })}
              {(metrics.unspecifiedClassCount || 0) > 0 && (
                <div className="class-dist-chip">
                  <span className="chip-code">—</span>
                  <span className="chip-name">{lang === 'fr' ? 'Sans code' : 'Unspecified'}</span>
                  <strong className="chip-count mono">{metrics.unspecifiedClassCount}</strong>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Right Column: GNSS & Media Integrity */}
        <div className="quality-card">
          <div className="quality-card-header">
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Compass size={16} color="var(--color-primary)" />
              <h3 style={{ fontSize: '0.92rem', fontWeight: 700 }}>
                {lang === 'fr' ? 'Intégrité géodésique et médias terrain' : 'GNSS & Field Media Integrity'}
              </h3>
            </div>
          </div>

          <div className="gnss-metrics-wrap">
            {(metrics.gpsSampleCount || 0) === 0 ? (
              <div className="metric-unavailable" role="status">
                <strong>Not available</strong>
                <span>
                  {lang === 'fr'
                    ? 'Aucune précision GPS (accuracy_meters) n’est stockée sur ces observations.'
                    : 'No stored GPS accuracy (accuracy_meters) on these observations.'}
                </span>
              </div>
            ) : (
              <div className="gnss-row">
                <div className="gnss-icon-box" style={{ background: 'rgba(239, 68, 68, 0.1)', color: '#EF4444' }}>
                  <AlertTriangle size={18} />
                </div>
                <div className="gnss-info">
                  <div className="gnss-label-row">
                    <span>{lang === 'fr' ? 'Précision GPS stockée > 25 m' : 'Stored GPS accuracy > 25 m'}</span>
                    <strong className="mono">{metrics.poorGpsPercent}% ({metrics.poorGpsCount})</strong>
                  </div>
                  <div className="bar-track">
                    <div className="bar-fill" style={{ width: `${metrics.poorGpsPercent}%`, background: '#EF4444' }} />
                  </div>
                </div>
              </div>
            )}

            {metrics.hasMediaPercent == null ? (
              <div className="metric-unavailable" role="status">
                <strong>Not available</strong>
                <span>
                  {lang === 'fr'
                    ? 'Aucun chemin média stocké à compter.'
                    : 'No stored media paths to count.'}
                </span>
              </div>
            ) : (
              <div className="gnss-row">
                <div className="gnss-icon-box" style={{ background: 'rgba(59, 130, 246, 0.1)', color: '#3B82F6' }}>
                  <Camera size={18} />
                </div>
                <div className="gnss-info">
                  <div className="gnss-label-row">
                    <span>{lang === 'fr' ? 'Observations avec un chemin média stocké' : 'Observations with a stored media path'}</span>
                    <strong className="mono">{metrics.hasMediaPercent}% ({metrics.hasMediaCount})</strong>
                  </div>
                  <div className="bar-track">
                    <div className="bar-fill" style={{ width: `${metrics.hasMediaPercent}%`, background: '#3B82F6' }} />
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* Authority Model Feedback Form */}
          {isAuthorityUser && (
            <div className="authority-feedback-box">
              <h4 style={{ fontSize: '0.8rem', fontWeight: 700, marginBottom: '6px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                <MessageSquare size={13} color="var(--color-primary)" />
                <span>{lang === 'fr' ? 'Signalement d\'anomalie de détection IA (Autorité)' : 'AI Model Feedback'}</span>
              </h4>

              {feedbackSuccess ? (
                <div className="feedback-success-msg">
                  <CheckCircle2 size={16} />
                  <span>{lang === 'fr' ? 'Noté dans cette session seulement. Rien n’est envoyé à un jeu d’entraînement.' : 'Noted in this session only. Nothing is sent to a training set.'}</span>
                </div>
              ) : (
                <form onSubmit={handleSubmit} className="feedback-form">
                  <div className="form-row-compact">
                    <input
                      type="text"
                      className="search-input"
                      style={{ fontSize: '0.78rem' }}
                      placeholder={lang === 'fr' ? 'ID du cas (ex: 8 char)...' : 'Case ID...'}
                      value={feedbackCaseId}
                      onChange={(e) => setFeedbackCaseId(e.target.value)}
                      required
                    />
                    <select
                      className="select-input"
                      style={{ fontSize: '0.78rem' }}
                      value={feedbackType}
                      onChange={(e) => setFeedbackType(e.target.value)}
                    >
                      <option value="false_positive">{lang === 'fr' ? 'Faux positif (pas d\'anomalie)' : 'False positive'}</option>
                      <option value="wrong_class">{lang === 'fr' ? 'Classe incorrecte' : 'Wrong class'}</option>
                      <option value="bad_box">{lang === 'fr' ? 'Boîte englobante décalée' : 'Bad bounding box'}</option>
                    </select>
                  </div>
                  <div className="form-row-compact" style={{ marginTop: '6px' }}>
                    <input
                      type="text"
                      className="search-input"
                      style={{ fontSize: '0.78rem', flex: 1 }}
                      placeholder={lang === 'fr' ? 'Observation technique pour l\'équipe data...' : 'Technical note...'}
                      value={feedbackComment}
                      onChange={(e) => setFeedbackComment(e.target.value)}
                    />
                    <button type="submit" className="btn btn-primary btn-sm">
                      <Send size={12} />
                      <span>{lang === 'fr' ? 'Transmettre' : 'Submit'}</span>
                    </button>
                  </div>
                </form>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function ConfidenceBar({ label, percent, count, color }) {
  const width = Number.isFinite(percent) ? percent : 0;
  return (
    <div className="confidence-stat-item">
      <div className="conf-header">
        <span className="conf-label">{label}</span>
        <strong className="conf-val" style={{ color }}>
          {percent == null ? '—' : `${percent}%`} ({count || 0})
        </strong>
      </div>
      <div className="bar-track">
        <div className="bar-fill" style={{ width: `${width}%`, background: color }} />
      </div>
    </div>
  );
}
