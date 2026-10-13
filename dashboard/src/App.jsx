import React, { useState, useEffect, useMemo, useRef } from 'react';
import L from 'leaflet';
import {
  DAMAGE_CLASSES,
  SEVERITY_COLORS,
  STATUS_LABELS,
  I18N,
} from './constants';
import {
  fetchObservations,
  updateObservationStatus,
  signIn,
  signOut,
  getCurrentUser,
  checkIsAuthority,
} from './supabase';
import { clusterObservations, calculateRoadHealthScore } from './utils/clustering';
import {
  MapPin,
  AlertTriangle,
  FileSpreadsheet,
  Printer,
  DollarSign,
  Clock,
  ShieldCheck,
  ShieldAlert,
  Globe,
  Layers,
  CheckCircle2,
  X,
  ExternalLink,
  ChevronRight,
  Info,
  LogIn,
  LogOut,
  Sliders,
  HelpCircle,
} from 'lucide-react';

export default function App() {
  const [lang, setLang] = useState('fr');
  const t = I18N[lang];

  const [observations, setObservations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Authentication State
  const [currentUser, setCurrentUser] = useState(null);
  const [isAuthorityUser, setIsAuthorityUser] = useState(false);
  const [showLoginModal, setShowLoginModal] = useState(false);
  const [authEmail, setAuthEmail] = useState('');
  const [authPassword, setAuthPassword] = useState('');
  const [authLoading, setAuthLoading] = useState(false);
  const [authError, setAuthError] = useState(null);

  // Filters
  const [classFilter, setClassFilter] = useState('all');
  const [severityFilter, setSeverityFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');

  // UI state
  const [activeTab, setActiveTab] = useState('priority'); // priority | budget | accountability
  const [selectedCluster, setSelectedCluster] = useState(null);
  const [workOrderModal, setWorkOrderModal] = useState(null);
  const [showRhiTooltip, setShowRhiTooltip] = useState(false);
  const [showAssumptionsPanel, setShowAssumptionsPanel] = useState(true);

  // Editable Budget Assumptions (Tunisian Dinars - Estimates only)
  const [unitCosts, setUnitCosts] = useState({
    D40: 180, // Pothole repair / milling & fill estimate (TND)
    D20: 320, // Alligator fatigue patch estimate (TND)
    D00: 45,  // Longitudinal crack sealing per linear meter estimate (TND)
    D10: 45,  // Transverse crack sealing per linear meter estimate (TND)
  });
  const [budgetTnd, setBudgetTnd] = useState(3500);

  // Leaflet Map Reference
  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersLayerRef = useRef(null);

  // ── 0. Initial Auth & Session Check ────────────────────────────────────────
  useEffect(() => {
    async function checkAuth() {
      try {
        const user = await getCurrentUser();
        setCurrentUser(user);
        if (user) {
          const authOk = await checkIsAuthority();
          setIsAuthorityUser(authOk);
        } else {
          setIsAuthorityUser(false);
        }
      } catch (_) {
        setCurrentUser(null);
        setIsAuthorityUser(false);
      }
    }
    checkAuth();
  }, []);

  // ── 1. Fetch Observations from Supabase ────────────────────────────────────
  useEffect(() => {
    async function loadData() {
      setLoading(true);
      try {
        const data = await fetchObservations();
        setObservations(data);
      } catch (err) {
        setError(err.message || 'Error fetching data from Supabase');
      } finally {
        setLoading(false);
      }
    }
    loadData();
  }, []);

  // ── 2. Geospatial Distance Clustering (20m radius) ─────────────────────────
  const clusters = useMemo(() => {
    return clusterObservations(observations, 20, 30);
  }, [observations]);

  // Check if any demo records are present
  const hasDemoData = useMemo(() => {
    return observations.some((o) => o.is_demo);
  }, [observations]);

  // ── 3. Filtered Clusters for Display ───────────────────────────────────────
  const filteredClusters = useMemo(() => {
    return clusters.filter((c) => {
      if (classFilter !== 'all' && c.dominantClass !== classFilter) return false;
      if (severityFilter !== 'all' && c.priorityLabel !== severityFilter) return false;
      if (statusFilter !== 'all' && c.status !== statusFilter) return false;
      return true;
    });
  }, [clusters, classFilter, severityFilter, statusFilter]);

  // ── 4. Key Metrics ─────────────────────────────────────────────────────────
  const totalDefects = filteredClusters.length;
  const criticalCount = filteredClusters.filter((c) => c.priorityLabel === 'CRITICAL').length;
  const healthScore = calculateRoadHealthScore(filteredClusters);

  // ── 5. Budget Allocation (Greedy Knapsack) ──────────────────────────────────
  const budgetAllocation = useMemo(() => {
    // Sort by priority score descending
    const sorted = [...filteredClusters].sort(
      (a, b) => b.maxPriorityScore - a.maxPriorityScore
    );
    let spent = 0;
    const selected = [];
    const deferred = [];

    for (const c of sorted) {
      const cost = unitCosts[c.dominantClass] || 150;
      if (spent + cost <= budgetTnd) {
        spent += cost;
        selected.push({ ...c, cost });
      } else {
        deferred.push({ ...c, cost });
      }
    }
    return {
      selected,
      deferred,
      totalSpent: spent,
      remainingBudget: Math.max(0, budgetTnd - spent),
    };
  }, [filteredClusters, budgetTnd, unitCosts]);

  // ── 6. Map Initialization & Marker Synchronization ────────────────────────
  useEffect(() => {
    if (!mapRef.current) return;

    if (!mapInstanceRef.current) {
      // Default center: Grand Tunis / Avenue Habib Bourguiba
      const map = L.map(mapRef.current, {
        center: [36.8065, 10.1815],
        zoom: 12,
        zoomControl: false,
      });

      L.control.zoom({ position: 'bottomright' }).addTo(map);

      // CartoDB Dark Matter tiles
      L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; OpenStreetMap &copy; CARTO',
        subdomains: 'abcd',
        maxZoom: 19,
      }).addTo(map);

      const markersGroup = L.layerGroup().addTo(map);
      markersLayerRef.current = markersGroup;
      mapInstanceRef.current = map;
    }

    const markersGroup = markersLayerRef.current;
    if (markersGroup) {
      markersGroup.clearLayers();

      filteredClusters.forEach((cluster) => {
        const clsMeta = DAMAGE_CLASSES[cluster.dominantClass] || DAMAGE_CLASSES.D40;
        const color = clsMeta.color;

        const customIcon = L.divIcon({
          className: 'custom-cluster-icon',
          html: `
            <div style="
              width: 32px;
              height: 32px;
              border-radius: 50%;
              background: ${clsMeta.bgLight};
              border: 2px solid ${color};
              display: flex;
              align-items: center;
              justify-content: center;
              color: #FFF;
              font-size: 11px;
              font-weight: 700;
              box-shadow: 0 0 12px ${color}88;
              cursor: pointer;
            ">
              ${cluster.count > 1 ? cluster.count : '!'}
            </div>
          `,
          iconSize: [32, 32],
          iconAnchor: [16, 16],
        });

        const marker = L.marker([cluster.latitude, cluster.longitude], {
          icon: customIcon,
        });

        marker.on('click', () => {
          setSelectedCluster(cluster);
        });

        marker.addTo(markersGroup);
      });

      // Fit bounds if markers exist
      if (filteredClusters.length > 0 && mapInstanceRef.current) {
        const bounds = L.latLngBounds(
          filteredClusters.map((c) => [c.latitude, c.longitude])
        );
        mapInstanceRef.current.fitBounds(bounds, { padding: [50, 50], maxZoom: 15 });
      }
    }
  }, [filteredClusters]);

  // ── 7. Handle Status Change (Authority only) ───────────────────────────────
  async function handleStatusChange(obsId, newStatus) {
    if (!isAuthorityUser) {
      setShowLoginModal(true);
      return;
    }
    try {
      await updateObservationStatus(obsId, newStatus);
      // Refresh local observations
      setObservations((prev) =>
        prev.map((o) => (o.id === obsId ? { ...o, status: newStatus } : o))
      );
      if (selectedCluster) {
        setSelectedCluster((prev) => ({
          ...prev,
          status: newStatus,
          observations: prev.observations.map((o) =>
            o.id === obsId ? { ...o, status: newStatus } : o
          ),
        }));
      }
    } catch (err) {
      alert(`Erreur de modification (RLS rejeté): ${err.message}`);
    }
  }

  // ── 8. Login Handler ───────────────────────────────────────────────────────
  async function handleLogin(e) {
    e.preventDefault();
    setAuthLoading(true);
    setAuthError(null);
    try {
      const data = await signIn(authEmail, authPassword);
      setCurrentUser(data.user);
      const isAuth = await checkIsAuthority();
      setIsAuthorityUser(isAuth);
      setShowLoginModal(false);
      setAuthPassword('');
      if (!isAuth) {
        alert(
          'Compte connecté, mais non enregistré dans authority_users. Accès en lecture seule conservé.'
        );
      }
    } catch (err) {
      setAuthError(err.message || 'Échec de connexion');
    } finally {
      setAuthLoading(false);
    }
  }

  async function handleLogout() {
    try {
      await signOut();
      setCurrentUser(null);
      setIsAuthorityUser(false);
    } catch (err) {
      console.error(err);
    }
  }

  // ── 9. Export CSV ──────────────────────────────────────────────────────────
  function handleExportCsv() {
    const headers = [
      'ClusterID',
      'DominantClass',
      'PriorityScore',
      'PriorityLabel',
      'Status',
      'Latitude',
      'Longitude',
      'SightingsCount',
      'FirstObserved',
    ];
    const rows = filteredClusters.map((c) => [
      c.id,
      c.dominantClass,
      c.maxPriorityScore,
      c.priorityLabel,
      c.status,
      c.latitude.toFixed(6),
      c.longitude.toFixed(6),
      c.count,
      c.firstObserved,
    ]);
    const csvContent =
      'data:text/csv;charset=utf-8,' +
      [headers.join(','), ...rows.map((e) => e.join(','))].join('\n');
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement('a');
    link.setAttribute('href', encodedUri);
    link.setAttribute('download', `tariqmap_export_${new Date().toISOString().slice(0, 10)}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  }

  return (
    <div className="dashboard-container">
      {/* ── Demo Data Active Banner ─────────────────────────────────────────── */}
      {hasDemoData && (
        <div className="demo-banner">
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <AlertTriangle size={18} />
            <span>{t.demoBanner}</span>
          </div>
          <span className="mono" style={{ fontSize: '0.75rem' }}>
            Flag: <code>is_demo = true</code>
          </span>
        </div>
      )}

      {/* ── Top Navigation Bar ───────────────────────────────────────────────── */}
      <header className="topbar">
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <div
            style={{
              width: '34px',
              height: '34px',
              borderRadius: '8px',
              background: 'linear-gradient(135deg, var(--teal-accent), #3B82F6)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontWeight: 900,
              color: '#000',
            }}
          >
            TM
          </div>
          <div>
            <h1 className="topbar-title">{t.title}</h1>
            <p className="topbar-subtitle">{t.subtitle}</p>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          {/* Authority / Public Status Badge */}
          {currentUser ? (
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                padding: '6px 12px',
                borderRadius: 'var(--radius-sm)',
                background: isAuthorityUser
                  ? 'rgba(16, 185, 129, 0.15)'
                  : 'rgba(234, 179, 8, 0.15)',
                border: `1px solid ${
                  isAuthorityUser ? 'var(--emerald-accent)' : 'var(--amber-accent)'
                }`,
                fontSize: '0.8rem',
              }}
            >
              {isAuthorityUser ? (
                <ShieldCheck size={16} color="var(--emerald-accent)" />
              ) : (
                <ShieldAlert size={16} color="var(--amber-accent)" />
              )}
              <span style={{ fontWeight: 600 }}>
                {isAuthorityUser ? 'AUTORITÉ COMMUNE' : 'UTILISATEUR AUTH'}
              </span>
              <button
                onClick={handleLogout}
                style={{
                  background: 'none',
                  border: 'none',
                  color: 'var(--text-muted)',
                  cursor: 'pointer',
                  marginLeft: '6px',
                  display: 'flex',
                  alignItems: 'center',
                }}
                title="Déconnexion"
              >
                <LogOut size={14} />
              </button>
            </div>
          ) : (
            <button className="btn" onClick={() => setShowLoginModal(true)}>
              <LogIn size={15} />
              <span>Connexion Autorité</span>
            </button>
          )}

          {/* Language Toggle */}
          <button
            className="btn"
            onClick={() => setLang(lang === 'fr' ? 'en' : 'fr')}
          >
            <Globe size={15} />
            <span>{t.switchLang}</span>
          </button>
        </div>
      </header>

      {/* ── Main Layout (Map + Sidebar) ─────────────────────────────────────── */}
      <div className="main-layout">
        {/* Left Map View */}
        <div className="map-wrapper">
          <div ref={mapRef} style={{ width: '100%', height: '100%' }} />

          {/* Quick Map Overlay Filter Controls */}
          <div
            style={{
              position: 'absolute',
              top: '16px',
              left: '16px',
              zIndex: 1000,
              display: 'flex',
              gap: '8px',
              background: 'rgba(18, 26, 43, 0.85)',
              backdropFilter: 'blur(8px)',
              padding: '8px',
              borderRadius: 'var(--radius-md)',
              border: '1px solid var(--border-subtle)',
            }}
          >
            <select
              className="select-input"
              value={classFilter}
              onChange={(e) => setClassFilter(e.target.value)}
            >
              <option value="all">{t.filterClass}: {t.all}</option>
              {Object.keys(DAMAGE_CLASSES).map((k) => (
                <option key={k} value={k}>
                  {k} ({lang === 'fr' ? DAMAGE_CLASSES[k].fr : DAMAGE_CLASSES[k].en})
                </option>
              ))}
            </select>

            <select
              className="select-input"
              value={severityFilter}
              onChange={(e) => setSeverityFilter(e.target.value)}
            >
              <option value="all">{t.filterSeverity}: {t.all}</option>
              <option value="CRITICAL">CRITICAL</option>
              <option value="HIGH">HIGH</option>
              <option value="MEDIUM">MEDIUM</option>
              <option value="LOW">LOW</option>
            </select>

            <select
              className="select-input"
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
            >
              <option value="all">{t.filterStatus}: {t.all}</option>
              {Object.keys(STATUS_LABELS).map((st) => (
                <option key={st} value={st}>
                  {lang === 'fr' ? STATUS_LABELS[st].fr : STATUS_LABELS[st].en}
                </option>
              ))}
            </select>
          </div>

          {/* Map Legend */}
          <div className="map-legend">
            <span style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--text-muted)' }}>
              LÉGENDE DÉGÂTS (20m DENSITY)
            </span>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '6px' }}>
              {Object.values(DAMAGE_CLASSES).map((cls) => (
                <div key={cls.code} style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.8rem' }}>
                  <span
                    style={{
                      width: '10px',
                      height: '10px',
                      borderRadius: '50%',
                      background: cls.color,
                      display: 'inline-block',
                    }}
                  />
                  <span>
                    <strong>{cls.code}</strong> — {lang === 'fr' ? cls.fr : cls.en}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Right Decision Support Sidebar */}
        <div className="sidebar">
          {/* Key Metrics Row */}
          <div className="metrics-row">
            <div className="metric-card">
              <span className="metric-label">{t.totalDefects}</span>
              <span className="metric-value mono">{totalDefects}</span>
            </div>
            <div className="metric-card">
              <span className="metric-label">{t.criticalCount}</span>
              <span className="metric-value mono" style={{ color: 'var(--red-accent)' }}>
                {criticalCount}
              </span>
            </div>
            <div className="metric-card" style={{ position: 'relative' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <span className="metric-label">{t.healthScore}</span>
                <HelpCircle
                  size={14}
                  style={{ color: 'var(--text-muted)', cursor: 'pointer' }}
                  onClick={() => setShowRhiTooltip(!showRhiTooltip)}
                />
              </div>
              <span
                className="metric-value mono"
                style={{
                  color:
                    healthScore > 75
                      ? 'var(--emerald-accent)'
                      : healthScore > 50
                      ? 'var(--amber-accent)'
                      : 'var(--red-accent)',
                }}
              >
                {healthScore}
                <span style={{ fontSize: '0.9rem', color: 'var(--text-muted)' }}>/100</span>
              </span>

              {/* RHI Formula Tooltip */}
              {showRhiTooltip && (
                <div
                  style={{
                    position: 'absolute',
                    top: '100%',
                    right: 0,
                    zIndex: 1100,
                    width: '280px',
                    padding: '12px',
                    background: 'var(--bg-card)',
                    border: '1px solid var(--border-medium)',
                    borderRadius: 'var(--radius-sm)',
                    boxShadow: 'var(--shadow-card)',
                    fontSize: '0.78rem',
                    color: 'var(--text-main)',
                    marginTop: '6px',
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                    <strong>Formule de l'Indice RHI</strong>
                    <X size={12} style={{ cursor: 'pointer' }} onClick={() => setShowRhiTooltip(false)} />
                  </div>
                  <p style={{ fontFamily: 'monospace', color: 'var(--teal-accent)', marginBottom: '6px' }}>
                    RHI = max(0, 100 - min(100, Σ (PriorityScore_i × ClassWeight_i) / N))
                  </p>
                  <p style={{ color: 'var(--text-muted)', lineHeight: 1.4 }}>
                    Pondération géodésique sur PostGIS/Haversine (20m). 100 = chaussée intacte. Décroissance proportionnelle à la densité et criticité des nids-de-poule et faïençages.
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Tabs Navigation */}
          <div className="tabs-header">
            <button
              className={`tab-btn ${activeTab === 'priority' ? 'active' : ''}`}
              onClick={() => setActiveTab('priority')}
            >
              {t.priorityRankedList}
            </button>
            <button
              className={`tab-btn ${activeTab === 'budget' ? 'active' : ''}`}
              onClick={() => setActiveTab('budget')}
            >
              {t.budgetOptimizer}
            </button>
            <button
              className={`tab-btn ${activeTab === 'accountability' ? 'active' : ''}`}
              onClick={() => setActiveTab('accountability')}
            >
              {t.accountability}
            </button>
          </div>

          {/* Tab Content Area */}
          <div className="tab-body">
            {/* ── Tab 1: Priority Queue ─────────────────────────────────────── */}
            {activeTab === 'priority' && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                    {filteredClusters.length} clusters identifiés
                  </span>
                  <button className="btn" onClick={handleExportCsv}>
                    <FileSpreadsheet size={14} />
                    <span>{t.exportCsv}</span>
                  </button>
                </div>

                <div className="queue-list">
                  {filteredClusters.map((cluster, idx) => {
                    const clsMeta = DAMAGE_CLASSES[cluster.dominantClass] || DAMAGE_CLASSES.D40;
                    return (
                      <div
                        key={cluster.id}
                        className={`queue-item ${selectedCluster?.id === cluster.id ? 'selected' : ''}`}
                        onClick={() => setSelectedCluster(cluster)}
                      >
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                            <span className="mono" style={{ color: 'var(--text-dim)', fontSize: '0.8rem' }}>
                              #{idx + 1}
                            </span>
                            <span
                              style={{
                                color: clsMeta.color,
                                fontWeight: 700,
                                fontSize: '0.9rem',
                              }}
                            >
                              {cluster.dominantClass}
                            </span>
                            <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                              ({lang === 'fr' ? clsMeta.fr : clsMeta.en})
                            </span>
                          </div>

                          <span className={`badge ${STATUS_LABELS[cluster.status]?.badge || 'badge-gray'}`}>
                            {lang === 'fr'
                              ? STATUS_LABELS[cluster.status]?.fr
                              : STATUS_LABELS[cluster.status]?.en}
                          </span>
                        </div>

                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '6px' }}>
                          <span className="mono" style={{ fontSize: '0.8rem' }}>
                            Score: <strong>{cluster.maxPriorityScore}</strong> / 100
                          </span>
                          <span style={{ fontSize: '0.75rem', color: 'var(--text-dim)' }}>
                            {cluster.count} {cluster.count > 1 ? 'passages' : 'passage'} (20m)
                          </span>
                        </div>

                        {selectedCluster?.id === cluster.id && (
                          <div
                            style={{
                              marginTop: '10px',
                              paddingTop: '10px',
                              borderTop: '1px solid var(--border-subtle)',
                              display: 'flex',
                              justifyContent: 'space-between',
                              alignItems: 'center',
                            }}
                          >
                            <select
                              className="select-input"
                              value={cluster.status}
                              onChange={(e) => handleStatusChange(cluster.observations[0]?.id, e.target.value)}
                              disabled={!isAuthorityUser}
                              style={{ fontSize: '0.75rem', padding: '4px 8px' }}
                            >
                              {Object.keys(STATUS_LABELS).map((st) => (
                                <option key={st} value={st}>
                                  {lang === 'fr' ? STATUS_LABELS[st].fr : STATUS_LABELS[st].en}
                                </option>
                              ))}
                            </select>

                            <button
                              className="btn"
                              style={{ fontSize: '0.75rem', padding: '4px 10px' }}
                              onClick={(e) => {
                                e.stopPropagation();
                                setWorkOrderModal(cluster);
                              }}
                            >
                              <Printer size={13} />
                              <span>Ordre Travaux</span>
                            </button>
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            )}

            {/* ── Tab 2: Budget Optimizer ───────────────────────────────────── */}
            {activeTab === 'budget' && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                {/* Assumptions Panel Toggle */}
                <div
                  style={{
                    padding: '12px',
                    background: 'rgba(234, 179, 8, 0.08)',
                    borderRadius: 'var(--radius-sm)',
                    border: '1px solid rgba(234, 179, 8, 0.25)',
                  }}
                >
                  <div
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      cursor: 'pointer',
                    }}
                    onClick={() => setShowAssumptionsPanel(!showAssumptionsPanel)}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <Sliders size={16} color="var(--amber-accent)" />
                      <span style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--amber-accent)' }}>
                        Panneau des Hypothèses de Coûts (Estimations)
                      </span>
                    </div>
                    <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                      {showAssumptionsPanel ? 'Masquer' : 'Ajuster'}
                    </span>
                  </div>

                  <p style={{ fontSize: '0.74rem', color: 'var(--text-muted)', marginTop: '4px' }}>
                    *Estimations paramétrables - non contractuelles / non officielles.
                  </p>

                  {showAssumptionsPanel && (
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px', marginTop: '10px' }}>
                      <div>
                        <label style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>D40 Pothole (TND)</label>
                        <input
                          type="number"
                          className="select-input"
                          style={{ width: '100%', marginTop: '2px' }}
                          value={unitCosts.D40}
                          onChange={(e) => setUnitCosts({ ...unitCosts, D40: Number(e.target.value) || 0 })}
                        />
                      </div>
                      <div>
                        <label style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>D20 Alligator (TND)</label>
                        <input
                          type="number"
                          className="select-input"
                          style={{ width: '100%', marginTop: '2px' }}
                          value={unitCosts.D20}
                          onChange={(e) => setUnitCosts({ ...unitCosts, D20: Number(e.target.value) || 0 })}
                        />
                      </div>
                      <div>
                        <label style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>D00 Long. Crack (TND/m)</label>
                        <input
                          type="number"
                          className="select-input"
                          style={{ width: '100%', marginTop: '2px' }}
                          value={unitCosts.D00}
                          onChange={(e) => setUnitCosts({ ...unitCosts, D00: Number(e.target.value) || 0 })}
                        />
                      </div>
                      <div>
                        <label style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>D10 Trans. Crack (TND/m)</label>
                        <input
                          type="number"
                          className="select-input"
                          style={{ width: '100%', marginTop: '2px' }}
                          value={unitCosts.D10}
                          onChange={(e) => setUnitCosts({ ...unitCosts, D10: Number(e.target.value) || 0 })}
                        />
                      </div>
                    </div>
                  )}
                </div>

                {/* Municipal Budget Input */}
                <div className="metric-card">
                  <span className="metric-label">{t.budgetInput}</span>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginTop: '8px' }}>
                    <input
                      type="number"
                      className="select-input mono"
                      style={{ flex: 1, fontSize: '1rem', fontWeight: 700 }}
                      value={budgetTnd}
                      onChange={(e) => setBudgetTnd(Number(e.target.value) || 0)}
                    />
                    <span className="mono" style={{ color: 'var(--text-muted)' }}>TND</span>
                  </div>
                </div>

                {/* Knapsack Summary */}
                <div style={{ padding: '12px', background: 'var(--bg-card)', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-subtle)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.85rem', marginBottom: '6px' }}>
                    <span>Réparations finançables:</span>
                    <span className="mono" style={{ fontWeight: 700, color: 'var(--emerald-accent)' }}>
                      {budgetAllocation.selected.length} / {filteredClusters.length}
                    </span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.85rem', marginBottom: '6px' }}>
                    <span>{t.cumulativeCost}:</span>
                    <span className="mono" style={{ fontWeight: 700 }}>
                      {budgetAllocation.totalSpent.toLocaleString()} TND (Est.)
                    </span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                    <span>Reliquat budgétaire:</span>
                    <span className="mono">{budgetAllocation.remainingBudget.toLocaleString()} TND</span>
                  </div>
                </div>

                <div style={{ maxHeight: '240px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                  {budgetAllocation.selected.map((item, idx) => (
                    <div
                      key={item.id}
                      style={{
                        padding: '6px 10px',
                        background: 'rgba(255, 255, 255, 0.02)',
                        border: '1px solid var(--border-subtle)',
                        borderRadius: 'var(--radius-sm)',
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        fontSize: '0.8rem',
                      }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <span className="mono" style={{ color: 'var(--text-dim)' }}>#{idx + 1}</span>
                        <span style={{ fontWeight: 600, color: DAMAGE_CLASSES[item.dominantClass]?.color }}>
                          {item.dominantClass}
                        </span>
                        <span>Score: {item.maxPriorityScore}</span>
                      </div>
                      <span className="mono" style={{ color: 'var(--text-muted)' }}>
                        {item.cost} TND
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* ── Tab 3: Accountability & Verification ──────────────────────── */}
            {activeTab === 'accountability' && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <div className="metric-card">
                  <span className="metric-label">Boucle de Vérification (Phase 3)</span>
                  <div
                    style={{
                      marginTop: '12px',
                      padding: '12px',
                      background: 'rgba(59, 130, 246, 0.08)',
                      borderRadius: 'var(--radius-sm)',
                      border: '1px solid rgba(59, 130, 246, 0.2)',
                    }}
                  >
                    <p style={{ fontSize: '0.82rem', color: 'var(--text-main)', lineHeight: 1.5 }}>
                      Lorsqu'un véhicule citoyen ou municipal traverse le centroïde d'un nid-de-poule réparé sans détecter de choc ou dégradation visuelle, le système enregistre un événement de validation.
                    </p>
                    <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '8px' }}>
                      {t.repairCycleNote}
                    </p>
                  </div>
                </div>

                <div className="metric-card">
                  <span className="metric-label">Délai Moyen de Réparation (MTTR)</span>
                  <span className="metric-value mono" style={{ fontSize: '1.2rem', color: 'var(--text-muted)' }}>
                    -- jours (En attente des journaux Phase 3)
                  </span>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* ── Authority Login Modal ────────────────────────────────────────────── */}
      {showLoginModal && (
        <div className="modal-overlay" onClick={() => setShowLoginModal(false)}>
          <div className="modal-card" style={{ maxWidth: '400px' }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: '24px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                <h3 style={{ fontSize: '1.1rem', fontWeight: 800 }}>Connexion Autorité Municipale</h3>
                <X size={18} style={{ cursor: 'pointer' }} onClick={() => setShowLoginModal(false)} />
              </div>

              <p style={{ fontSize: '0.82rem', color: 'var(--text-muted)', marginBottom: '16px', lineHeight: 1.4 }}>
                L'authentification par rôle <code>authority_users</code> permet de valider les signalements, attribuer les marchés de voirie et clore les travaux.
              </p>

              {authError && (
                <div style={{ padding: '8px', background: 'rgba(239, 68, 68, 0.15)', border: '1px solid var(--red-accent)', borderRadius: 'var(--radius-sm)', color: '#FFF', fontSize: '0.78rem', marginBottom: '12px' }}>
                  {authError}
                </div>
              )}

              <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <div>
                  <label style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>Email Agent</label>
                  <input
                    type="email"
                    required
                    className="select-input"
                    style={{ width: '100%', marginTop: '4px' }}
                    placeholder="authority@tariqmap.tn"
                    value={authEmail}
                    onChange={(e) => setAuthEmail(e.target.value)}
                  />
                </div>

                <div>
                  <label style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>Mot de passe</label>
                  <input
                    type="password"
                    required
                    className="select-input"
                    style={{ width: '100%', marginTop: '4px' }}
                    placeholder="••••••••••••"
                    value={authPassword}
                    onChange={(e) => setAuthPassword(e.target.value)}
                  />
                </div>

                <button
                  type="submit"
                  className="btn"
                  disabled={authLoading}
                  style={{ width: '100%', justifyContent: 'center', marginTop: '8px' }}
                >
                  {authLoading ? 'Vérification...' : 'Se connecter'}
                </button>
              </form>
            </div>
          </div>
        </div>
      )}

      {/* ── Printable Work Order Modal ──────────────────────────────────────── */}
      {workOrderModal && (
        <div className="modal-overlay" onClick={() => setWorkOrderModal(null)}>
          <div className="modal-card" onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: '24px' }}>
              <div
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'flex-start',
                  borderBottom: '2px solid #000',
                  paddingBottom: '16px',
                  marginBottom: '20px',
                }}
              >
                <div>
                  <h2 style={{ fontSize: '1.2rem', fontWeight: 800 }}>{t.workOrderTitle}</h2>
                  <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                    RÉPUBLIQUE TUNISIENNE • DIRECTION RÉGIONALE DE L'ÉQUIPEMENT
                  </p>
                </div>
                <button className="btn" onClick={() => window.print()}>
                  <Printer size={15} />
                  <span>Imprimer / PDF</span>
                </button>
              </div>

              {workOrderModal.photoUrl && (
                <div style={{ marginBottom: '16px', textAlign: 'center' }}>
                  <img
                    src={workOrderModal.photoUrl}
                    alt="Road defect"
                    style={{ maxHeight: '220px', width: '100%', objectFit: 'cover', borderRadius: 'var(--radius-sm)' }}
                  />
                </div>
              )}

              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem', marginBottom: '24px' }}>
                <tbody>
                  <tr style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>{t.defectType}:</td>
                    <td style={{ padding: '8px 0', fontWeight: 700 }}>
                      {workOrderModal.dominantClass} - {lang === 'fr' ? DAMAGE_CLASSES[workOrderModal.dominantClass]?.fr : DAMAGE_CLASSES[workOrderModal.dominantClass]?.en}
                    </td>
                  </tr>
                  <tr style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>Niveau d'Urgence:</td>
                    <td style={{ padding: '8px 0', fontWeight: 700 }}>
                      {workOrderModal.maxPriorityScore} / 100 ({workOrderModal.priorityLabel})
                    </td>
                  </tr>
                  <tr style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>{t.gpsCoords}:</td>
                    <td style={{ padding: '8px 0' }} className="mono">
                      {workOrderModal.latitude.toFixed(6)}, {workOrderModal.longitude.toFixed(6)}
                    </td>
                  </tr>
                  <tr style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>{t.sightings}:</td>
                    <td style={{ padding: '8px 0' }}>{workOrderModal.count} signalements concordants (Rayon 20m)</td>
                  </tr>
                  <tr style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>Coût estimatif d'intervention:</td>
                    <td style={{ padding: '8px 0' }} className="mono">
                      {unitCosts[workOrderModal.dominantClass] || 150} TND (Estimation non officielle)
                    </td>
                  </tr>
                  {/* Engineer prescription blank line */}
                  <tr style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>Prescription technique d'enrobé:</td>
                    <td style={{ padding: '8px 0', fontStyle: 'italic', color: 'var(--text-dim)' }}>
                      ___________________________________ (À définir par l'ingénieur subdivisionnaire)
                    </td>
                  </tr>
                  <tr>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>Visa & Approbation Technique:</td>
                    <td style={{ padding: '8px 0', fontStyle: 'italic', color: 'var(--text-dim)' }}>
                      Date: _______________ Signature: ___________________
                    </td>
                  </tr>
                </tbody>
              </table>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px' }}>
                <button className="btn" onClick={() => setWorkOrderModal(null)}>
                  {t.close}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
