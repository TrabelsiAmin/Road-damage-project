import React, { useState, useEffect, useMemo, useRef } from 'react';
import L from 'leaflet';
import {
  DAMAGE_CLASSES,
  SEVERITY_COLORS,
  STATUS_LABELS,
  I18N,
} from './constants';
import { fetchObservations, updateObservationStatus } from './supabase';
import { clusterObservations, calculateRoadHealthScore } from './utils/clustering';
import {
  MapPin,
  AlertTriangle,
  FileSpreadsheet,
  Printer,
  DollarSign,
  Clock,
  ShieldCheck,
  Globe,
  Layers,
  CheckCircle2,
  X,
  ExternalLink,
  ChevronRight,
  Info,
} from 'lucide-react';

export default function App() {
  const [lang, setLang] = useState('fr');
  const t = I18N[lang];

  const [observations, setObservations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Filters
  const [classFilter, setClassFilter] = useState('all');
  const [severityFilter, setSeverityFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');

  // UI state
  const [activeTab, setActiveTab] = useState('priority'); // priority | budget | accountability
  const [selectedCluster, setSelectedCluster] = useState(null);
  const [workOrderModal, setWorkOrderModal] = useState(null);

  // Budget assumptions (Tunisian Dinars - editable)
  const [unitCosts, setUnitCosts] = useState({
    D40: 280,
    D20: 450,
    D00: 120,
    D10: 120,
  });
  const [budgetTnd, setBudgetTnd] = useState(3500);

  // Leaflet Map Reference
  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersLayerRef = useRef(null);

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

  // ── 5. Initialize Leaflet Map ──────────────────────────────────────────────
  useEffect(() => {
    if (!mapRef.current) return;

    if (!mapInstanceRef.current) {
      const defaultCenter = [36.8065, 10.1815]; // Tunis
      const map = L.map(mapRef.current, {
        center: defaultCenter,
        zoom: 14,
        zoomControl: true,
      });

      // CartoDB Dark Matter tile layer
      L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
        maxZoom: 19,
      }).addTo(map);

      markersLayerRef.current = L.layerGroup().addTo(map);
      mapInstanceRef.current = map;
    }
  }, []);

  // ── 6. Update Map Markers with Cluster Data ────────────────────────────────
  useEffect(() => {
    const map = mapInstanceRef.current;
    const layer = markersLayerRef.current;
    if (!map || !layer) return;

    layer.clearLayers();

    if (filteredClusters.length === 0) return;

    const bounds = L.latLngBounds();

    filteredClusters.forEach((c) => {
      const clsInfo = DAMAGE_CLASSES[c.dominantClass] || DAMAGE_CLASSES.D40;
      const size = Math.min(46, 28 + c.count * 3);

      const markerHtml = `
        <div class="tariq-marker" style="
          width: ${size}px;
          height: ${size}px;
          background-color: ${clsInfo.color};
          border: 2px solid #ffffff;
        ">
          ${c.count > 1 ? c.count : c.dominantClass}
        </div>
      `;

      const customIcon = L.divIcon({
        html: markerHtml,
        className: 'custom-leaflet-marker',
        iconSize: [size, size],
        iconAnchor: [size / 2, size / 2],
      });

      const marker = L.marker([c.latitude, c.longitude], { icon: customIcon });

      marker.on('click', () => {
        setSelectedCluster(c);
      });

      layer.addLayer(marker);
      bounds.extend([c.latitude, c.longitude]);
    });

    if (bounds.isValid() && filteredClusters.length > 0) {
      map.fitBounds(bounds, { padding: [50, 50], maxZoom: 16 });
    }
  }, [filteredClusters]);

  // ── 7. Greedy Budget Optimization (Knapsack heuristic) ─────────────────────
  const budgetAllocation = useMemo(() => {
    let remainingBudget = budgetTnd;
    const selected = [];
    let totalSpent = 0;

    // Sort by Priority Score / Cost efficiency
    const candidates = [...clusters].map((c) => {
      const cost = unitCosts[c.dominantClass] || 250;
      const efficiency = c.maxPriorityScore / cost;
      return { ...c, cost, efficiency };
    });

    candidates.sort((a, b) => b.efficiency - a.efficiency || b.maxPriorityScore - a.maxPriorityScore);

    for (const item of candidates) {
      if (item.cost <= remainingBudget) {
        selected.push(item);
        remainingBudget -= item.cost;
        totalSpent += item.cost;
      }
    }

    return {
      selected,
      totalSpent,
      remainingBudget,
    };
  }, [clusters, budgetTnd, unitCosts]);

  // ── 8. Export CSV ──────────────────────────────────────────────────────────
  const exportCsv = () => {
    const headers = ['ID', 'Class', 'Priority_Score', 'Priority_Label', 'Sightings', 'Status', 'Latitude', 'Longitude', 'First_Seen'];
    const rows = filteredClusters.map((c) => [
      c.id,
      c.dominantClass,
      c.maxPriorityScore,
      c.priorityLabel,
      c.count,
      c.status,
      c.latitude.toFixed(6),
      c.longitude.toFixed(6),
      c.oldestDate,
    ]);

    const csvContent = 'data:text/csv;charset=utf-8,' + [headers, ...rows].map((e) => e.join(',')).join('\n');
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement('a');
    link.setAttribute('href', encodedUri);
    link.setAttribute('download', `tariqmap_workorders_${new Date().toISOString().slice(0, 10)}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  return (
    <div className="app-container">
      {/* ── Header ─────────────────────────────────────────────────────────── */}
      <header className="header">
        <div className="header-brand">
          <div className="logo-badge">
            <ShieldCheck size={22} color="#ffffff" />
          </div>
          <div>
            <h1 className="header-title">{t.title}</h1>
            <p className="header-subtitle">{t.subtitle}</p>
          </div>
        </div>

        <div className="header-actions">
          <button className="btn" onClick={() => setLang(lang === 'fr' ? 'en' : 'fr')}>
            <Globe size={15} />
            <span>{t.switchLang}</span>
          </button>
          <button className="btn btn-primary" onClick={exportCsv}>
            <FileSpreadsheet size={15} />
            <span>{t.exportCsv}</span>
          </button>
        </div>
      </header>

      {/* ── Demo Banner ────────────────────────────────────────────────────── */}
      {hasDemoData && (
        <div className="demo-banner">
          <div>
            <span className="demo-tag">DEMO DATA</span>
            <span>{t.demoBanner}</span>
          </div>
          <span className="mono" style={{ fontSize: '0.75rem', opacity: 0.8 }}>
            is_demo = true
          </span>
        </div>
      )}

      {/* ── Main Split View ────────────────────────────────────────────────── */}
      <div className="dashboard-grid">
        {/* Map Pane */}
        <div className="map-pane">
          <div ref={mapRef} style={{ width: '100%', height: '100%' }} />
        </div>

        {/* Sidebar Pane */}
        <div className="sidebar-pane">
          {/* Navigation Tabs */}
          <div className="sidebar-tabs">
            <button
              className={`tab-btn ${activeTab === 'priority' ? 'active' : ''}`}
              onClick={() => setActiveTab('priority')}
            >
              <AlertTriangle size={16} />
              <span>{t.priorityRankedList}</span>
            </button>
            <button
              className={`tab-btn ${activeTab === 'budget' ? 'active' : ''}`}
              onClick={() => setActiveTab('budget')}
            >
              <DollarSign size={16} />
              <span>{t.budgetOptimizer}</span>
            </button>
            <button
              className={`tab-btn ${activeTab === 'accountability' ? 'active' : ''}`}
              onClick={() => setActiveTab('accountability')}
            >
              <Clock size={16} />
              <span>{t.accountability}</span>
            </button>
          </div>

          <div className="sidebar-content">
            {/* ── Metrics Cards ────────────────────────────────────────────── */}
            <div className="metrics-row">
              <div className="metric-card">
                <span className="metric-label">{t.totalDefects}</span>
                <span className="metric-value">{totalDefects}</span>
              </div>
              <div className="metric-card">
                <span className="metric-label">{t.criticalCount}</span>
                <span className="metric-value" style={{ color: 'var(--color-critical)' }}>
                  {criticalCount}
                </span>
              </div>
              <div className="metric-card" title={t.healthTooltip}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <span className="metric-label">{t.healthScore}</span>
                  <Info size={13} color="var(--text-dim)" />
                </div>
                <span
                  className="metric-value"
                  style={{
                    color: healthScore > 75 ? 'var(--color-success)' : healthScore > 45 ? 'var(--color-warning)' : 'var(--color-critical)',
                  }}
                >
                  {healthScore}/100
                </span>
              </div>
            </div>

            {/* ── Tab 1: Priority Queue ─────────────────────────────────────── */}
            {activeTab === 'priority' && (
              <>
                {/* Filter Bar */}
                <div className="filter-bar">
                  <select
                    className="select-input"
                    value={classFilter}
                    onChange={(e) => setClassFilter(e.target.value)}
                  >
                    <option value="all">{t.filterClass}: {t.all}</option>
                    {Object.values(DAMAGE_CLASSES).map((c) => (
                      <option key={c.code} value={c.code}>
                        {c.code} - {lang === 'fr' ? c.fr : c.en}
                      </option>
                    ))}
                  </select>

                  <select
                    className="select-input"
                    value={severityFilter}
                    onChange={(e) => setSeverityFilter(e.target.value)}
                  >
                    <option value="all">{t.filterSeverity}: {t.all}</option>
                    {Object.keys(SEVERITY_COLORS).map((s) => (
                      <option key={s} value={s}>
                        {lang === 'fr' ? SEVERITY_COLORS[s].fr : SEVERITY_COLORS[s].label}
                      </option>
                    ))}
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

                {/* Queue Cards */}
                {loading ? (
                  <div style={{ padding: '32px', textAlign: 'center', color: 'var(--text-muted)' }}>
                    Loading road damage records...
                  </div>
                ) : filteredClusters.length === 0 ? (
                  <div style={{ padding: '32px', textAlign: 'center', color: 'var(--text-dim)' }}>
                    No defects match current filters.
                  </div>
                ) : (
                  filteredClusters.map((cluster) => {
                    const clsInfo = DAMAGE_CLASSES[cluster.dominantClass] || DAMAGE_CLASSES.D40;
                    const statusInfo = STATUS_LABELS[cluster.status] || STATUS_LABELS.unconfirmed;

                    return (
                      <div
                        key={cluster.id}
                        className="hazard-card"
                        onClick={() => setSelectedCluster(cluster)}
                      >
                        {cluster.photoUrl ? (
                          <img src={cluster.photoUrl} alt="Hazard" className="hazard-thumb" />
                        ) : (
                          <div
                            className="hazard-thumb"
                            style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                          >
                            <MapPin size={22} color="var(--text-dim)" />
                          </div>
                        )}

                        <div className="hazard-details">
                          <div className="hazard-header">
                            <span
                              className="badge"
                              style={{ background: clsInfo.bgLight, color: clsInfo.color, border: `1px solid ${clsInfo.color}` }}
                            >
                              {cluster.dominantClass} • {lang === 'fr' ? clsInfo.fr : clsInfo.en}
                            </span>
                            <span className="score-pill" style={{ color: clsInfo.color }}>
                              {cluster.maxPriorityScore} pts
                            </span>
                          </div>

                          <div className="hazard-meta">
                            <span>{cluster.count} {t.sightings}</span>
                            <span>{cluster.ageDays}d ago</span>
                            <span className={`badge ${statusInfo.badge}`}>
                              {lang === 'fr' ? statusInfo.fr : statusInfo.en}
                            </span>
                          </div>

                          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '6px' }}>
                            <span className="mono" style={{ fontSize: '0.72rem', color: 'var(--text-dim)' }}>
                              {cluster.latitude.toFixed(4)}, {cluster.longitude.toFixed(4)}
                            </span>
                            <button
                              className="btn"
                              style={{ padding: '2px 8px', fontSize: '0.72rem' }}
                              onClick={(e) => {
                                e.stopPropagation();
                                setWorkOrderModal(cluster);
                              }}
                            >
                              <Printer size={12} />
                              <span>{t.printWorkOrder}</span>
                            </button>
                          </div>
                        </div>
                      </div>
                    );
                  })
                )}
              </>
            )}

            {/* ── Tab 2: Budget Optimizer ───────────────────────────────────── */}
            {activeTab === 'budget' && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <div className="metric-card">
                  <span className="metric-label">{t.budgetInput}</span>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '6px' }}>
                    <input
                      type="number"
                      className="text-input"
                      style={{ fontSize: '1.2rem', fontWeight: 700, width: '160px' }}
                      value={budgetTnd}
                      onChange={(e) => setBudgetTnd(Number(e.target.value) || 0)}
                    />
                    <span className="mono" style={{ color: 'var(--text-muted)' }}>TND</span>
                  </div>
                </div>

                <div className="metric-card">
                  <span className="metric-label" style={{ marginBottom: '8px' }}>
                    Cost Assumptions (Unit Cost per Fix - Estimate)
                  </span>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
                    {Object.keys(unitCosts).map((code) => (
                      <div key={code} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                        <span style={{ fontSize: '0.8rem', color: DAMAGE_CLASSES[code].color }}>
                          {code} ({lang === 'fr' ? DAMAGE_CLASSES[code].fr : DAMAGE_CLASSES[code].en}):
                        </span>
                        <input
                          type="number"
                          className="text-input"
                          style={{ width: '80px', padding: '4px 6px', fontSize: '0.8rem' }}
                          value={unitCosts[code]}
                          onChange={(e) =>
                            setUnitCosts({ ...unitCosts, [code]: Number(e.target.value) || 0 })
                          }
                        />
                      </div>
                    ))}
                  </div>
                </div>

                <div className="metric-card" style={{ borderColor: 'var(--color-primary)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span className="metric-label">Greedy Fix Selection</span>
                    <span className="mono" style={{ fontSize: '0.8rem', color: 'var(--color-primary)' }}>
                      {budgetAllocation.selected.length} Hazards Funded
                    </span>
                  </div>
                  <div style={{ marginTop: '8px', display: 'flex', justifyContent: 'space-between', fontSize: '0.9rem' }}>
                    <span>{t.cumulativeCost}:</span>
                    <span className="mono" style={{ fontWeight: 700 }}>
                      {budgetAllocation.totalSpent.toLocaleString()} TND (Est.)
                    </span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                    <span>Remaining Reserve:</span>
                    <span className="mono">{budgetAllocation.remainingBudget.toLocaleString()} TND</span>
                  </div>
                </div>

                <div style={{ maxHeight: '280px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '8px' }}>
                  {budgetAllocation.selected.map((item, idx) => (
                    <div
                      key={item.id}
                      style={{
                        padding: '8px 12px',
                        background: 'rgba(255, 255, 255, 0.02)',
                        border: '1px solid var(--border-subtle)',
                        borderRadius: 'var(--radius-sm)',
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        fontSize: '0.82rem',
                      }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <span className="mono" style={{ color: 'var(--text-dim)' }}>#{idx + 1}</span>
                        <span style={{ fontWeight: 600, color: DAMAGE_CLASSES[item.dominantClass].color }}>
                          {item.dominantClass}
                        </span>
                        <span>{item.maxPriorityScore} pts</span>
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
                  <span className="metric-label">Repair Verification Loop (Phase 3)</span>
                  <div style={{ marginTop: '12px', padding: '12px', background: 'rgba(59, 130, 246, 0.08)', borderRadius: 'var(--radius-sm)', border: '1px solid rgba(59, 130, 246, 0.2)' }}>
                    <p style={{ fontSize: '0.82rem', color: 'var(--text-main)', lineHeight: 1.5 }}>
                      When citizen & municipal survey devices traverse a flagged pothole location without re-detecting damage, the system logs an audit clear-pass.
                    </p>
                    <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '8px' }}>
                      {t.repairCycleNote}
                    </p>
                  </div>
                </div>

                <div className="metric-card">
                  <span className="metric-label">Average Time to Repair (MTTR)</span>
                  <span className="metric-value mono" style={{ fontSize: '1.2rem', color: 'var(--text-muted)' }}>
                    -- days (Awaiting Phase 3 logs)
                  </span>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* ── Printable Work Order Modal ──────────────────────────────────────── */}
      {workOrderModal && (
        <div className="modal-overlay" onClick={() => setWorkOrderModal(null)}>
          <div className="modal-card" onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: '24px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', borderBottom: '2px solid #000', paddingBottom: '16px', marginBottom: '20px' }}>
                <div>
                  <h2 style={{ fontSize: '1.2rem', fontWeight: 800 }}>{t.workOrderTitle}</h2>
                  <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                    REPUBLIQUE TUNISIENNE • MINISTERE DE L'EQUIPEMENT
                  </p>
                </div>
                <button className="btn" onClick={() => window.print()}>
                  <Printer size={15} />
                  <span>Print / Save PDF</span>
                </button>
              </div>

              {workOrderModal.photoUrl && (
                <div style={{ marginBottom: '16px', textAlign: 'center' }}>
                  <img
                    src={workOrderModal.photoUrl}
                    alt="Road defect"
                    style={{ maxHeight: '240px', width: '100%', objectFit: 'cover', borderRadius: 'var(--radius-sm)' }}
                  />
                </div>
              )}

              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem', marginBottom: '24px' }}>
                <tbody>
                  <tr style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>{t.defectType}:</td>
                    <td style={{ padding: '8px 0', fontWeight: 700 }}>
                      {workOrderModal.dominantClass} - {lang === 'fr' ? DAMAGE_CLASSES[workOrderModal.dominantClass].fr : DAMAGE_CLASSES[workOrderModal.dominantClass].en}
                    </td>
                  </tr>
                  <tr style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>Priority Score:</td>
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
                    <td style={{ padding: '8px 0' }}>{workOrderModal.count} independent surveys</td>
                  </tr>
                  <tr style={{ borderBottom: '1px solid var(--border-subtle)' }}>
                    <td style={{ padding: '8px 0', color: 'var(--text-muted)' }}>Estimated Intervention Cost:</td>
                    <td style={{ padding: '8px 0' }} className="mono">
                      {unitCosts[workOrderModal.dominantClass]} TND (Estimate)
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
