import { describe, it, expect } from 'vitest';
import React from 'react';
import { renderToString } from 'react-dom/server';
import { StatusBadge } from './StatusBadge';
import { PriorityBadge } from './PriorityBadge';
import { EmptyState } from './EmptyState';
import { StatCard } from './StatCard';
import { Breadcrumbs } from '../layout/Breadcrumbs';

describe('21st.dev UI Components', () => {
  describe('StatusBadge', () => {
    it('renders confirmed status badge in French', () => {
      const html = renderToString(<StatusBadge status="confirmed" lang="fr" />);
      expect(html).toContain('tm-status-badge');
      expect(html).toContain('tm-status-confirmed');
      expect(html).toContain('Confirmé');
    });

    it('renders repaired status badge in English', () => {
      const html = renderToString(<StatusBadge status="repaired" lang="en" />);
      expect(html).toContain('tm-status-badge');
      expect(html).toContain('tm-status-repaired');
      expect(html).toContain('Repaired');
    });

    it('falls back gracefully on unknown status', () => {
      const html = renderToString(<StatusBadge status="unknown_status" lang="fr" />);
      expect(html).toContain('tm-status-badge');
      expect(html).toContain('unknown_status');
    });
  });

  describe('PriorityBadge', () => {
    it('renders CRITICAL priority with score in French', () => {
      const html = renderToString(<PriorityBadge priority="CRITICAL" score={85.4} showScore={true} lang="fr" />);
      expect(html).toContain('tm-priority-badge');
      expect(html).toContain('Critique');
      expect(html).toContain('85');
    });

    it('renders HIGH priority in French without score', () => {
      const html = renderToString(<PriorityBadge priority="HIGH" lang="fr" showScore={false} />);
      expect(html).toContain('tm-priority-badge');
      expect(html).toContain('tm-priority-high');
      expect(html).toContain('Élevée');
    });

    it('renders LOW priority in English', () => {
      const html = renderToString(<PriorityBadge priority="LOW" lang="en" />);
      expect(html).toContain('tm-priority-badge');
      expect(html).toContain('tm-priority-low');
      expect(html).toContain('Low');
    });
  });

  describe('EmptyState', () => {
    it('renders title, description and action button when onAction is provided', () => {
      const html = renderToString(
        <EmptyState
          title="Aucun signalement"
          description="Aucune anomalie trouvée pour cette sélection."
          actionLabel="Réinitialiser"
          onAction={() => {}}
        />
      );
      expect(html).toContain('tm-empty-state');
      expect(html).toContain('Aucun signalement');
      expect(html).toContain('Aucune anomalie trouvée');
      expect(html).toContain('Réinitialiser');
    });
  });

  describe('StatCard', () => {
    it('renders 21st.dev Bento card with delta', () => {
      const html = renderToString(
        <StatCard
          title="Nids-de-poule critiques"
          value={42}
          delta="+5 vs sem. préc."
          deltaType="negative"
          tooltip="Potholes requiring urgent repair"
        />
      );
      expect(html).toContain('tm-stat-card');
      expect(html).toContain('Nids-de-poule critiques');
      expect(html).toContain('42');
      expect(html).toContain('+5 vs sem. préc.');
      expect(html).toContain('tm-delta-negative');
    });
  });

  describe('Breadcrumbs', () => {
    it('renders accessible breadcrumbs navigation', () => {
      const items = [
        { label: 'TariqMap' },
        { label: 'Centre d’opérations' },
      ];
      const html = renderToString(<Breadcrumbs items={items} />);
      expect(html).toContain('tm-breadcrumbs');
      expect(html).toContain('TariqMap');
      expect(html).toContain('Centre d’opérations');
    });
  });
});
