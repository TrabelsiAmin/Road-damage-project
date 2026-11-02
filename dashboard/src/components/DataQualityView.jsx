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
                ? 'Surveillance de la calibration des réseaux de neurones embarqués (TFLite), de la distribution de confiance et de l\'intégrité géodésique GNSS.'
                : 'Edge TFLite model inference calibration, confidence telemetry, and field GNSS GPS integrity.'}
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
                {lang === 'fr' ? 'Précision et confiance des inférences TFLite' : 'TFLite Inference Confidence'}
              </h3>
            </div>
            <span className="bundle-badge mono">Bundle v2.1 RoadSense</span>
          </div>

          <div className="confidence-breakdown">
            <div className="confidence-stat-item">
              <div className="conf-header">
                <span className="conf-label">{lang === 'fr' ? 'Haute confiance (>80%)' : 'High confidence (>80%)'}</span>
                <strong className="conf-val" style={{ color: 'var(--color-success)' }}>
                  {metrics.highConfidencePct}% ({metrics.highConfidenceCount})
                </strong>
              </div>
              <div className="bar-track">
                <div
                  className="bar-fill"
                  style={{ width: `${metrics.highConfidencePct}%`, background: 'var(--color-success)' }}
                />
              </div>
            </div>

            <div className="confidence-stat-item">
              <div className="conf-header">
                <span className="conf-label">{lang === 'fr' ? 'Confiance moyenne (50-80%)' : 'Medium confidence (50-80%)'}</span>
                <strong className="conf-val" style={{ color: 'var(--color-warning)' }}>
                  {metrics.mediumConfidencePct}% ({metrics.mediumConfidenceCount})
                </strong>
              </div>
              <div className="bar-track">
                <div
                  className="bar-fill"
                  style={{ width: `${metrics.mediumConfidencePct}%`, background: 'var(--color-warning)' }}
                />
              </div>
            </div>

            <div className="confidence-stat-item">
              <div className="conf-header">
                <span className="conf-label">{lang === 'fr' ? 'Faible confiance (<50%)' : 'Low confidence (<50%)'}</span>
                <strong className="conf-val" style={{ color: '#EF4444' }}>
                  {metrics.lowConfidencePct}% ({metrics.lowConfidenceCount})
                </strong>
              </div>
              <div className="bar-track">
                <div
                  className="bar-fill"
                  style={{ width: `${metrics.lowConfidencePct}%`, background: '#EF4444' }}
                />
              </div>
            </div>
          </div>

          {/* Model Class Distribution */}
          <div className="class-dist-section">
            <h4 style={{ fontSize: '0.8rem', fontWeight: 700, marginBottom: '8px' }}>
              {lang === 'fr' ? 'Distribution des classes détectées' : 'Detected Classes Distribution'}
            </h4>
            <div className="class-pills-row">
              {Object.entries(metrics.classDistribution || {}).map(([code, count]) => {
                const cls = DAMAGE_CLASSES[code] || { fr: code, color: '#64748b' };
                return (
                  <div key={code} className="class-dist-chip" style={{ borderColor: `${cls.color}40` }}>
                    <span className="chip-code" style={{ color: cls.color }}>{code}</span>
                    <span className="chip-name">{lang === 'fr' ? cls.fr : code}</span>
                    <strong className="chip-count mono">{count}</strong>
                  </div>
                );
              })}
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
            <div className="gnss-row">
              <div className="gnss-icon-box" style={{ background: 'rgba(16, 185, 129, 0.1)', color: '#10B981' }}>
                <CheckCircle2 size={18} />
              </div>
              <div className="gnss-info">
                <div className="gnss-label-row">
                  <span>{lang === 'fr' ? 'Positions GPS haute précision (<15m)' : 'High accuracy GPS (<15m)'}</span>
                  <strong className="mono">{metrics.goodGpsPct}%</strong>
                </div>
                <div className="bar-track">
                  <div className="bar-fill" style={{ width: `${metrics.goodGpsPct}%`, background: '#10B981' }} />
                </div>
              </div>
            </div>

            <div className="gnss-row">
              <div className="gnss-icon-box" style={{ background: 'rgba(239, 68, 68, 0.1)', color: '#EF4444' }}>
                <AlertTriangle size={18} />
              </div>
              <div className="gnss-info">
                <div className="gnss-label-row">
                  <span>{lang === 'fr' ? 'Positions GPS imprécises (>25m, exclues de la carte)' : 'Inaccurate GPS (>25m)'}</span>
                  <strong className="mono">{metrics.poorGpsPct}% ({metrics.poorGpsCount})</strong>
                </div>
                <div className="bar-track">
                  <div className="bar-fill" style={{ width: `${metrics.poorGpsPct}%`, background: '#EF4444' }} />
                </div>
              </div>
            </div>

            <div className="gnss-row">
              <div className="gnss-icon-box" style={{ background: 'rgba(59, 130, 246, 0.1)', color: '#3B82F6' }}>
                <Camera size={18} />
              </div>
              <div className="gnss-info">
                <div className="gnss-label-row">
                  <span>{lang === 'fr' ? 'Clichés originaux certifiés rattachés' : 'Certified photos attached'}</span>
                  <strong className="mono">{metrics.hasMediaPct}%</strong>
                </div>
                <div className="bar-track">
                  <div className="bar-fill" style={{ width: `${metrics.hasMediaPct}%`, background: '#3B82F6' }} />
                </div>
              </div>
            </div>
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
                  <span>{lang === 'fr' ? 'Feedback enregistré pour le réentraînement du modèle.' : 'Feedback recorded for retraining.'}</span>
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
