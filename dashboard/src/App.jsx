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
  getMediaUrl,
} from './supabase';
import { clusterObservations, calculateRoadHealthScore } from './utils/clustering';
import { calculatePriorityScore, PRIORITY_CONFIG } from './utils/priorityScoring';
import validationMetricsData from './data/validation_metrics.json';
import {
  MapPin,
  AlertTriangle,
  FileSpreadsheet,
  Printer,
  Shield,
  ShieldCheck,
  ShieldAlert,
  Globe,
  CheckCircle2,
  X,
  LogIn,
  LogOut,
  HelpCircle,
  BarChart3,
  ChevronRight,
  Eye,
  Camera,
  Layers,
  Wrench,
  Clock,
  ArrowRight,
} from 'lucide-react';

// Priority Colors for Leaflet pins (v2: HIGH, MEDIUM, LOW)
const PRIORITY_PIN_COLORS = {
  HIGH: '#EF4444',     // Red
  CRITICAL: '#EF4444', // Red fallback
  MEDIUM: '#F59E0B',   // Amber
  LOW: '#3B82F6',      // Blue
};

/**
 * Report Image Card: uses createSignedUrl with short expiry (300s) for observation-images.
 * Never calls getPublicUrl. Shows neutral placeholder when no image is available.
 */
function ReportImageThumbnail({ storagePath, bucket = 'observation-images', isAuthority }) {
  const [signedUrl, setSignedUrl] = useState(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let active = true;
    if (isAuthority && storagePath) {
      setLoading(true);
      getMediaUrl(storagePath, bucket)
        .then((url) => {
          if (active) {
            setSignedUrl(url);
            setLoading(false);
          }
        })
        .catch(() => {
          if (active) {
            setSignedUrl(null);
            setLoading(false);
          }
        });
    } else {
      setSignedUrl(null);
      setLoading(false);
    }
    return () => { active = false; };
  }, [storagePath, bucket, isAuthority]);

  if (isAuthority && storagePath) {
    if (loading) {
      return (
        <div className="report-img-placeholder">
          <div className="spinner-sm" style={{ width: '14px', height: '14px', border: '2px solid rgba(255,255,255,0.2)', borderTopColor: 'var(--color-primary)', borderRadius: '50%', animation: 'spin 0.8s linear infinite' }} />
          <span style={{ fontSize: '0.7rem' }}>Chargement URL signée...</span>
        </div>
      );
    }
    if (signedUrl) {
      return (
        <div className="report-img-container">
          <img
            src={signedUrl}
            alt="Cliché chaussée"
            className="report-img"
            onError={() => setSignedUrl(null)}
          />
          <span className="report-img-badge">Signé (300s)</span>
        </div>
      );
    }
  }

  return (
    <div className="report-img-placeholder neutral-privacy">
      <Camera size={16} style={{ opacity: 0.6 }} />
      <span style={{ fontSize: '0.7rem', color: 'var(--text-dim)' }}>
        {storagePath ? 'Photo réservée autorité' : 'Aucun cliché'}
      </span>
    </div>
  );
}

