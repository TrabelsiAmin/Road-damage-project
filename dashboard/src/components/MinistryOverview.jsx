import React from 'react';
import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';

const COPY = {
  en: {
    kicker: 'Ministry of Equipment',
    title: 'Road Infrastructure Overview',
    subtitle: 'National road condition, critical damage, and repair follow-up from recorded inspections.',
    period: 'Reporting period',
    periods: { all: 'All reports', '7': 'Last 7 days', '30': 'Last 30 days', '90': 'Last 90 days' },
    observations: 'Road damage observations',
    observationsHelp: 'Inspection reports in this period and filter, excluding rejected records.',
    high: 'High-priority hazards',
    highHelp: 'Stored priority HIGH. Score above 65 is used only when a label was not saved.',
    awaiting: 'Awaiting action',
    awaitingHelp: 'Unconfirmed, confirmed, or in progress. Not yet repaired.',
    repaired: 'Repairs recorded',
    repairedHelp: 'Observations an authority account marked repaired.',
    vs: 'Prior window',
    noBaseline: 'No earlier reports to compare.',
    classTitle: 'Damage by classification',
    priorityTitle: 'Priority distribution',
    statusTitle: 'Maintenance status',
    trendTitle: 'Observations over time',
    trendHelp: 'Counts of non-rejected reports. Empty days are real zeros inside the selected window.',
    emptyTrend: 'No dated reports in this period.',
    priorityList: 'Priority interventions',
    priorityEmpty: 'No observations require attention in this view.',
    recent: 'Recent reports',
    recentEmpty: 'No reports in this view.',
    regionTitle: 'Administrative areas',
    regionBody: 'Governorate and road-segment fields are not stored on observations. Use the map for location.',
    syncTitle: 'Operational catalogue',
    syncBody: 'This view reads reports already stored in Supabase. Device upload queues stay on the inspection app.',
    open: 'Open on map',
    ask: 'Technical recommendation',
    empty: 'No road damage observations match these filters.',
    chartEmpty: 'None recorded in this view.',
    loading: 'Loading the road catalogue…',
    retry: 'Try again',
    demo: 'Demo',
    unknownClass: 'Unclassified',
    unknownPriority: 'Unscored',
  },
  fr: {
    kicker: 'Ministère de l\'Équipement',
    title: 'Vue d\'ensemble de l\'infrastructure routière',
    subtitle: 'État du réseau, dommages critiques et suivi des réparations à partir des inspections enregistrées.',
    period: 'Période',
    periods: { all: 'Toute la période', '7': '7 derniers jours', '30': '30 derniers jours', '90': '90 derniers jours' },
    observations: 'Observations de dégradation',
    observationsHelp: 'Rapports de la période et des filtres, hors signalements rejetés.',
    high: 'Dangers prioritaires',
    highHelp: 'Priorité enregistrée HIGH. Un score supérieur à 65 n\'est utilisé que si l\'étiquette est absente.',
    awaiting: 'En attente d\'action',
    awaitingHelp: 'Non confirmé, confirmé ou en cours. Pas encore réparé.',
    repaired: 'Réparations enregistrées',
    repairedHelp: 'Observations marquées réparées par un compte autorité.',
    vs: 'Période précédente',
    noBaseline: 'Aucun rapport antérieur à comparer.',
    classTitle: 'Dégradations par classe',
    priorityTitle: 'Répartition des priorités',
    statusTitle: 'Statut d\'entretien',
    trendTitle: 'Observations dans le temps',
    trendHelp: 'Signalements non rejetés. Les jours vides sont de vrais zéros dans la fenêtre choisie.',
    emptyTrend: 'Aucun rapport daté sur cette période.',
    priorityList: 'Interventions prioritaires',
    priorityEmpty: 'Aucune observation à traiter dans cette vue.',
    recent: 'Rapports récents',
    recentEmpty: 'Aucun rapport dans cette vue.',
    regionTitle: 'Découpage administratif',
    regionBody: 'Le gouvernorat et le tronçon routier ne sont pas enregistrés. La localisation se lit sur la carte.',
    syncTitle: 'Catalogue opérationnel',
    syncBody: 'Cet écran lit les rapports déjà stockés dans Supabase. Les files d\'envoi restent sur l\'application d\'inspection.',
    open: 'Voir sur la carte',
    ask: 'Recommandation technique',
    empty: 'Aucune observation ne correspond à ces filtres.',
    chartEmpty: 'Aucun enregistrement dans cette vue.',
    loading: 'Chargement du catalogue routier…',
    retry: 'Réessayer',
    demo: 'Démo',
    unknownClass: 'Non classé',
    unknownPriority: 'Sans score',
  },
};

