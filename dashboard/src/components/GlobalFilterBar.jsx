import React from 'react';
import { Filter, RotateCcw, Calendar, MapPin, Tag, Shield, Building2 } from 'lucide-react';
import { ALL_GOVERNORATES, getMunicipalitiesForGovernorate } from '../utils/tunisiaGeo';
import { STATUS_LABELS } from '../constants';

export function GlobalFilterBar({
  filters,
  onChange,
  onReset,
  lang = 'fr',
  totalCount = 0,
  filteredCount = 0,
  organizations = [],
  organizationsUnavailable = false,
}) {
  const municipalities = getMunicipalitiesForGovernorate(filters.governorate);

  const handleFieldChange = (key, value) => {
    const next = { ...filters, [key]: value };
    // If governorate changes, reset municipality
    if (key === 'governorate') {
      next.municipality = 'all';
    }
    onChange(next);
  };

  const isFiltered =
    filters.dateRange !== 'all' ||
    filters.governorate !== 'all' ||
    filters.municipality !== 'all' ||
    filters.anomalyClass !== 'all' ||
    filters.priority !== 'all' ||
    filters.status !== 'all' ||
    filters.organization !== 'all' ||
    filters.includeDemo === true;

  return (
    <div className="command-filter-bar">
      <div className="filter-bar-header">
        <div className="filter-bar-title">
          <Filter size={15} color="var(--color-primary)" />
          <span className="filter-title-text">
            {lang === 'fr' ? 'Filtres opérationnels' : 'Operational Filters'}
          </span>
          <span className="filter-count-badge">
            {filteredCount} / {totalCount} {lang === 'fr' ? 'enregistrements' : 'records'}
          </span>
        </div>

        <div className="filter-date-pills">
          <Calendar size={13} style={{ opacity: 0.6 }} />
          {[
            { id: 'today', fr: 'Aujourd\'hui', en: 'Today' },
            { id: '7d', fr: '7 jours', en: '7 days' },
            { id: '30d', fr: '30 jours', en: '30 days' },
            { id: '90d', fr: '90 jours', en: '90 days' },
            { id: 'year', fr: 'Cette année', en: 'This year' },
            { id: 'all', fr: 'Historique complet', en: 'All time' },
          ].map((pill) => (
            <button
              key={pill.id}
              type="button"
              className={`date-pill ${filters.dateRange === pill.id ? 'active' : ''}`}
              onClick={() => handleFieldChange('dateRange', pill.id)}
            >
              {lang === 'fr' ? pill.fr : pill.en}
            </button>
          ))}
        </div>

        {isFiltered && (
          <button
            type="button"
            className="btn-reset-filters"
            onClick={onReset}
            title={lang === 'fr' ? 'Réinitialiser tous les filtres' : 'Reset all filters'}
          >
            <RotateCcw size={13} />
            <span>{lang === 'fr' ? 'Réinitialiser' : 'Reset'}</span>
          </button>
        )}
      </div>

      <div className="filter-inputs-grid">
        {/* Governorate */}
        <div className="filter-field">
          <label className="filter-label">
            <MapPin size={12} />
            <span>{lang === 'fr' ? 'Gouvernorat' : 'Governorate'}</span>
          </label>
          <select
            className="select-input select-filter"
            value={filters.governorate}
            onChange={(e) => handleFieldChange('governorate', e.target.value)}
          >
            <option value="all">{lang === 'fr' ? 'Tous les gouvernorats' : 'All governorates'}</option>
            {ALL_GOVERNORATES.map((gov) => (
              <option key={gov} value={gov}>
                {gov}
              </option>
            ))}
          </select>
        </div>

        {/* Municipality */}
        <div className="filter-field">
          <label className="filter-label">
            <MapPin size={12} />
            <span>{lang === 'fr' ? 'Délégation / Commune' : 'Municipality'}</span>
          </label>
          <select
            className="select-input select-filter"
            value={filters.municipality}
            disabled={filters.governorate === 'all'}
            onChange={(e) => handleFieldChange('municipality', e.target.value)}
          >
            <option value="all">
              {filters.governorate === 'all'
                ? lang === 'fr'
                  ? 'Sélectionnez un gouvernorat'
                  : 'Select governorate first'
                : lang === 'fr'
                ? 'Toutes les communes'
                : 'All municipalities'}
            </option>
            {municipalities.map((muni) => (
              <option key={muni} value={muni}>
                {muni}
              </option>
            ))}
          </select>
        </div>

        {/* Anomaly Class */}
        <div className="filter-field">
          <label className="filter-label">
            <Tag size={12} />
            <span>{lang === 'fr' ? 'Type d\'anomalie' : 'Anomaly Class'}</span>
          </label>
          <select
            className="select-input select-filter"
            value={filters.anomalyClass}
            onChange={(e) => handleFieldChange('anomalyClass', e.target.value)}
          >
            <option value="all">{lang === 'fr' ? 'Toutes les classes' : 'All classes'}</option>
            {['D40', 'D20', 'D10', 'D00'].map((code) => (
              <option key={code} value={code}>
                {code}
              </option>
            ))}
          </select>
        </div>

        {/* Priority */}
        <div className="filter-field">
          <label className="filter-label">
            <Shield size={12} />
            <span>{lang === 'fr' ? 'Priorité de danger' : 'Priority'}</span>
          </label>
          <select
            className="select-input select-filter"
            value={filters.priority}
            onChange={(e) => handleFieldChange('priority', e.target.value)}
          >
            <option value="all">{lang === 'fr' ? 'Toutes priorités' : 'All priorities'}</option>
            <option value="HIGH">HIGH (Critique &gt;65)</option>
            <option value="MEDIUM">MEDIUM (Moyen 35-65)</option>
            <option value="LOW">LOW (Surveillance &lt;35)</option>
          </select>
        </div>

        {/* Status */}
        <div className="filter-field">
          <label className="filter-label">
            <span>{lang === 'fr' ? 'Statut du cycle de vie' : 'Lifecycle Status'}</span>
          </label>
          <select
            className="select-input select-filter"
            value={filters.status}
            onChange={(e) => handleFieldChange('status', e.target.value)}
          >
            <option value="all">{lang === 'fr' ? 'Tous les statuts' : 'All statuses'}</option>
            {['unconfirmed', 'confirmed', 'in_progress', 'repaired', 'rejected'].map((st) => (
              <option key={st} value={st}>
                {lang === 'fr' ? STATUS_LABELS[st]?.fr || st : STATUS_LABELS[st]?.en || st}
              </option>
            ))}
          </select>
        </div>

        {/* Organization / Service */}
        <div className="filter-field">
          <label className="filter-label">
            <Building2 size={12} />
            <span>{lang === 'fr' ? 'Service / Direction' : 'Organization'}</span>
          </label>
          {organizationsUnavailable ? (
            <p className="filter-note">{lang === 'fr' ? 'Indisponible' : 'Unavailable'}</p>
          ) : (
            <select
              className="select-input select-filter"
              value={filters.organization}
              onChange={(e) => handleFieldChange('organization', e.target.value)}
            >
              <option value="all">{lang === 'fr' ? 'Tous les services' : 'All organizations'}</option>
              {organizations.map((org) => (
                <option key={org.id} value={org.id}>
                  {org.name}
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Demo Toggle */}
        <div className="filter-field filter-field-checkbox">
          <label className="checkbox-label" title="Inclure ou exclure les données de démonstration / bancs d'essai">
            <input
              type="checkbox"
              checked={filters.includeDemo}
              onChange={(e) => handleFieldChange('includeDemo', e.target.checked)}
            />
            <span>{lang === 'fr' ? 'Inclure enregistrements démo' : 'Include demo records'}</span>
          </label>
        </div>
      </div>
    </div>
  );
}