export default function App() {
  const [observations, setObservations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lang, setLang] = useState('fr');

  // Auth State
  const [currentUser, setCurrentUser] = useState(null);
  const [isAuthorityUser, setIsAuthorityUser] = useState(false);
  const [showLoginModal, setShowLoginModal] = useState(false);
  const [authEmail, setAuthEmail] = useState('');
  const [authPassword, setAuthPassword] = useState('');
  const [authLoading, setAuthLoading] = useState(false);
  const [authError, setAuthError] = useState(null);

  // Filters: class, priority, status
  const [classFilter, setClassFilter] = useState('all');
  const [priorityFilter, setPriorityFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');

  // Selected Cluster & Side Panel
  const [selectedCluster, setSelectedCluster] = useState(null);

  // Status Change Confirmation Modal
  const [statusConfirmModal, setStatusConfirmModal] = useState(null); // { obsId, newStatus, currentStatus }
  const [statusUpdating, setStatusUpdating] = useState(false);

  // Honest Metrics Panel Modal
  const [showMetricsPanel, setShowMetricsPanel] = useState(false);

  // RHI Tooltip
  const [showRhiTooltip, setShowRhiTooltip] = useState(false);

  // Active Sidebar Tab
  const [activeTab, setActiveTab] = useState('clusters'); // 'clusters' | 'metrics'

  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersLayerRef = useRef(null);

  const t = I18N[lang] || I18N.fr;

  // ── 0. Check Auth Session on Mount ─────────────────────────────────────────
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

  // ── 2. Metric Distance Clustering (20m radius, accuracy <= 25m) ────────────
  const clusters = useMemo(() => {
    return clusterObservations(observations, 20, 25);
  }, [observations]);

  const hasDemoData = useMemo(() => {
    return observations.some((o) => o.is_demo);
  }, [observations]);

  // ── 3. Filtered Clusters for Display ───────────────────────────────────────
  const filteredClusters = useMemo(() => {
    return clusters.filter((c) => {
      if (classFilter !== 'all' && c.dominantClass !== classFilter) return false;
      if (priorityFilter !== 'all' && c.priorityLabel !== priorityFilter) return false;
      if (statusFilter !== 'all' && c.status !== statusFilter) return false;
      return true;
    });
  }, [clusters, classFilter, priorityFilter, statusFilter]);

  // ── 4. KPI Strip Metrics ───────────────────────────────────────────────────
  const kpis = useMemo(() => {
    const classCounts = { D40: 0, D20: 0, D10: 0, D00: 0 };
    const priorityCounts = { HIGH: 0, MEDIUM: 0, LOW: 0 };
    const statusCounts = { unconfirmed: 0, confirmed: 0, repaired: 0 };

    filteredClusters.forEach((c) => {
      if (classCounts[c.dominantClass] !== undefined) {
        classCounts[c.dominantClass] += c.count;
      }
      if (priorityCounts[c.priorityLabel] !== undefined) {
        priorityCounts[c.priorityLabel] += 1;
      }
      if (statusCounts[c.status] !== undefined) {
        statusCounts[c.status] += 1;
      }
    });

    const totalReports = filteredClusters.reduce((sum, c) => sum + c.count, 0);
    const healthScore = calculateRoadHealthScore(filteredClusters);

    return {
      totalClusters: filteredClusters.length,
      totalReports,
      classCounts,
      priorityCounts,
      statusCounts,
      healthScore,
    };
  }, [filteredClusters]);

  // ── 5. Leaflet Map Markers (colour = priority, size = report count) ────────
  useEffect(() => {
    if (!mapRef.current) return;

    if (!mapInstanceRef.current) {
      const map = L.map(mapRef.current, {
        center: [36.8065, 10.1815], // Grand Tunis
        zoom: 12,
        zoomControl: false,
      });

      L.control.zoom({ position: 'bottomright' }).addTo(map);

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
        // Colour = Priority
        const pinColor = PRIORITY_PIN_COLORS[cluster.priorityLabel] || '#3B82F6';

        // Size = Report Count (scaled smoothly from 28px to 54px)
        const pinSize = Math.min(54, Math.max(28, 24 + cluster.count * 4));

        const customIcon = L.divIcon({
          className: 'custom-cluster-marker',
          html: `
            <div style="
              width: ${pinSize}px;
              height: ${pinSize}px;
              border-radius: 50%;
              background: ${pinColor}25;
              border: 2px solid ${pinColor};
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              color: #FFF;
              font-size: ${pinSize > 36 ? '12px' : '10px'};
              font-weight: 800;
              box-shadow: 0 0 14px ${pinColor}88;
              cursor: pointer;
              transition: transform 0.15s ease;
            ">
              <span>${cluster.count}</span>
            </div>
          `,
          iconSize: [pinSize, pinSize],
          iconAnchor: [pinSize / 2, pinSize / 2],
        });

        const marker = L.marker([cluster.latitude, cluster.longitude], {
          icon: customIcon,
        });

        marker.on('click', () => {
          setSelectedCluster(cluster);
        });

        marker.addTo(markersGroup);
      });

      if (filteredClusters.length > 0 && mapInstanceRef.current) {
        const bounds = L.latLngBounds(
          filteredClusters.map((c) => [c.latitude, c.longitude])
        );
        mapInstanceRef.current.fitBounds(bounds, { padding: [40, 40], maxZoom: 15 });
      }
    }
  }, [filteredClusters]);

  // Keep selectedCluster in sync with updated observations
  useEffect(() => {
    if (!selectedCluster) return;
    const fresh = clusters.find((c) => c.id === selectedCluster.id);
    if (fresh) setSelectedCluster(fresh);
  }, [clusters]);

  // ── 6. Status Workflow Handler (unconfirmed → confirmed → repaired) ────────
  function promptStatusUpdate(obsId, currentStatus, newStatus) {
    if (!isAuthorityUser) {
      setShowLoginModal(true);
      return;
    }
    setStatusConfirmModal({ obsId, currentStatus, newStatus });
  }

  async function executeStatusUpdate() {
    if (!statusConfirmModal) return;
    const { obsId, newStatus } = statusConfirmModal;
    setStatusUpdating(true);
    try {
      await updateObservationStatus(obsId, newStatus);
      // Refresh local observations
      setObservations((prev) =>
        prev.map((o) => (o.id === obsId ? { ...o, status: newStatus } : o))
      );
      setStatusConfirmModal(null);
    } catch (err) {
      alert(`Erreur de mise à jour: ${err.message}`);
    } finally {
      setStatusUpdating(false);
    }
  }

  // ── 7. CSV Export (Strictly omitting device_id) ────────────────────────────
  function handleExportCsv() {
    const headers = [
      'ClusterID',
      'DominantClass',
      'ReportCount',
      'MaxPriorityScore',
      'PriorityLabel',
      'Status',
      'CentroidLatitude',
      'CentroidLongitude',
      'FirstSeen',
      'LastSeen',
    ];

    const rows = filteredClusters.map((c) => [
      `"${c.id}"`,
      `"${c.dominantClass}"`,
      c.count,
      c.maxPriorityScore,
      `"${c.priorityLabel}"`,
      `"${c.status}"`,
      c.latitude.toFixed(7),
      c.longitude.toFixed(7),
      `"${c.oldestDate}"`,
      `"${c.newestDate}"`,
    ]);

    const csvContent =
      'data:text/csv;charset=utf-8,' +
      [headers.join(','), ...rows.map((e) => e.join(','))].join('\n');
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement('a');
    link.setAttribute('href', encodedUri);
    link.setAttribute(
      'download',
      `tariqmap_clusters_${new Date().toISOString().slice(0, 10)}.csv`
    );
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
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
          'Compte authentifié, mais absent de la table authority_users. Accès en lecture seule conservé.'
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

  return (
    <div className="dashboard-container">
      {/* ── Demo Data Active Banner ─────────────────────────────────────────── */}
      {hasDemoData && (
        <div className="demo-banner">
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <AlertTriangle size={16} />
            <span>{t.demoBanner}</span>
          </div>
          <span className="mono" style={{ fontSize: '0.72rem' }}>
            <code>is_demo = true</code>
          </span>
        </div>
      )}

      {/* ── Top Navigation Bar ───────────────────────────────────────────────── */}
      <header className="topbar">
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <div className="brand-badge">TM</div>
          <div>
            <h1 className="topbar-title">{t.title}</h1>
            <p className="topbar-subtitle">
              {lang === 'fr'
                ? 'Tableau de Bord Autorité • Priorisation & Diagnostic Voirie'
                : 'Authority Dashboard • Road Anomaly Triage & Verification'}
            </p>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap' }}>
          {/* Honest Metrics Button */}
          <button
            className="btn btn-secondary"
            onClick={() => setShowMetricsPanel(true)}
            title="Consulter les métriques de validation du modèle"
          >
            <BarChart3 size={15} color="var(--color-primary)" />
            <span>Métriques IA & Limites</span>
          </button>

          {/* Export CSV Button */}
          <button className="btn btn-secondary" onClick={handleExportCsv} title="Exporter les clusters en CSV">
            <FileSpreadsheet size={15} />
            <span className="hide-on-mobile">Exporter CSV</span>
          </button>

          {/* Authority / Public Status Badge */}
          {currentUser ? (
            <div
              className="auth-badge"
              style={{
                background: isAuthorityUser ? 'rgba(16, 185, 129, 0.15)' : 'rgba(245, 158, 11, 0.15)',
                borderColor: isAuthorityUser ? 'var(--color-success)' : 'var(--color-warning)',
              }}
            >
              {isAuthorityUser ? (
                <ShieldCheck size={16} color="var(--color-success)" />
              ) : (
                <ShieldAlert size={16} color="var(--color-warning)" />
              )}
              <span style={{ fontWeight: 700, fontSize: '0.78rem' }}>
                {isAuthorityUser ? 'AUTORITÉ VOIRIE' : 'UTILISATEUR'}
              </span>
              <button
                onClick={handleLogout}
                style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', display: 'flex' }}
                title="Déconnexion"
              >
                <LogOut size={14} />
              </button>
            </div>
          ) : (
            <button className="btn btn-primary" onClick={() => setShowLoginModal(true)}>
              <LogIn size={15} />
              <span>Connexion Autorité</span>
            </button>
          )}

          {/* Language Toggle */}
          <button className="btn btn-secondary" onClick={() => setLang(lang === 'fr' ? 'en' : 'fr')}>
            <Globe size={14} />
            <span>{lang.toUpperCase()}</span>
          </button>
        </div>
      </header>

      {/* ── KPI Strip (Class, Priority, Status Breakdown) ────────────────────── */}
      <section className="kpi-strip">
        {/* Class Counts */}
        <div className="kpi-group">
          <span className="kpi-group-title">CLASSES D'ANOMALIES</span>
          <div className="kpi-items">
            <div className="kpi-pill" title="D40 Pothole">
              <span className="dot" style={{ background: DAMAGE_CLASSES.D40.color }} />
              <span className="label">D40 Nid-de-poule</span>
              <strong className="val mono">{kpis.classCounts.D40}</strong>
            </div>
            <div className="kpi-pill" title="D20 Alligator Crack">
              <span className="dot" style={{ background: DAMAGE_CLASSES.D20.color }} />
              <span className="label">D20 Faïençage</span>
              <strong className="val mono">{kpis.classCounts.D20}</strong>
            </div>
            <div className="kpi-pill" title="D10 Transverse Crack">
              <span className="dot" style={{ background: DAMAGE_CLASSES.D10.color }} />
              <span className="label">D10 Transversale</span>
              <strong className="val mono">{kpis.classCounts.D10}</strong>
            </div>
            <div className="kpi-pill" title="D00 Longitudinal Crack">
              <span className="dot" style={{ background: DAMAGE_CLASSES.D00.color }} />
              <span className="label">D00 Longitudinale</span>
              <strong className="val mono">{kpis.classCounts.D00}</strong>
            </div>
          </div>
        </div>

        {/* Priority Counts */}
        <div className="kpi-group">
          <span className="kpi-group-title">NIVEAU DE PRIORITÉ</span>
          <div className="kpi-items">
            <div className="kpi-pill">
              <span className="dot" style={{ background: PRIORITY_PIN_COLORS.HIGH }} />
              <span className="label">HIGH (&gt;65)</span>
              <strong className="val mono" style={{ color: PRIORITY_PIN_COLORS.HIGH }}>
                {kpis.priorityCounts.HIGH}
              </strong>
            </div>
            <div className="kpi-pill">
              <span className="dot" style={{ background: PRIORITY_PIN_COLORS.MEDIUM }} />
              <span className="label">MEDIUM (35–65)</span>
              <strong className="val mono" style={{ color: PRIORITY_PIN_COLORS.MEDIUM }}>
                {kpis.priorityCounts.MEDIUM}
              </strong>
            </div>
            <div className="kpi-pill">
              <span className="dot" style={{ background: PRIORITY_PIN_COLORS.LOW }} />
              <span className="label">LOW (&lt;35)</span>
              <strong className="val mono" style={{ color: PRIORITY_PIN_COLORS.LOW }}>
                {kpis.priorityCounts.LOW}
              </strong>
            </div>
          </div>
        </div>

        {/* Status Counts */}
        <div className="kpi-group">
          <span className="kpi-group-title">WORKFLOW AUTORITÉ</span>
          <div className="kpi-items">
            <div className="kpi-pill">
              <span className="dot" style={{ background: '#9CA3AF' }} />
              <span className="label">Non confirmé</span>
              <strong className="val mono">{kpis.statusCounts.unconfirmed}</strong>
            </div>
            <div className="kpi-pill">
              <span className="dot" style={{ background: '#F59E0B' }} />
              <span className="label">Confirmé</span>
              <strong className="val mono" style={{ color: '#F59E0B' }}>
                {kpis.statusCounts.confirmed}
              </strong>
            </div>
            <div className="kpi-pill">
              <span className="dot" style={{ background: '#10B981' }} />
              <span className="label">Réparé</span>
              <strong className="val mono" style={{ color: '#10B981' }}>
                {kpis.statusCounts.repaired}
              </strong>
            </div>
          </div>
        </div>
      </section>

      {/* ── Main Layout: Map + Side Panel ───────────────────────────────────── */}
      <div className="main-layout">
        {/* Left Map View */}
        <div className="map-wrapper">
          <div ref={mapRef} style={{ width: '100%', height: '100%' }} />

          {/* Quick Filters Overlay */}
          <div className="map-filter-overlay">
            <select
              className="select-input"
              value={classFilter}
              onChange={(e) => setClassFilter(e.target.value)}
            >
              <option value="all">Classe: Tous</option>
              <option value="D40">D40 (Nid-de-poule)</option>
              <option value="D20">D20 (Faïençage)</option>
              <option value="D10">D10 (Transversale)</option>
              <option value="D00">D00 (Longitudinale)</option>
            </select>

            <select
              className="select-input"
              value={priorityFilter}
              onChange={(e) => setPriorityFilter(e.target.value)}
            >
              <option value="all">Priorité: Tous</option>
              <option value="HIGH">HIGH (&gt;65)</option>
              <option value="MEDIUM">MEDIUM (35–65)</option>
              <option value="LOW">LOW (&lt;35)</option>
            </select>

            <select
              className="select-input"
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
            >
              <option value="all">Statut: Tous</option>
              <option value="unconfirmed">Non confirmé</option>
              <option value="confirmed">Confirmé</option>
              <option value="repaired">Réparé</option>
            </select>
          </div>

          {/* Map Legend */}
          <div className="map-legend">
            <span style={{ fontSize: '0.72rem', fontWeight: 800, color: 'var(--text-muted)' }}>
              LÉGENDE CARTE (COULEUR = PRIORITÉ • TAILLE = SÉVÉRITÉ)
            </span>
            <div style={{ display: 'flex', gap: '14px', marginTop: '6px', flexWrap: 'wrap' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.75rem' }}>
                <span style={{ width: '12px', height: '12px', borderRadius: '50%', background: PRIORITY_PIN_COLORS.HIGH, display: 'inline-block' }} />
                <span>HIGH (&gt;65)</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.75rem' }}>
                <span style={{ width: '12px', height: '12px', borderRadius: '50%', background: PRIORITY_PIN_COLORS.MEDIUM, display: 'inline-block' }} />
                <span>MEDIUM (35–65)</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.75rem' }}>
                <span style={{ width: '12px', height: '12px', borderRadius: '50%', background: PRIORITY_PIN_COLORS.LOW, display: 'inline-block' }} />
                <span>LOW (&lt;35)</span>
              </div>
            </div>
          </div>
        </div>

        {/* Right Side Panel: Cluster Details & Report List */}
        <aside className="sidebar">
          {selectedCluster ? (
            <div className="cluster-detail-panel">
              {/* Cluster Header */}
              <div className="panel-header">
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span
                      className="class-badge"
                      style={{
                        background: DAMAGE_CLASSES[selectedCluster.dominantClass]?.color || '#EF4444',
                      }}
                    >
                      {selectedCluster.dominantClass}
                    </span>
                    <h2 style={{ fontSize: '1rem', fontWeight: 800 }}>
                      {DAMAGE_CLASSES[selectedCluster.dominantClass]?.fr || 'Anomalie'}
                    </h2>
                  </div>
                  <p className="mono" style={{ fontSize: '0.74rem', color: 'var(--text-dim)', marginTop: '4px' }}>
                    {selectedCluster.latitude.toFixed(6)}, {selectedCluster.longitude.toFixed(6)}
                  </p>
                </div>
                <button
                  className="icon-btn"
                  onClick={() => setSelectedCluster(null)}
                  title="Fermer la sélection"
                >
                  <X size={16} />
                </button>
              </div>

              {/* Cluster KPI Grid */}
              <div className="cluster-kpi-grid">
                <div className="cluster-kpi-card">
                  <span className="lbl">SCORE MAX</span>
                  <strong
                    className="val mono"
                    style={{
                      color: PRIORITY_PIN_COLORS[selectedCluster.priorityLabel],
                    }}
                  >
                    {selectedCluster.maxPriorityScore} ({selectedCluster.priorityLabel})
                  </strong>
                </div>
                <div className="cluster-kpi-card">
                  <span className="lbl">SIGNALEMENTS (20M)</span>
                  <strong className="val mono">{selectedCluster.count}</strong>
                </div>
                <div className="cluster-kpi-card">
                  <span className="lbl">STATUT CLUSTER</span>
                  <span
                    className={`badge ${STATUS_LABELS[selectedCluster.status]?.badge || 'badge-gray'}`}
                    style={{ fontSize: '0.72rem', alignSelf: 'flex-start', marginTop: '2px' }}
                  >
                    {STATUS_LABELS[selectedCluster.status]?.fr || selectedCluster.status}
                  </span>
                </div>
                <div className="cluster-kpi-card">
                  <span className="lbl">DERNIER PASSAGE</span>
                  <span style={{ fontSize: '0.75rem', color: 'var(--text-main)', marginTop: '2px' }}>
                    {new Date(selectedCluster.newestDate).toLocaleDateString()}
                  </span>
                </div>
              </div>

              {/* Reports in Cluster Section */}
              <div className="reports-section">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                  <h3 style={{ fontSize: '0.85rem', fontWeight: 700, textTransform: 'uppercase', color: 'var(--text-muted)' }}>
                    Rapports du cluster ({selectedCluster.members.length})
                  </h3>
                  <span style={{ fontSize: '0.72rem', color: 'var(--text-dim)' }}>
                    Rayon DBSCAN 20m
                  </span>
                </div>

                <div className="report-items-list">
                  {selectedCluster.members.map((obs, idx) => {
                    const det = obs.detections?.[0];
                    const classCode = obs.anomaly_type || det?.class_code || 'D40';
                    const conf = det?.confidence !== undefined ? det.confidence : null;

                    return (
                      <div key={obs.id} className="report-card">
                        <div style={{ display: 'flex', gap: '12px' }}>
                          {/* Image thumbnail (Signed URL short expiry) */}
                          <div style={{ width: '80px', flexShrink: 0 }}>
                            <ReportImageThumbnail
                              storagePath={obs.storage_path}
                              bucket={obs.bucket}
                              isAuthority={isAuthorityUser}
                            />
                          </div>

                          {/* Report metadata */}
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                              <span style={{ fontWeight: 700, fontSize: '0.82rem', color: DAMAGE_CLASSES[classCode]?.color }}>
                                #{idx + 1} {classCode} ({DAMAGE_CLASSES[classCode]?.fr})
                              </span>
                              <span className={`badge ${STATUS_LABELS[obs.status]?.badge || 'badge-gray'}`} style={{ fontSize: '0.68rem' }}>
                                {STATUS_LABELS[obs.status]?.fr || obs.status}
                              </span>
                            </div>

                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '4px', marginTop: '6px', fontSize: '0.74rem' }}>
                              <div>
                                <span style={{ color: 'var(--text-dim)' }}>Confiance IA: </span>
                                <strong style={{ color: conf && conf >= 0.7 ? 'var(--color-success)' : 'var(--text-muted)' }}>
                                  {conf !== null ? `${Math.round(conf * 100)}%` : '--'}
                                </strong>
                              </div>
                              <div>
                                <span style={{ color: 'var(--text-dim)' }}>Score: </span>
                                <strong className="mono">{obs.priority_score || '--'}</strong>
                              </div>
                            </div>

                            <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginTop: '4px' }}>
                              {new Date(obs.created_at).toLocaleString()}
                            </div>

                            {/* Authority Status Workflow Actions */}
                            {isAuthorityUser && (
                              <div style={{ display: 'flex', gap: '6px', marginTop: '8px' }}>
                                {obs.status === 'unconfirmed' && (
                                  <button
                                    className="btn-status btn-confirm"
                                    onClick={() => promptStatusUpdate(obs.id, 'unconfirmed', 'confirmed')}
                                  >
                                    <CheckCircle2 size={12} />
                                    <span>Confirmer anomalie</span>
                                  </button>
                                )}
                                {obs.status === 'confirmed' && (
                                  <button
                                    className="btn-status btn-repair"
                                    onClick={() => promptStatusUpdate(obs.id, 'confirmed', 'repaired')}
                                  >
                                    <Wrench size={12} />
                                    <span>Marquer réparé</span>
                                  </button>
                                )}
                                {obs.status === 'repaired' && (
                                  <span style={{ fontSize: '0.7rem', color: 'var(--color-success)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                                    <CheckCircle2 size={12} /> Réparé & Validé
                                  </span>
                                )}
                              </div>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          ) : (
            <div className="panel-empty-state">
              <Layers size={36} style={{ opacity: 0.4, color: 'var(--color-primary)' }} />
              <h3 style={{ fontSize: '0.95rem', fontWeight: 700, marginTop: '8px' }}>
                Sélectionnez un cluster sur la carte
              </h3>
              <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', textAlign: 'center', maxWidth: '280px', lineHeight: 1.4, marginTop: '4px' }}>
                Cliquez sur n'importe quel marqueur géodésique pour afficher les signalements concordants, les clichés certifiés et le workflow de réparation.
              </p>

              {/* Cluster Ranked List in Empty State */}
              <div style={{ width: '100%', marginTop: '16px' }}>
                <span style={{ fontSize: '0.72rem', fontWeight: 800, color: 'var(--text-dim)', textTransform: 'uppercase' }}>
                  Top clusters prioritaires ({filteredClusters.length})
                </span>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '8px', maxHeight: '340px', overflowY: 'auto' }}>
                  {filteredClusters.slice(0, 15).map((c, i) => (
                    <div
                      key={c.id}
                      className="cluster-list-row"
                      onClick={() => setSelectedCluster(c)}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <span className="mono" style={{ fontSize: '0.75rem', color: 'var(--text-dim)' }}>#{i + 1}</span>
                        <span style={{ fontWeight: 700, fontSize: '0.8rem', color: DAMAGE_CLASSES[c.dominantClass]?.color }}>
                          {c.dominantClass}
                        </span>
                        <span style={{ fontSize: '0.74rem', color: 'var(--text-muted)' }}>
                          {c.count} {c.count > 1 ? 'passages' : 'passage'}
                        </span>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <strong className="mono" style={{ fontSize: '0.8rem', color: PRIORITY_PIN_COLORS[c.priorityLabel] }}>
                          {c.maxPriorityScore}
                        </strong>
                        <ChevronRight size={14} color="var(--text-dim)" />
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
        </aside>
      </div>

      {/* ── Status Change Confirmation Modal ────────────────────────────────── */}
      {statusConfirmModal && (
        <div className="modal-overlay" onClick={() => setStatusConfirmModal(null)}>
          <div className="modal-card" style={{ maxWidth: '420px' }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: '24px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px' }}>
                <h3 style={{ fontSize: '1.05rem', fontWeight: 800, color: 'var(--text-main)' }}>
                  Confirmation du changement de statut
                </h3>
                <X size={18} style={{ cursor: 'pointer' }} onClick={() => setStatusConfirmModal(null)} />
              </div>

              <p style={{ fontSize: '0.84rem', color: 'var(--text-muted)', lineHeight: 1.5, marginBottom: '16px' }}>
                Voulez-vous modifier le statut de cette observation :
              </p>

              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '14px', padding: '12px', background: 'rgba(255,255,255,0.03)', borderRadius: 'var(--radius-sm)', marginBottom: '18px' }}>
                <span className={`badge ${STATUS_LABELS[statusConfirmModal.currentStatus]?.badge || 'badge-gray'}`}>
                  {STATUS_LABELS[statusConfirmModal.currentStatus]?.fr || statusConfirmModal.currentStatus}
                </span>
                <ArrowRight size={16} color="var(--text-dim)" />
                <span className={`badge ${STATUS_LABELS[statusConfirmModal.newStatus]?.badge || 'badge-gray'}`}>
                  {STATUS_LABELS[statusConfirmModal.newStatus]?.fr || statusConfirmModal.newStatus}
                </span>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
                <button
                  className="btn btn-secondary"
                  onClick={() => setStatusConfirmModal(null)}
                  disabled={statusUpdating}
                >
                  Annuler
                </button>
                <button
                  className="btn btn-primary"
                  onClick={executeStatusUpdate}
                  disabled={statusUpdating}
                >
                  {statusUpdating ? 'Mise à jour en cours...' : 'Confirmer la modification'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Honest Metrics Panel Modal (Loaded from JSON file) ──────────────── */}
      {showMetricsPanel && (
        <div className="modal-overlay" onClick={() => setShowMetricsPanel(false)}>
          <div className="modal-card" style={{ maxWidth: '640px' }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: '24px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                <div>
                  <h3 style={{ fontSize: '1.15rem', fontWeight: 800, color: 'var(--text-main)' }}>
                    Métriques d'Évaluation Honnêtes & Limites IA
                  </h3>
                  <span style={{ fontSize: '0.75rem', color: 'var(--text-dim)' }}>
                    Source: {validationMetricsData.model_name} • {validationMetricsData.evaluation_split}
                  </span>
                </div>
                <X size={18} style={{ cursor: 'pointer' }} onClick={() => setShowMetricsPanel(false)} />
              </div>

              {/* Warning Statement Banner */}
              <div style={{ padding: '12px 14px', background: 'rgba(239, 68, 68, 0.12)', border: '1px solid rgba(239, 68, 68, 0.3)', borderRadius: 'var(--radius-sm)', marginBottom: '18px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--color-critical)', fontWeight: 700, fontSize: '0.85rem' }}>
                  <AlertTriangle size={16} />
                  <span>{validationMetricsData.warning_highlight}</span>
                </div>
                <p style={{ fontSize: '0.8rem', color: 'var(--text-main)', marginTop: '6px', lineHeight: 1.45 }}>
                  {validationMetricsData.statement}
                </p>
              </div>

              {/* Validation Metrics Table */}
              <table className="metrics-table">
                <thead>
                  <tr>
                    <th>Classe</th>
                    <th>Nom</th>
                    <th>Précision</th>
                    <th>Rappel</th>
                    <th>mAP50</th>
                    <th>Fiabilité</th>
                  </tr>
                </thead>
                <tbody>
                  {validationMetricsData.per_class_metrics.map((row) => (
                    <tr key={row.class_code}>
                      <td>
                        <span className="mono" style={{ fontWeight: 800, color: DAMAGE_CLASSES[row.class_code]?.color }}>
                          {row.class_code}
                        </span>
                      </td>
                      <td>{row.class_name_fr}</td>
                      <td className="mono">{row.precision.toFixed(3)}</td>
                      <td className="mono">{row.recall.toFixed(3)}</td>
                      <td className="mono">{row.map50.toFixed(4)}</td>
                      <td>
                        <span
                          className="badge"
                          style={{
                            background: row.reliability === 'Low' ? 'rgba(239,68,68,0.2)' : 'rgba(16,185,129,0.2)',
                            color: row.reliability === 'Low' ? 'var(--color-critical)' : 'var(--color-success)',
                            fontSize: '0.7rem',
                          }}
                        >
                          {row.assessment}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>

              <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '20px' }}>
                <button className="btn btn-secondary" onClick={() => setShowMetricsPanel(false)}>
                  Fermer
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

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
                <div style={{ padding: '8px', background: 'rgba(239, 68, 68, 0.15)', border: '1px solid var(--color-critical)', borderRadius: 'var(--radius-sm)', color: '#FFF', fontSize: '0.78rem', marginBottom: '12px' }}>
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
                  className="btn btn-primary"
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
    </div>
  );
}