const STATUS_ORDER = ['unconfirmed', 'confirmed', 'in_progress', 'repaired', 'rejected'];
const STATUS_COLORS = {
  unconfirmed: '#d97706',
  confirmed: '#1d4ed8',
  in_progress: '#0369a1',
  repaired: '#0f766e',
  rejected: '#64748b',
};
const PRIORITY_ORDER = [
  { key: 'HIGH', color: '#dc2626' },
  { key: 'MEDIUM', color: '#d97706' },
  { key: 'LOW', color: '#0f766e' },
  { key: 'unknown', color: '#64748b' },
];

function formatDelta(pct, previous, copy) {
  if (previous === 0) return copy.noBaseline;
  if (pct == null) return null;
  const sign = pct > 0 ? '+' : '';
  return `${copy.vs}: ${previous} (${sign}${pct}%)`;
}

function BarChart({ items, emptyLabel }) {
  const max = Math.max(1, ...items.map((item) => item.value));
  const hasAny = items.some((item) => item.value > 0);
  if (!hasAny) {
    return <p className="ministry-empty">{emptyLabel}</p>;
  }
  return (
    <div className="ministry-bars" role="img" aria-label={items.map((item) => `${item.label} ${item.value}`).join(', ')}>
      {items.map((item) => (
        <div key={item.key} className="ministry-bar-row">
          <span className="ministry-bar-label">{item.label}</span>
          <span className="ministry-bar-track">
            <span
              className="ministry-bar-fill"
              style={{
                width: item.value > 0 ? `${(item.value / max) * 100}%` : '0%',
                minWidth: item.value > 0 ? 2 : 0,
                background: item.color,
              }}
            />
          </span>
          <strong className="ministry-bar-value">{item.value}</strong>
        </div>
      ))}
    </div>
  );
}

function TrendChart({ trend, emptyLabel }) {
  const buckets = trend?.buckets || [];
  const max = Math.max(1, ...buckets.map((b) => b.count));
  if (buckets.length === 0) return <p className="ministry-empty">{emptyLabel}</p>;
  const step = buckets.length > 16 ? Math.ceil(buckets.length / 8) : 1;
  return (
    <div className="ministry-trend" role="img" aria-label={buckets.map((b) => `${b.label} ${b.count}`).join(', ')}>
      {buckets.map((bucket, index) => (
        <div key={bucket.key} className="ministry-trend-col" title={`${bucket.key}: ${bucket.count}`}>
          <span className="ministry-trend-count">{bucket.count > 0 ? bucket.count : ''}</span>
          <span className="ministry-trend-track">
            <span style={{ height: `${Math.max(bucket.count === 0 ? 2 : 8, (bucket.count / max) * 100)}%` }} />
          </span>
          <span className="ministry-trend-label">{index % step === 0 ? bucket.label : ''}</span>
        </div>
      ))}
    </div>
  );
}

function KpiCard({ label, value, help, delta, tone }) {
  return (
    <article className={`ministry-kpi ministry-kpi-${tone}`}>
      <p className="ministry-kpi-label">{label}</p>
      <p className="ministry-kpi-value">{value}</p>
      <p className="ministry-kpi-help">{help}</p>
      {delta && <p className="ministry-kpi-delta">{delta}</p>}
    </article>
  );
}

