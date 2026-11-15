import React from 'react';
import {
  AlertTriangle,
  BookOpen,
  Calendar,
  MapPin,
  Route,
} from 'lucide-react';
import { buildOverviewPresentation } from '../utils/overviewPresentation';
import { approximateRoadNote } from '../utils/tunisiaGeo';

const COPY = {
  fr: {
    total: 'Total des incidents',
    totalHelp: 'Signalements non rejetés dans le filtre.',
    vs: 'par rapport à la période précédente',
    routes: 'Routes concernées',
    routesHelp: 'Voies approximatives, déduites des coordonnées.',
    zones: 'Zones concernées',
    zonesHelp: 'Gouvernorats déduits des coordonnées.',
    latest: 'Dernier incident recensé',
    latestMissing: 'Aucune date enregistrée',
    latestHidden: 'Dossier individuel non visible',
    unavailable: 'Indisponible',
    loading: 'Chargement…',
    hole: 'incidents',
    regionTitle: 'Incidents par gouvernorat',
    regionHelp: 'Déduit du point le plus proche. Le gouvernorat n’est pas un champ enregistré.',
    regionEmpty: 'Aucun point localisé dans cette vue.',
    chartEmpty: 'Aucune classe ou priorité enregistrée dans cette vue.',
    assistant: 'Assistant intelligent',
    assistantPrompt: 'Posez une question sur les manuels de pathologie routière.',
    more: 'Pour en savoir plus',
    moreHelp: 'Ouvrir Rapports et synthèse.',
    recent: 'Derniers incidents',
    seeAll: 'Voir tous les incidents',
    date: 'Date',
    road: 'Route / Lieu',
    class: 'Classe',
    status: 'Statut',
    owner: 'Responsable',
    restrictedTitle: 'Dossiers individuels réservés',
    restrictedBody: 'Les lignes individuelles restent réservées aux comptes autorisés.',
    listMissingTitle: 'Liste détaillée non chargée',
    listMissingBody: 'Le total vient du catalogue visible. Les dossiers individuels ne sont pas dans la liste chargée.',
    emptyTitle: 'Aucun incident',
    emptyBody: 'Aucun signalement non rejeté dans cette période.',
    unavailableBody: 'Les totaux ne sont pas disponibles.',
    roadNote: approximateRoadNote('fr'),
    publicTitle: 'Signalements publics',
    publicHelp: 'Articles et communiqués ouverts sur le web. Ils restent séparés du catalogue TariqMap et ne changent pas les totaux.',
    publicEmpty: 'Aucun signalement public cité.',
    publicSource: 'Source',
    publicShow: 'Voir sur la carte',
  },
  en: {
    total: 'Total incidents',
    totalHelp: 'Non-rejected reports in the current filter.',
    vs: 'versus the previous period',
    routes: 'Routes concerned',
    routesHelp: 'Approximate roads, derived from coordinates.',
    zones: 'Zones concerned',
    zonesHelp: 'Governorates derived from coordinates.',
    latest: 'Latest recorded incident',
    latestMissing: 'No date recorded',
    latestHidden: 'Individual case is hidden',
    unavailable: 'Unavailable',
    loading: 'Loading…',
    hole: 'incidents',
    regionTitle: 'Incidents by governorate',
    regionHelp: 'Derived from the nearest point. Governorate is not a stored field.',
    regionEmpty: 'No located point in this view.',
    chartEmpty: 'No class or priority is recorded in this view.',
    assistant: 'Intelligent assistant',
    assistantPrompt: 'Ask a question about the road-pathology manuals.',
    more: 'Learn more',
    moreHelp: 'Open Reports and synthesis.',
    recent: 'Latest incidents',
    seeAll: 'See all incidents',
    date: 'Date',
    road: 'Road / Place',
    class: 'Class',
    status: 'Status',
    owner: 'Organization',
    restrictedTitle: 'Individual cases are reserved',
    restrictedBody: 'Individual rows stay with authorized accounts.',
    listMissingTitle: 'Detailed list not loaded',
    listMissingBody: 'The total comes from the visible catalogue. Individual cases are not in the loaded list.',
    emptyTitle: 'No incidents',
    emptyBody: 'No non-rejected report in this period.',
    unavailableBody: 'The totals are not available.',
    roadNote: approximateRoadNote('en'),
    publicTitle: 'Public reports',
    publicHelp: 'News and notices opened on the web. They stay separate from the TariqMap catalogue and do not change the totals.',
    publicEmpty: 'No cited public report.',
    publicSource: 'Source',
    publicShow: 'Show on map',
  },
};

function formatPct(pct) {
  const sign = pct > 0 ? '+' : '';
  const rounded = Math.round(pct * 10) / 10;
  return `${sign}${rounded}%`;
}

function figureText(status, value, copy) {
  if (status === 'loading') return copy.loading;
  if (status !== 'ready' || value == null) return copy.unavailable;
  return String(value);
}

