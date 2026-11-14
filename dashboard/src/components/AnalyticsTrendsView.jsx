import React from 'react';
import {
  BarChart3,
  TrendingUp,
  MapPin,
  Clock,
  CheckCircle2,
  AlertTriangle,
  ArrowUpRight,
  ArrowDownRight,
  Calendar,
} from 'lucide-react';

export function AnalyticsTrendsView({
  regionalBacklog = [],
  timeSeries = [],
  kpis,
  lang = 'fr',
}) {
  // Compute max values for relative CSS bar widths
  const maxBacklog = Math.max(...regionalBacklog.map((r) => r.backlog), 1);
  const maxTimeVal = Math.max(
    ...timeSeries.map((t) => Math.max(t.newReports, t.repaired)),
    1
  );

  return (
    <div className="analytics-trends-container">
      <div className="section-intro">
        <div className="intro-title-row">
          <BarChart3 size={20} color="var(--color-primary)" />
          <div>
            <h2 style={{ fontSize: '1.1rem', fontWeight: 800 }}>
              {lang === 'fr' ? 'Tendances et analytique de maintenance' : 'Maintenance Trends & Analytics'}
            </h2>
            <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '2px' }}>
              {lang === 'fr'
                ? 'Évolution temporelle du carnet de travail (nouveaux vs réparés) et répartition territoriale de la dette d\'infrastructure.'
                : 'Backlog evolution (new vs repaired) and territorial infrastructure maintenance distribution.'}
            </p>
          </div>
        </div>
      </div>

      <div className="analytics-grid-two">
        {/* Left Column: New vs Repaired Time Series */}
        <div className="analytics-card">
          <div className="analytics-card-header">
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <TrendingUp size={16} color="var(--color-primary)" />
              <h3 style={{ fontSize: '0.92rem', fontWeight: 700 }}>
                {lang === 'fr' ? 'Évolution du carnet : Nouveaux vs Réparés (6 mois)' : 'Backlog Evolution: New vs Repaired (6 months)'}
              </h3>
            </div>
            <div className="chart-legend-inline">
              <span className="legend-dot" style={{ background: '#3B82F6' }} />
              <span>{lang === 'fr' ? 'Nouveaux' : 'New'}</span>
              <span className="legend-dot" style={{ background: '#10B981', marginLeft: '8px' }} />
              <span>{lang === 'fr' ? 'Réparés' : 'Repaired'}</span>
            </div>
          </div>

          <div className="time-series-bars-wrap">
            {timeSeries.map((entry) => {
              const newPct = Math.round((entry.newReports / maxTimeVal) * 100);
              const repPct = Math.round((entry.repaired / maxTimeVal) * 100);
              const delta = entry.newReports - entry.repaired;
              return (
                <div key={entry.month} className="time-series-row">
                  <div className="time-month-label mono">{entry.label}</div>
                  <div className="time-bars-group">
                    <div className="bar-track">
                      <div
                        className="bar-fill bar-fill-new"
                        style={{ width: `${Math.max(newPct, 4)}%` }}
                        title={`${entry.newReports} nouveaux signalements`}
                      >
                        <span className="bar-value">{entry.newReports}</span>
                      </div>
                    </div>
                    <div className="bar-track">
                      <div
                        className="bar-fill bar-fill-repaired"
                        style={{ width: `${Math.max(repPct, 4)}%` }}
                        title={`${entry.repaired} réparations certifiées`}
                      >
                        <span className="bar-value">{entry.repaired}</span>
                      </div>
                    </div>
                  </div>
                  <div className="time-delta-col">
                    <span className={`delta-tag ${delta > 0 ? 'expanding' : 'shrinking'}`}>
                      {delta > 0 ? `+${delta}` : delta}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>

          <div className="card-footer-note">
            <span style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>
              {lang === 'fr'
                ? 'Un delta positif indique une expansion du backlog (détections supérieures au rythme de réhabilitation).'
                : 'A positive delta indicates backlog expansion.'}
            </span>
          </div>
        </div>

        {/* Right Column: Regional Backlog Ranking */}
        <div className="analytics-card">
          <div className="analytics-card-header">
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <MapPin size={16} color="var(--color-primary)" />
              <h3 style={{ fontSize: '0.92rem', fontWeight: 700 }}>
                {lang === 'fr' ? 'Classement territorial du backlog (Gouvernorats)' : 'Regional Backlog Ranking'}
              </h3>
            </div>
            <span style={{ fontSize: '0.74rem', color: 'var(--text-muted)' }}>
              {regionalBacklog.length} {lang === 'fr' ? 'zones actives' : 'active zones'}
            </span>
          </div>

          <div className="regional-bars-wrap">
            {regionalBacklog.length === 0 ? (
              <div className="panel-empty-state" style={{ height: '180px' }}>
                <p>{lang === 'fr' ? 'Aucun backlog régional pour la sélection actuelle.' : 'No regional backlog.'}</p>
              </div>
            ) : (
              regionalBacklog.slice(0, 8).map((reg, idx) => {
                const widthPct = Math.round((reg.backlog / maxBacklog) * 100);
                return (
                  <div key={reg.governorate} className="regional-bar-row">
                    <div className="regional-name-col">
                      <span className="mono" style={{ fontSize: '0.75rem', color: 'var(--text-dim)', marginRight: '6px' }}>
                        #{idx + 1}
                      </span>
                      <strong style={{ fontSize: '0.8rem' }}>{reg.governorate}</strong>
                    </div>

                    <div className="regional-bar-track">
                      <div
                        className="regional-bar-fill"
                        style={{ width: `${Math.max(widthPct, 6)}%` }}
                      >
                        <span className="regional-bar-val">{reg.backlog}</span>
                      </div>
                    </div>

                    <div className="regional-crit-col">
                      {reg.critical > 0 && (
                        <span className="crit-pill">
                          {reg.critical} {lang === 'fr' ? 'crit.' : 'crit.'}
                        </span>
                      )}
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>

      {/* Age & Resolution Benchmarks Row */}
      <div className="analytics-metrics-strip">
        <div className="strip-metric">
          <Clock size={18} color="#6366F1" />
          <div className="strip-info">
            <span className="strip-label">{lang === 'fr' ? 'Délai moyen de résolution' : 'Avg Resolution Time'}</span>
            <strong className="strip-val">{kpis.avgResolutionDays == null ? (lang === 'fr' ? 'Non calculé' : 'Not calculated') : `${kpis.avgResolutionDays} ${lang === 'fr' ? 'jours' : 'days'}`}</strong>
          </div>
        </div>

        <div className="strip-metric">
          <CheckCircle2 size={18} color="#10B981" />
          <div className="strip-info">
            <span className="strip-label">{lang === 'fr' ? 'Taux de conformité des réparations' : 'Repair Completion Rate'}</span>
            <strong className="strip-val">{kpis.repairCompletionRate == null ? (lang === 'fr' ? 'Non calculé' : 'Not calculated') : `${kpis.repairCompletionRate}%`}</strong>
          </div>
        </div>

        <div className="strip-metric">
          <AlertTriangle size={18} color="#EF4444" />
          <div className="strip-info">
            <span className="strip-label">{lang === 'fr' ? 'Dépassements SLA (>14 jours)' : 'SLA Breaches (>14 days)'}</span>
            <strong className="strip-val">{kpis.overdueCases} {lang === 'fr' ? 'cas' : 'cases'}</strong>
          </div>
        </div>
      </div>
    </div>
  );
}