function ReportRow({ item, copy, lang, onOpen, onAsk }) {
  const klass = DAMAGE_CLASSES[item.classCode];
  const status = STATUS_LABELS[item.status];
  const coords = item.latitude != null && item.longitude != null
    ? `${item.latitude.toFixed(5)}, ${item.longitude.toFixed(5)}`
    : '—';
  const when = item.createdAt ? new Date(item.createdAt).toLocaleString(lang === 'fr' ? 'fr-TN' : 'en-GB') : '—';
  return (
    <li className="ministry-report">
      <div className="ministry-report-media">
        {item.imageUrl ? (
          <img src={item.imageUrl} alt="" />
        ) : (
          <span>{item.classCode || '—'}</span>
        )}
      </div>
      <div className="ministry-report-body">
        <div className="ministry-report-title">
          <strong style={{ color: klass?.color || '#0b1f33' }}>
            {item.classCode || copy.unknownClass}
            {klass ? ` · ${lang === 'fr' ? klass.fr : klass.en}` : ''}
          </strong>
          {item.isDemo && <span className="badge badge-demo">{copy.demo}</span>}
        </div>
        <p>
          {item.priority || copy.unknownPriority}
          {item.score != null ? ` · ${item.score.toFixed(1)}` : ''}
          {' · '}
          {status ? (lang === 'fr' ? status.fr : status.en) : item.status}
        </p>
        <p className="ministry-report-meta">{when} · {coords}</p>
      </div>
      <div className="ministry-report-actions">
        <button type="button" className="btn btn-secondary" onClick={() => onOpen(item.id)}>
          {copy.open}
        </button>
        {onAsk && (
          <button type="button" className="btn btn-secondary" onClick={() => onAsk(item)}>
            {copy.ask}
          </button>
        )}
      </div>
    </li>
  );
}