function Donut({ chart, hole, caption }) {
  const slices = chart?.slices || [];
  const sum = slices.reduce((total, slice) => total + slice.value, 0);
  if (!chart || sum <= 0) return null;
  let cursor = 0;
  const stops = slices.map((slice) => {
    const start = cursor;
    cursor += (slice.value / sum) * 100;
    return `${slice.color} ${start}% ${cursor}%`;
  }).join(', ');
  const label = slices.map((slice) => `${slice.label} ${slice.value}`).join(', ');
  return (
    <div className="ov-donut-wrap">
      <div className="ov-donut" style={{ background: `conic-gradient(${stops})` }} role="img" aria-label={label}>
        <div className="ov-donut-hole">
          <strong>{hole}</strong>
          <span>{caption}</span>
        </div>
      </div>
      <ul className="ov-legend">
        {slices.map((slice) => (
          <li key={slice.key}>
            <i style={{ background: slice.color }} />
            <span>{slice.label}</span>
            <strong>{slice.percent}%</strong>
          </li>
        ))}
      </ul>
    </div>
  );
}

function RegionBars({ regions, emptyLabel }) {
  if (!regions || regions.length === 0) return <p className="ov-empty">{emptyLabel}</p>;
  const max = Math.max(...regions.map((region) => region.value), 1);
  return (
    <div className="ov-bars" role="img" aria-label={regions.map((region) => `${region.label} ${region.value}`).join(', ')}>
      {regions.map((region) => (
        <div key={region.key} className="ov-bar-row">
          <span className="ov-bar-label">{region.label}</span>
          <span className="ov-bar-track">
            <span className="ov-bar-fill" style={{ width: `${(region.value / max) * 100}%` }} />
          </span>
          <strong>{region.value}</strong>
        </div>
      ))}
    </div>
  );
}

