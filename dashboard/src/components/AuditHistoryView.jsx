import React, { useState } from 'react';
import {
  History,
  ShieldCheck,
  Clock,
  UserCheck,
  Wrench,
  XCircle,
  CheckCircle2,
  Filter,
  Search,
} from 'lucide-react';

export function AuditHistoryView({
  events = [],
  lang = 'fr',
  onSelectCase,
}) {
  const [filterType, setFilterType] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');

  const filteredEvents = events.filter((ev) => {
    if (filterType !== 'all' && ev.event_type !== filterType) return false;
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      const id = String(ev.case_id || ev.observation_id || '').toLowerCase();
      const actor = String(ev.actor_email || ev.actor_name || '').toLowerCase();
      const notes = String(ev.notes || '').toLowerCase();
      return id.includes(q) || actor.includes(q) || notes.includes(q);
    }
    return true;
  });

  const getEventBadge = (type) => {
    switch (type) {
      case 'validation':
      case 'confirm':
        return { label: 'Validation', color: '#10B981', icon: CheckCircle2 };
      case 'assignment':
        return { label: 'Affectation', color: '#3B82F6', icon: UserCheck };
      case 'repair':
        return { label: 'Réparation', color: '#06B6D4', icon: Wrench };
      case 'rejection':
        return { label: 'Rejet', color: '#EF4444', icon: XCircle };
      default:
        return { label: 'Transition', color: '#8B5CF6', icon: History };
    }
  };

  return (
    <div className="audit-history-container">
      <div className="section-intro">
        <div className="intro-title-row">
          <History size={20} color="var(--color-primary)" />
          <div>
            <h2 style={{ fontSize: '1.1rem', fontWeight: 800 }}>
              {lang === 'fr' ? 'Journal d\'audit et traçabilité des décisions' : 'Audit Trail & Decision History'}
            </h2>
            <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '2px' }}>
              {lang === 'fr'
                ? 'Historique immuable de toutes les validations, réaffectations, rejets et vérifications effectués par les autorités assermentées.'
                : 'Immutable audit log of all validations, reassignments, rejections, and verifications by authorized officers.'}
            </p>
          </div>
        </div>
      </div>

      <div className="audit-toolbar">
        <div className="audit-search-wrap">
          <input
            type="text"
            className="search-input"
            placeholder={lang === 'fr' ? 'Rechercher par ID de dossier, agent, note...' : 'Search by case ID, agent, note...'}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>

        <div className="audit-filter-wrap">
          <select
            className="select-input"
            value={filterType}
            onChange={(e) => setFilterType(e.target.value)}
          >
            <option value="all">{lang === 'fr' ? 'Tous les types d\'événements' : 'All event types'}</option>
            <option value="validation">{lang === 'fr' ? 'Validations' : 'Validations'}</option>
            <option value="assignment">{lang === 'fr' ? 'Affectations' : 'Assignments'}</option>
            <option value="repair">{lang === 'fr' ? 'Réparations' : 'Repairs'}</option>
            <option value="rejection">{lang === 'fr' ? 'Rejets' : 'Rejections'}</option>
          </select>
        </div>
      </div>

      <div className="audit-timeline-wrap">
        {filteredEvents.length === 0 ? (
          <div className="panel-empty-state" style={{ height: '220px' }}>
            <History size={32} style={{ opacity: 0.3 }} />
            <p>{lang === 'fr' ? 'Aucun événement d\'audit enregistré pour cette recherche.' : 'No audit events found.'}</p>
          </div>
        ) : (
          <div className="audit-timeline">
            {filteredEvents.map((ev, idx) => {
              const badge = getEventBadge(ev.event_type);
              const Icon = badge.icon;
              const dateStr = ev.created_at ? new Date(ev.created_at).toLocaleString() : '—';
              const caseId = ev.case_id || ev.observation_id || '—';

              return (
                <div key={ev.id || idx} className="audit-timeline-item">
                  <div className="timeline-node" style={{ borderColor: badge.color, color: badge.color }}>
                    <Icon size={14} />
                  </div>

                  <div className="timeline-content">
                    <div className="timeline-header-line">
                      <div className="timeline-badge-group">
                        <span className="event-badge" style={{ color: badge.color, background: `${badge.color}15` }}>
                          {badge.label}
                        </span>
                        <span
                          className="mono case-ref-link"
                          onClick={() => onSelectCase && onSelectCase(caseId)}
                          title="Consulter le dossier"
                        >
                          Dossier #{String(caseId).substring(0, 8)}
                        </span>
                      </div>
                      <span className="timeline-timestamp">{dateStr}</span>
                    </div>

                    <div className="timeline-actor-line">
                      <ShieldCheck size={13} color="var(--color-success)" />
                      <span className="actor-name">{ev.actor_name || ev.actor_email || 'Autorité Voirie'}</span>
                      {ev.actor_role && <span className="actor-role-badge">{ev.actor_role}</span>}
                    </div>

                    {ev.old_status && ev.new_status && (
                      <div className="timeline-transition-line">
                        <span className="mono status-from">{ev.old_status}</span>
                        <span className="arrow-sep">→</span>
                        <span className="mono status-to">{ev.new_status}</span>
                      </div>
                    )}

                    {ev.notes && (
                      <div className="timeline-notes-box">
                        <span className="notes-text">"{ev.notes}"</span>
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