export function MinistryOverview({
  overview,
  lang = 'fr',
  period,
  onPeriodChange,
  loading,
  error,
  onRetry,
  onOpenObservation,
  onAskObservation,
}) {
  const copy = COPY[lang] || COPY.fr;
  const comparison = overview?.comparison;
  const noRows = !overview || (overview.total === 0 && overview.rejected === 0);
  const showFigures = Boolean(overview) && !loading && !(error && noRows);

  const classItems = ['D40', 'D20', 'D10', 'D00'].map((code) => ({
    key: code,
    label: `${code} ${lang === 'fr' ? DAMAGE_CLASSES[code].fr : DAMAGE_CLASSES[code].en}`,
    value: overview?.classCounts?.[code] || 0,
    color: DAMAGE_CLASSES[code].color,
  }));
  if ((overview?.classCounts?.other || 0) > 0) {
    classItems.push({
      key: 'other',
      label: copy.unknownClass,
      value: overview.classCounts.other,
      color: '#64748b',
    });
  }

  const priorityItems = PRIORITY_ORDER
    .filter((item) => item.key !== 'unknown' || (overview?.priorityCounts?.unknown || 0) > 0)
    .map((item) => ({
      key: item.key,
      label: item.key === 'unknown' ? copy.unknownPriority : item.key,
      value: overview?.priorityCounts?.[item.key] || 0,
      color: item.color,
    }));

  const statusItems = STATUS_ORDER
    .filter((key) => key !== 'rejected' || (overview?.statusCounts?.rejected || 0) > 0)
    .map((key) => ({
      key,
      label: STATUS_LABELS[key] ? (lang === 'fr' ? STATUS_LABELS[key].fr : STATUS_LABELS[key].en) : key,
      value: overview?.statusCounts?.[key] || 0,
      color: STATUS_COLORS[key] || '#64748b',
    }));

  return (
    <section className="ministry-overview" aria-labelledby="ministry-overview-title">
      <div className="ministry-heading">
        <div>
          <p className="ministry-kicker">{copy.kicker}</p>
          <h2 id="ministry-overview-title">{copy.title}</h2>
          <p className="ministry-subtitle">{copy.subtitle}</p>
        </div>
        <label className="ministry-period">
          <span>{copy.period}</span>
          <select value={period} onChange={(e) => onPeriodChange(e.target.value)}>
            {Object.entries(copy.periods).map(([id, label]) => (
              <option key={id} value={id}>{label}</option>
            ))}
          </select>
        </label>
      </div>

      {loading && <p className="ministry-status">{copy.loading}</p>}
      {error && (
        <div className="ministry-error" role="alert">
          <p>{error}</p>
          <button type="button" className="btn btn-secondary" onClick={onRetry}>{copy.retry}</button>
        </div>
      )}

      {!loading && !error && noRows && (
        <p className="ministry-status">{copy.empty}</p>
      )}

      {showFigures && (
        <>
          <div className="ministry-kpi-grid">
            <KpiCard
              tone="navy"
              label={copy.observations}
              value={overview.total}
              help={copy.observationsHelp}
              delta={comparison && formatDelta(comparison.totalPct, comparison.previousTotal, copy)}
            />
            <KpiCard
              tone="critical"
              label={copy.high}
              value={overview.high}
              help={copy.highHelp}
              delta={comparison && formatDelta(comparison.highPct, comparison.previousHigh, copy)}
            />
            <KpiCard
              tone="warning"
              label={copy.awaiting}
              value={overview.awaiting}
              help={copy.awaitingHelp}
              delta={comparison && formatDelta(comparison.awaitingPct, comparison.previousAwaiting, copy)}
            />
            <KpiCard
              tone="positive"
              label={copy.repaired}
              value={overview.repaired}
              help={copy.repairedHelp}
              delta={comparison && formatDelta(comparison.repairedPct, comparison.previousRepaired, copy)}
            />
          </div>

          <div className="ministry-chart-grid">
            <article className="ministry-panel">
              <h3>{copy.classTitle}</h3>
              <BarChart items={classItems} emptyLabel={copy.chartEmpty} />
            </article>
            <article className="ministry-panel">
              <h3>{copy.priorityTitle}</h3>
              <BarChart items={priorityItems} emptyLabel={copy.chartEmpty} />
            </article>
            <article className="ministry-panel">
              <h3>{copy.statusTitle}</h3>
              <BarChart items={statusItems} emptyLabel={copy.chartEmpty} />
            </article>
            <article className="ministry-panel">
              <h3>{copy.trendTitle}</h3>
              <p className="ministry-panel-help">{copy.trendHelp}</p>
              <TrendChart trend={overview.trend} emptyLabel={copy.emptyTrend} />
            </article>
          </div>

          <div className="ministry-split">
            <article className="ministry-panel">
              <h3>{copy.priorityList}</h3>
              {overview.priorityQueue.length === 0 ? (
                <p className="ministry-empty">{copy.priorityEmpty}</p>
              ) : (
                <ul className="ministry-report-list">
                  {overview.priorityQueue.map((item) => (
                    <ReportRow
                      key={item.id}
                      item={item}
                      copy={copy}
                      lang={lang}
                      onOpen={onOpenObservation}
                      onAsk={onAskObservation}
                    />
                  ))}
                </ul>
              )}
            </article>
            <article className="ministry-panel">
              <h3>{copy.recent}</h3>
              {overview.recent.length === 0 ? (
                <p className="ministry-empty">{copy.recentEmpty}</p>
              ) : (
                <ul className="ministry-report-list">
                  {overview.recent.map((item) => (
                    <ReportRow key={`recent-${item.id}`} item={item} copy={copy} lang={lang} onOpen={onOpenObservation} />
                  ))}
                </ul>
              )}
              <div className="ministry-note">
                <h3>{copy.regionTitle}</h3>
                <p>{copy.regionBody}</p>
                <h3>{copy.syncTitle}</h3>
                <p>{copy.syncBody}</p>
              </div>
            </article>
          </div>
        </>
      )}
    </section>
  );
}