export function OverviewBoard({
  observations = [],
  canSeeRows = false,
  figureStatus = 'unavailable',
  publicSummary = [],
  publicCells = [],
  comparison = null,
  authorityTotal = null,
  authorityClassCounts = null,
  authorityPriorityCounts = null,
  organizations = [],
  catalogueTotal = null,
  catalogueStats = null,
  catalogueFloor = null,
  loadedCount = 0,
  listTruncated = false,
  note = null,
  lang = 'fr',
  onOpenReports,
  onOpenIncidents,
  onOpenObservation,
  onRetainObservation,
  assistant = null,
  publicReports = [],
  onFocusPublicReport,
}) {
  const copy = COPY[lang] || COPY.fr;
  const view = buildOverviewPresentation({
    observations,
    canSeeRows,
    figureStatus,
    publicSummary,
    publicCells,
    comparison,
    authorityTotal,
    authorityClassCounts,
    authorityPriorityCounts,
    organizations,
    catalogueTotal,
    catalogueStats,
    catalogueFloor,
    loadedCount,
    listTruncated,
    lang,
  });
  const ready = view.status === 'ready';
  const latestValue = !canSeeRows
    ? copy.unavailable
    : figureText(view.status, view.lastIncident ? view.lastIncident.dateLabel : null, copy);
  const latestSub = !canSeeRows
    ? copy.latestHidden
    : (view.lastIncident?.place || (ready ? copy.latestMissing : copy.totalHelp));

  return (
    <>
      <section className="ov-kpis" aria-label={copy.total}>
        <div className="ov-kpi-grid">
          <article className="ov-kpi">
            <span className="ov-kpi-icon ov-kpi-icon-alert"><AlertTriangle size={16} /></span>
            <p className="ov-kpi-label">{copy.total}</p>
            <p className="ov-kpi-value">{figureText(view.status, view.total, copy)}</p>
            {view.delta && (
              <p className={`ov-kpi-delta ${view.delta.pct >= 0 ? 'is-up' : 'is-down'}`}>
                {formatPct(view.delta.pct)}
                <span>{copy.vs}</span>
              </p>
            )}
            <p className="ov-kpi-sub">{view.totalNote || copy.totalHelp}</p>
          </article>
          <article className="ov-kpi">
            <span className="ov-kpi-icon ov-kpi-icon-blue"><Route size={16} /></span>
            <p className="ov-kpi-label">{copy.routes}</p>
            <p className="ov-kpi-value">{figureText(view.status, view.routeCount, copy)}</p>
            <p className="ov-kpi-sub">{copy.routesHelp}</p>
          </article>
          <article className="ov-kpi">
            <span className="ov-kpi-icon ov-kpi-icon-blue"><MapPin size={16} /></span>
            <p className="ov-kpi-label">{copy.zones}</p>
            <p className="ov-kpi-value">{figureText(view.status, view.zoneCount, copy)}</p>
            <p className="ov-kpi-sub">{copy.zonesHelp}</p>
          </article>
          <article className="ov-kpi">
            <span className="ov-kpi-icon ov-kpi-icon-blue"><Calendar size={16} /></span>
            <p className="ov-kpi-label">{copy.latest}</p>
            <p className={`ov-kpi-value ${canSeeRows && view.lastIncident ? 'ov-kpi-value-date' : ''}`}>{latestValue}</p>
            <p className="ov-kpi-sub">{latestSub}</p>
          </article>
        </div>
        {note && <p className="ov-public-note">{note}</p>}
      </section>

      <section className="ov-charts">
        <article className="ov-card">
          <h2>{view.chart?.title || (lang === 'fr' ? 'Répartition par classe' : 'Split by class')}</h2>
          {view.chart ? (
            <Donut chart={view.chart} hole={view.total} caption={copy.hole} />
          ) : (
            <p className="ov-empty">{ready ? copy.chartEmpty : figureText(view.status, null, copy)}</p>
          )}
        </article>
        <article className="ov-card">
          <h2>{copy.regionTitle}</h2>
          <p className="ov-card-help">{copy.regionHelp}</p>
          <RegionBars regions={view.regions} emptyLabel={ready ? copy.regionEmpty : figureText(view.status, null, copy)} />
        </article>
      </section>

      <aside className="ov-assist ov-card">
        <div className="ov-assist-head">
          <span className="ov-kpi-icon ov-kpi-icon-blue"><BookOpen size={16} /></span>
          <div>
            <h2>{copy.assistant}</h2>
            <p>{copy.assistantPrompt}</p>
          </div>
        </div>
        <div className="ov-assist-body">{assistant}</div>
        <button type="button" className="ov-more" onClick={onOpenReports}>
          <strong>{copy.more}</strong>
          <span>{copy.moreHelp}</span>
        </button>
      </aside>

      <section className="ov-public-reports ov-card" data-public-reports="true" aria-labelledby="public-reports-title">
        <h2 id="public-reports-title">{copy.publicTitle}</h2>
        <p className="ov-card-help">{copy.publicHelp}</p>
        {publicReports.length === 0 ? (
          <p className="ov-empty">{copy.publicEmpty}</p>
        ) : (
          <ul className="ov-public-list">
            {publicReports.map((item) => (
              <li key={item.id}>
                <div className="ov-public-main">
                  <strong>{item.title}</strong>
                  <span>{item.place}</span>
                  <q>{item.quote}</q>
                  <span className="ov-public-meta">
                    {item.dateLabel || '—'}
                    {item.dateNote ? ` — ${item.dateNote}` : ''}
                  </span>
                  <span className="ov-public-meta">{item.publicNote}</span>
                  <span className="ov-public-meta">{item.placementNote}</span>
                </div>
                <div className="ov-public-side">
                  <span className="ov-public-source">{copy.publicSource}</span>
                  {item.sources.map((source) => (
                    <a key={source.url} href={source.url} target="_blank" rel="noopener noreferrer">
                      {source.name}
                    </a>
                  ))}
                  {item.onMap && item.focus && (
                    <button type="button" className="ov-text-btn" onClick={() => onFocusPublicReport?.(item.focus)}>
                      {copy.publicShow}
                    </button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="ov-table-card ov-card">
        <div className="ov-table-head">
          <h2>{copy.recent}</h2>
          {canSeeRows && (
            <button type="button" className="ov-text-btn" onClick={onOpenIncidents}>{copy.seeAll}</button>
          )}
        </div>
        {view.tableState === 'rows' ? (
          <div className="ov-table-scroll">
            <table className="ov-table">
              <thead>
                <tr>
                  <th>{copy.date}</th>
                  <th>{copy.road}</th>
                  <th>{copy.class}</th>
                  <th>{copy.status}</th>
                  <th>{copy.owner}</th>
                </tr>
              </thead>
              <tbody>
                {view.rows.map((row) => (
                  <tr
                    key={row.id || `${row.dateLabel}-${row.classCode}`}
                    className={onRetainObservation ? 'ov-row-selectable' : undefined}
                    onClick={() => onRetainObservation && row.id && onRetainObservation(row.id)}
                  >
                    <td>{row.dateLabel || '—'}</td>
                    <td>
                      <button
                        type="button"
                        className="ov-place"
                        title={copy.roadNote}
                        onClick={(event) => {
                          event.stopPropagation();
                          if (onRetainObservation && row.id) onRetainObservation(row.id);
                          else if (onOpenObservation && row.id) onOpenObservation(row.id);
                        }}
                      >
                        <strong>{row.road || '—'}</strong>
                        <span>{row.place || '—'}</span>
                      </button>
                    </td>
                    <td><span className="ov-code">{row.classCode}</span></td>
                    <td><span className={`ov-status ov-status-${row.status}`}>{row.statusLabel}</span></td>
                    <td>{row.organization || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="ov-table-empty">
            <strong>
              {view.tableState === 'restricted'
                ? copy.restrictedTitle
                : view.tableState === 'listMissing'
                  ? copy.listMissingTitle
                  : view.tableState === 'empty'
                    ? copy.emptyTitle
                    : copy.unavailable}
            </strong>
            <p>
              {view.tableState === 'restricted'
                ? copy.restrictedBody
                : view.tableState === 'listMissing'
                  ? copy.listMissingBody
                  : view.tableState === 'empty'
                    ? copy.emptyBody
                    : view.tableState === 'loading'
                      ? copy.loading
                      : copy.unavailableBody}
            </p>
          </div>
        )}
      </section>
    </>
  );
}
