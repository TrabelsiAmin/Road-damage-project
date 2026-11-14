import React from 'react';
import {
  AlertTriangle,
  Flame,
  Route,
  Clock,
  CheckCircle2,
  Wrench,
  TrendingUp,
  Coins,
  ShieldAlert,
  Inbox,
  Info,
} from 'lucide-react';
import { StatCard } from './ui/StatCard';
import { repairCostText } from '../constants';

export function ExecutiveKpiGrid({
  kpis,
  loading = false,
  lang = 'fr',
  onSelectQueue,
}) {
  if (loading) {
    return (
      <div className="kpi-grid-container">
        {Array.from({ length: 10 }).map((_, idx) => (
          <div key={idx} className="kpi-card skeleton-card">
            <div className="skeleton-line" style={{ width: '60%', height: '14px', marginBottom: '8px' }} />
            <div className="skeleton-line" style={{ width: '40%', height: '28px', marginBottom: '6px' }} />
            <div className="skeleton-line" style={{ width: '80%', height: '12px' }} />
          </div>
        ))}
      </div>
    );
  }

  const unavailable = lang === 'fr' ? 'Non calculé' : 'Not calculated';
  const completionRate = kpis.repairCompletionRate;
  const cards = [
    {
      id: 'active',
      title: lang === 'fr' ? 'Anomalies actives' : 'Active anomalies',
      value: kpis.activeAnomalies,
      sub: lang === 'fr' ? 'Non réparées dans le filtre' : 'Unrepaired in the current filter',
      deltaType: 'neutral',
      icon: AlertTriangle,
      color: '#F59E0B',
      tooltip: lang === 'fr' ? 'Total des dégradations non encore réparées (non confirmées, confirmées, en cours).' : 'Total un-repaired road anomalies.',
      clickable: true,
      queueKey: 'all',
    },
    {
      id: 'critical',
      title: lang === 'fr' ? 'Anomalies critiques' : 'Critical anomalies',
      value: kpis.criticalAnomalies,
      sub: `${kpis.criticalDelta >= 0 ? '+' : ''}${kpis.criticalDelta ?? 0} ${lang === 'fr' ? 'vs période préc.' : 'vs prior period'}`,
      deltaType: kpis.criticalDelta > 0 ? 'negative' : 'positive',
      icon: Flame,
      color: '#EF4444',
      tooltip: lang === 'fr' ? 'Priorité HIGH ou CRITICAL, ou score de priorité d’au moins 65.' : 'Priority HIGH or CRITICAL, or a priority score of at least 65.',
      clickable: true,
      queueKey: 'critical',
    },
    {
      id: 'highRiskSegments',
      title: lang === 'fr' ? 'Tronçons à haut risque' : 'High-risk segments',
      value: kpis.highRiskSegments,
      sub: lang === 'fr' ? 'Corridors score > 60' : 'Corridors score > 60',
      deltaType: 'neutral',
      icon: Route,
      color: '#DC2626',
      tooltip: lang === 'fr' ? "Axes routiers cumulant anomalies répétées, gravité élevée et retard d'intervention." : 'Road corridors with high composite danger.',
      clickable: false,
    },
    {
      id: 'newReports',
      title: lang === 'fr' ? 'Nouveaux signalements' : 'New reports this period',
      value: kpis.newThisWeek,
      sub: lang === 'fr' ? '7 derniers jours' : 'Last 7 days',
      deltaType: 'neutral',
      icon: TrendingUp,
      color: '#3B82F6',
      tooltip: lang === 'fr' ? "Signalements capturés par mobile ou vidéo dans l'intervalle sélectionné." : 'Detections captured in selected window.',
      clickable: false,
    },
    {
      id: 'unconfirmed',
      title: lang === 'fr' ? 'Rapports non validés' : 'Unconfirmed reports',
      value: kpis.unconfirmedReports,
      sub: lang === 'fr' ? 'En attente de revue' : 'Pending verification',
      deltaType: kpis.unconfirmedReports > 10 ? 'warning' : 'neutral',
      icon: Inbox,
      color: '#8B5CF6',
      tooltip: lang === 'fr' ? "Signalements transmis par les usagers ou chauffeurs nécessitant validation de l'autorité." : 'Reports pending authority validation.',
      clickable: true,
      queueKey: 'awaiting_validation',
    },
    {
      id: 'overdue',
      title: lang === 'fr' ? 'Cas en retard (>14j)' : 'Overdue cases (>14d)',
      value: kpis.overdueCases,
      sub: lang === 'fr' ? 'Dépassement SLA voirie' : 'Exceeded road SLA',
      deltaType: kpis.overdueCases > 0 ? 'negative' : 'positive',
      icon: Clock,
      color: '#DC2626',
      tooltip: lang === 'fr' ? 'Anomalies confirmées depuis plus de 14 jours sans réparation entamée.' : 'Cases un-repaired after SLA period.',
      clickable: true,
      queueKey: 'overdue',
    },
    {
      id: 'inProgress',
      title: lang === 'fr' ? 'Réparations en cours' : 'Repairs in progress',
      value: kpis.repairsInProgress,
      sub: lang === 'fr' ? 'Chantiers assignés' : 'Active work sites',
      deltaType: 'neutral',
      icon: Wrench,
      color: '#06B6D4',
      tooltip: lang === 'fr' ? "Chantiers de voirie actuellement en cours d'intervention par les brigades." : 'Currently assigned and undergoing maintenance.',
      clickable: true,
      queueKey: 'in_progress',
    },
    {
      id: 'completed',
      title: lang === 'fr' ? 'Réparations achevées' : 'Repairs completed',
      value: kpis.repairsCompleted,
      sub: completionRate == null
        ? unavailable
        : `${completionRate}% ${lang === 'fr' ? "taux d'achèvement" : 'completion rate'}`,
      deltaType: 'positive',
      icon: CheckCircle2,
      color: '#10B981',
      tooltip: lang === 'fr' ? 'Anomalies réhabilitées et certifiées sur le réseau.' : 'Anomalies fixed and verified.',
      clickable: false,
    },
    {
      id: 'avgResponse',
      title: lang === 'fr' ? 'Délai moyen résolution' : 'Avg. resolution time',
      value: kpis.avgResolutionDays == null ? unavailable : `${kpis.avgResolutionDays}j`,
      sub: lang === 'fr' ? 'De la détection au chantier' : 'Detection to repair',
      deltaType: 'neutral',
      icon: Clock,
      color: '#6366F1',
      tooltip: lang === 'fr' ? 'Durée moyenne constatée entre le signalement mobile initial et la clôture des travaux.' : 'Mean days elapsed between report and repair.',
      clickable: false,
    },
    {
      id: 'estBudget',
      title: lang === 'fr' ? 'Coût de réparation' : 'Repair cost',
      value: repairCostText(lang),
      sub: lang === 'fr' ? 'Aucun montant vérifié' : 'No verified amount',
      deltaType: 'neutral',
      icon: Coins,
      color: '#EC4899',
      tooltip: lang === 'fr' ? 'Coût de réparation indisponible. Aucun barème cité n’est dans ce dépôt.' : 'Repair cost unavailable. This repo has no cited price schedule.',
      clickable: false,
    },
  ];

  return (
    <div className="kpi-grid-container">
      {cards.map((card) => (
        <StatCard
          key={card.id}
          title={card.title}
          value={card.value}
          delta={card.sub}
          deltaType={card.deltaType}
          subtitle=""
          icon={card.icon}
          color={card.color}
          tooltip={card.tooltip}
          clickable={card.clickable}
          onClick={() => card.clickable && onSelectQueue && onSelectQueue(card.queueKey)}
        />
      ))}
    </div>
  );
}
