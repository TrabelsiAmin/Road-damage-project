import React, { useState, useEffect, useMemo, useRef, useCallback } from 'react';
import L from 'leaflet';
import {
  DAMAGE_CLASSES,
  SEVERITY_COLORS,
  STATUS_LABELS,
  I18N,
  MAP_CONFIG,
} from './constants';
import {
  fetchObservations,
  updateObservationStatus,
  updateMultipleObservationsStatus,
  signIn,
  signOut,
  getCurrentUser,
  checkIsAuthority,
  getMediaUrl,
  getSignedMediaUrl,
  getPublicMediaUrl,
  fetchMediaFilesForObservations,
  fetchServerClusters,
  supabase,
} from './supabase';
import { haversineDistanceMeters } from './utils/clustering';
import { MinistryOverview } from './components/MinistryOverview';
import { TechnicalRecommendation } from './components/TechnicalRecommendation';
import {
  buildMinistryOverview,
  isWithinPeriod,
  matchesObservationFilters,
  observationClass,
  observationPriority,
  observationTime,
} from './utils/ministryAnalytics';
import { calculatePriorityScore, PRIORITY_CONFIG } from './utils/priorityScoring';
import {
  buildMapRagPopupHtml,
  buildTechnicalQuestion,
  observationForRecommendation,
} from './utils/ragClient';
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
  ChevronLeft,
  Eye,
  Camera,
  CameraOff,
  Layers,
  Wrench,
  Clock,
  ArrowRight,
  Lock,
  XCircle,
  Trash2,
  RotateCcw,
  Info,
  BookOpen,
} from 'lucide-react';

// Priority Colors for Leaflet pins (v2: HIGH, MEDIUM, LOW)
const PRIORITY_PIN_COLORS = {
  HIGH: '#EF4444',     // Red
  CRITICAL: '#EF4444', // Red fallback
  MEDIUM: '#F59E0B',   // Amber
  LOW: '#3B82F6',      // Blue
};

/**
 * Score formatter: rounds to 1 decimal place.
 */
function formatScore(score) {
  if (score === null || score === undefined || isNaN(score)) return '--';
  return Number(score).toFixed(1);
}

/**
 * Image Lightbox Modal: shows original image full-size with details on click.
 */
function ImageLightbox({ image, onClose }) {
  useEffect(() => {
    function handleKeyDown(e) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  if (!image) return null;

  return (
    <div className="lightbox-backdrop" onClick={onClose}>
      <div className="lightbox-content" onClick={(e) => e.stopPropagation()}>
        <div className="lightbox-header">
          <div className="lightbox-title-area">
            <h4 className="lightbox-title">{image.title}</h4>
            <span className="lightbox-badge">{image.badge}</span>
          </div>
          <button className="icon-btn" onClick={onClose} title="Fermer (Échap)">
            <X size={20} />
          </button>
        </div>
        <div className="lightbox-body">
          <img src={image.url} alt={image.title} className="lightbox-image" />
        </div>
      </div>
    </div>
  );
}

/**
 * Report Image Card:
 * - When Authority: fetches 10-minute signed URL from observation-images for original photo,
 *   auto-refreshes 30s before expiry. Falls back to public thumbnail only if original is missing.
 * - When Citizen / Logged Out: displays public thumbnail from public-photos if available.
 * - Distinct UI states: loading ("Chargement de la photo..."), no photo uploaded ("Aucune photo enregistrée"),
 *   load failure ("Échec du chargement" + Retry button), and not authority ("Photo réservée autorité").
 * - Click-to-zoom into Lightbox.
 */
function ReportImageThumbnail({ obs, clusterMedia, isAuthority, onOpenLightbox }) {
  const orig = clusterMedia?.original || obs?.original_media;
  const thumb = clusterMedia?.thumbnail || obs?.thumbnail_media;

  const [imageUrl, setImageUrl] = useState(null);
  const [loading, setLoading] = useState(false);
  const [errorInfo, setErrorInfo] = useState(null);
  const [retryKey, setRetryKey] = useState(0);

  const hasOriginal = Boolean(orig?.storage_path);
  const hasThumbnail = Boolean(thumb?.storage_path);

  useEffect(() => {
    let active = true;
    let refreshTimer = null;

    async function resolveImage() {
      setErrorInfo(null);

      // ── Case A: User is Authority ───────────────────────────────────────────
      if (isAuthority) {
        if (hasOriginal) {
          setLoading(true);
          try {
            const res = await getSignedMediaUrl(orig.storage_path, 'observation-images', 600);
            if (!active) return;
            setImageUrl(res.signedUrl);
            setLoading(false);

            // Auto-refresh before 10min expiry (30s buffer)
            const msUntilRefresh = Math.max(30000, res.expiresAt - Date.now());
            refreshTimer = setTimeout(() => {
              if (active) resolveImage();
            }, msUntilRefresh);
          } catch (err) {
            if (!active) return;
            console.error('[ReportImageThumbnail] Error creating signed URL:', err);
            setErrorInfo(err?.message || 'Erreur d\'accès au stockage');
            setImageUrl(null);
            setLoading(false);
          }
          return;
        }

        // Fallback to public thumbnail only if original doesn't exist
        if (hasThumbnail) {
          const pubUrl = getPublicMediaUrl(thumb.storage_path, 'public-photos');
          if (active) {
            setImageUrl(pubUrl);
            setLoading(false);
          }
          return;
        }

        if (active) {
          setImageUrl(null);
          setLoading(false);
        }
        return;
      }

      // ── Case B: User is NOT Authority (Anon / Logged out) ───────────────────
      if (!isAuthority) {
        if (hasThumbnail) {
          const pubUrl = getPublicMediaUrl(thumb.storage_path, 'public-photos');
          if (active) {
            setImageUrl(pubUrl);
            setLoading(false);
          }
          return;
        }

        if (active) {
          setImageUrl(null);
          setLoading(false);
        }
      }
    }

    resolveImage();

    return () => {
      active = false;
      if (refreshTimer) clearTimeout(refreshTimer);
    };
  }, [orig?.storage_path, thumb?.storage_path, isAuthority, retryKey]);

  // State 1: Loading
  if (loading) {
    return (
      <div className="report-img-placeholder">
        <div className="spinner-sm" style={{ width: '16px', height: '16px', border: '2px solid rgba(255,255,255,0.2)', borderTopColor: 'var(--color-primary)', borderRadius: '50%', animation: 'spin 0.8s linear infinite' }} />
        <span className="placeholder-text">Chargement de la photo...</span>
      </div>
    );
  }

  // State 2: Error with Retry button
  if (errorInfo) {
    return (
      <div className="report-img-placeholder error">
        <AlertTriangle size={18} />
        <span className="placeholder-text error-text">Échec du chargement</span>
        <button
          className="btn-retry"
          onClick={() => setRetryKey((k) => k + 1)}
          title={errorInfo}
        >
          Réessayer
        </button>
      </div>
    );
  }

  // State 3: Photo loaded successfully
  if (imageUrl) {
    const isOriginal = isAuthority && hasOriginal;
    const badgeText = isOriginal ? 'Original HD (Signé 10 min)' : 'Aperçu public flouté';
    const badgeClass = isOriginal ? 'badge-signed-hd' : 'badge-public-thumb';
    const title = `#${obs.id.slice(0, 8)} • ${DAMAGE_CLASSES[obs.anomaly_type]?.fr || obs.anomaly_type || 'Anomalie'}`;

    return (
      <div
        className="report-img-container"
        onClick={() => onOpenLightbox && onOpenLightbox(imageUrl, title, badgeText)}
        title="Cliquer pour agrandir dans la visionneuse"
      >
        <img
          src={imageUrl}
          alt={title}
          className="report-img"
          onError={() => setErrorInfo('Image introuvable')}
        />
        <div className="report-img-overlay">
          <Eye size={20} />
        </div>
        <span className={`report-img-badge ${badgeClass}`}>{badgeText}</span>
      </div>
    );
  }

  // State 4: Not Authority (photo exists in private bucket, but user lacks authority rights)
  if (!isAuthority && (hasOriginal || (!obs?.is_demo && !hasThumbnail))) {
    return (
      <div className="report-img-placeholder not-authority">
        <Lock size={18} />
        <span className="placeholder-text">Photo réservée autorité</span>
      </div>
    );
  }

  // State 5: No photo uploaded (or demo data)
  return (
    <div className="report-img-placeholder">
      <CameraOff size={18} />
      <span className="placeholder-text">Aucune photo enregistrée</span>
    </div>
  );
}

export default function App() {
  const [observations, setObservations] = useState([]);
  const [serverClusters, setServerClusters] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lang, setLang] = useState('fr');
  const [dataVersion, setDataVersion] = useState(0);

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
  const [period, setPeriod] = useState('all');

  // Selected Cluster & Side Panel
  const [selectedCluster, setSelectedCluster] = useState(null);
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(false);
  const [clusterMediaMap, setClusterMediaMap] = useState({});

  // Lightbox Image
  const [lightboxImage, setLightboxImage] = useState(null); // { url, title, badge }

  // Status Change Confirmation Modal
  const [statusConfirmModal, setStatusConfirmModal] = useState(null); // { obsId, newStatus, currentStatus }
  const [statusUpdating, setStatusUpdating] = useState(false);

  // Honest Metrics Panel Modal
  const [showMetricsPanel, setShowMetricsPanel] = useState(false);

  // RHI Tooltip
  const [showRhiTooltip, setShowRhiTooltip] = useState(false);

  // Active Sidebar View Tab ('clusters' | 'rejected')
  const [activeSidebarTab, setActiveSidebarTab] = useState('clusters');

  // Reject Confirmation Modals
  const [rejectReportModal, setRejectReportModal] = useState(null); // observation to reject
  const [rejectClusterModal, setRejectClusterModal] = useState(null); // cluster to reject

  // Undo Toast state
  const [undoState, setUndoState] = useState(null); // { message, previousStatuses }
  const undoTimerRef = useRef(null);

  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersLayerRef = useRef(null);
  const focusMarkerRef = useRef(null);
  const [mapFocus, setMapFocus] = useState(null);
  const [mapReady, setMapReady] = useState(false);
  const [ragSelection, setRagSelection] = useState(null);
  const [ragRequest, setRagRequest] = useState(null);
  const askObservationRef = useRef(() => {});
  const langRef = useRef(lang);
  langRef.current = lang;
  askObservationRef.current = (observation) => {
    const safe = observationForRecommendation(observation);
    setRagSelection(safe);
    setRagRequest({
      id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      question: buildTechnicalQuestion(safe, langRef.current),
    });
    window.requestAnimationFrame(() => {
      document.getElementById('recommandation-technique')?.scrollIntoView({
        behavior: 'smooth',
        block: 'start',
      });
    });
  };

  const t = I18N[lang] || I18N.fr;

  // ── 0. Check Auth Session on Mount & Listen to Changes ──────────────────────
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

    // Listen to token refresh, login, logout
    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (event, session) => {
      console.log('[Auth] State changed:', event, session?.user?.email);
      const user = session?.user || null;
      setCurrentUser(user);
      if (user) {
        const authOk = await checkIsAuthority();
        setIsAuthorityUser(authOk);
      } else {
        setIsAuthorityUser(false);
      }
      // Trigger full observation refetch with the new token/context
      setDataVersion((v) => v + 1);
    });

    return () => {
      subscription?.unsubscribe();
    };
  }, []);

  // ── 1. Fetch Observations & Server Clusters from Supabase ────────────────────
  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [obsData, clusterData] = await Promise.all([
        fetchObservations(),
        fetchServerClusters(20, 1),
      ]);
      setObservations(obsData || []);
      setServerClusters(clusterData || []);
    } catch (err) {
      setError(err.message || 'Error fetching data from Supabase');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData, dataVersion]);

  // ── 1b. Refetch Media for Open Cluster when Cluster or Auth Changes ────────
  useEffect(() => {
    let active = true;
    if (!selectedCluster || !selectedCluster.members || selectedCluster.members.length === 0) {
      setClusterMediaMap({});
      return;
    }

    const obsIds = selectedCluster.members.map((m) => m.id);
    fetchMediaFilesForObservations(obsIds)
      .then((res) => {
        if (active) {
          setClusterMediaMap(res);
        }
      })
      .catch((err) => {
        console.warn('[ClusterMedia] error:', err);
      });

    return () => {
      active = false;
    };
  }, [selectedCluster?.id, isAuthorityUser, dataVersion]);

  // ── 2. Partition Observations: Active vs Rejected & Excluded Counts ────────
  const activeObservations = useMemo(() => {
    return observations.filter((o) => o.status !== 'rejected');
  }, [observations]);

  const rejectedObservations = useMemo(() => {
    return observations.filter((o) => o.status === 'rejected');
  }, [observations]);

  // Count of observations excluded from the map & clusters because accuracy > 25m
  const accuracyExcludedCount = useMemo(() => {
    return observations.filter(
      (o) => typeof o.accuracy_meters === 'number' && o.accuracy_meters > 25
    ).length;
  }, [observations]);

  // Server Clusters (public.get_clusters() is the single source of truth)
  // Each cluster's member reports are matched by location & radius (<= 30m covers 20m DBSCAN eps)
  // and must satisfy the same filters (accuracy <= 25m, status <> 'rejected')
  const clusters = useMemo(() => {
    const validObs = observations.filter(
      (o) => o.status !== 'rejected' && (o.accuracy_meters == null || o.accuracy_meters <= 25)
    );

    return serverClusters.map((sc) => {
      // Find reports of this cluster by distance to centroid (<= 30m)
      const members = validObs.filter(
        (o) =>
          haversineDistanceMeters(
            sc.centroid_lat,
            sc.centroid_lng,
            o.latitude,
            o.longitude
          ) <= 30
      );

      // Dominant status hierarchy from status_counts or members:
      // status_counts has { unconfirmed, confirmed, in_progress, repaired, rejected }
      const scCounts = sc.status_counts || {};
      const count = Number(sc.report_count);
      let dominantStatus = 'unconfirmed';
      const repairedCount = Number(scCounts.repaired || 0);
      const confirmedCount = Number(scCounts.confirmed || 0);
      const progressCount = Number(scCounts.in_progress || 0);
      if (repairedCount > 0 && repairedCount === count) {
        dominantStatus = 'repaired';
      } else if (progressCount > 0 && confirmedCount === 0) {
        dominantStatus = 'in_progress';
      } else if (confirmedCount > 0 || progressCount > 0) {
        dominantStatus = 'confirmed';
      } else if (repairedCount > 0) {
        dominantStatus = 'repaired';
      }

      const score = Number(sc.max_priority_score || 0);
      const priorityLabel =
        score >= PRIORITY_CONFIG.highThreshold
          ? 'HIGH'
          : score < PRIORITY_CONFIG.lowThreshold
          ? 'LOW'
          : 'MEDIUM';

      return {
        id: sc.cluster_id,
        cluster_id: sc.cluster_id,
        latitude: sc.centroid_lat,
        longitude: sc.centroid_lng,
        count,
        dominantClass: sc.worst_class || null,
        maxPriorityScore: score,
        priorityLabel,
        oldestDate: sc.first_seen,
        newestDate: sc.last_seen,
        status: dominantStatus,
        statusCounts: scCounts,
        members,
        realCount: Number(sc.real_count || 0),
        demoCount: Number(sc.demo_count || 0),
      };
    });
  }, [serverClusters, observations]);

  const hasDemoData = useMemo(() => {
    return (
      serverClusters.some((c) => Number(c.demo_count || 0) > 0) ||
      activeObservations.some((o) => o.is_demo)
    );
  }, [serverClusters, activeObservations]);

  // ── 3. Filtered Clusters for Display ───────────────────────────────────────
  const filteredClusters = useMemo(() => {
    return clusters.filter((c) => {
      if (classFilter !== 'all') {
        const memberClass = c.members.some((member) => observationClass(member) === classFilter);
        if (c.dominantClass !== classFilter && !memberClass) return false;
      }
      if (priorityFilter !== 'all') {
        const memberPriority = c.members.some((member) => observationPriority(member) === priorityFilter);
        if (c.priorityLabel !== priorityFilter && !memberPriority) return false;
      }
      if (statusFilter !== 'all') {
        const counted = Number(c.statusCounts?.[statusFilter] || 0) > 0;
        const memberStatus = c.members.some((member) => (member.status || 'unconfirmed') === statusFilter);
        if (c.status !== statusFilter && !counted && !memberStatus) return false;
      }
      if (period !== 'all') {
        const memberInPeriod = c.members.some((member) => {
          const timestamp = observationTime(member);
          return timestamp != null && isWithinPeriod(timestamp, period);
        });
        const clusterInPeriod = c.members.length === 0 && isWithinPeriod(c.newestDate, period);
        if (!memberInPeriod && !clusterInPeriod) return false;
      }
      return true;
    });
  }, [clusters, classFilter, priorityFilter, statusFilter, period]);

  const ministry = useMemo(() => {
    const scoped = observations.filter((obs) => matchesObservationFilters(obs, {
      classFilter,
      priorityFilter,
      statusFilter,
    }));
    return buildMinistryOverview(scoped, { period });
  }, [observations, classFilter, priorityFilter, statusFilter, period]);

  function openObservation(observationId) {
    const observation = observations.find((item) => item.id === observationId);
    const cluster = clusters.find((item) =>
      item.members.some((member) => member.id === observationId)
    );
    if (cluster) {
      setActiveSidebarTab('clusters');
      setSelectedCluster(cluster);
      setIsSidebarCollapsed(false);
    }
    const latitude = Number(cluster?.latitude ?? observation?.latitude);
    const longitude = Number(cluster?.longitude ?? observation?.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return;
    if (latitude === 0 && longitude === 0) return;
    setMapFocus({ id: observationId, lat: latitude, lng: longitude });
    document.getElementById('ministry-map')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

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

      L.tileLayer(MAP_CONFIG.tileUrl, {
        attribution: MAP_CONFIG.tileAttribution,
        maxZoom: MAP_CONFIG.maxZoom,
      }).addTo(map);

      const markersGroup = L.layerGroup().addTo(map);
      markersLayerRef.current = markersGroup;
      mapInstanceRef.current = map;
      setMapReady(true);
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

        const popup = L.popup({ maxWidth: 320, minWidth: 220, className: 'rag-leaflet-popup' });
        popup.setContent('<div class="rag-map-popup-root"></div>');
        marker.bindPopup(popup);
        marker.on('popupopen', () => {
          const root = popup.getElement()?.querySelector('.rag-map-popup-root');
          if (!root) return;
          const safe = observationForRecommendation(cluster);
          const known = safe.classCode && DAMAGE_CLASSES[safe.classCode];
          const isFr = langRef.current !== 'en';
          root.innerHTML = buildMapRagPopupHtml({
            classCode: safe.classCode || '—',
            classLabel: known ? (isFr ? known.fr : known.en) : (isFr ? 'Non classé' : 'Unclassified'),
            priorityLabel: safe.priority || '—',
            statusLabel: safe.status && STATUS_LABELS[safe.status]
              ? (isFr ? STATUS_LABELS[safe.status].fr : STATUS_LABELS[safe.status].en)
              : '—',
            buttonLabel: isFr ? 'Recommandation technique' : 'Technical recommendation',
          });
          root.querySelector('[data-rag-ask]')?.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            askObservationRef.current(safe);
          });
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

  useEffect(() => {
    const map = mapInstanceRef.current;
    if (focusMarkerRef.current) {
      focusMarkerRef.current.remove();
      focusMarkerRef.current = null;
    }
    if (!map || !mapFocus || !mapReady) return undefined;
    map.invalidateSize();
    const marker = L.circleMarker([mapFocus.lat, mapFocus.lng], {
      radius: 16,
      color: '#0b1f33',
      weight: 3,
      fillColor: '#1d4ed8',
      fillOpacity: 0.18,
      interactive: false,
    }).addTo(map);
    focusMarkerRef.current = marker;
    map.flyTo([mapFocus.lat, mapFocus.lng], Math.max(map.getZoom(), 15), { duration: 0.45 });
    return () => {
      marker.remove();
      if (focusMarkerRef.current === marker) focusMarkerRef.current = null;
    };
  }, [mapFocus, mapReady]);

  // Keep selectedCluster in sync with updated observations; close panel if cluster becomes empty
  useEffect(() => {
    if (!selectedCluster) return;
    const fresh = clusters.find((c) => c.id === selectedCluster.id);
    if (fresh && fresh.members && fresh.members.length > 0) {
      setSelectedCluster(fresh);
    } else {
      setSelectedCluster(null);
    }
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
      setDataVersion((v) => v + 1);
    } catch (err) {
      alert(`Erreur de mise à jour: ${err.message}`);
    } finally {
      setStatusUpdating(false);
    }
  }

  // ── 6b. Reject Report Workflow (single report soft delete) ──────────────────
  function promptRejectReport(obs) {
    if (!isAuthorityUser) {
      setShowLoginModal(true);
      return;
    }
    setRejectReportModal(obs);
  }

  async function executeRejectReport() {
    if (!rejectReportModal) return;
    const obs = rejectReportModal;
    const prevStatus = obs.status;
    setRejectReportModal(null);

    try {
      await updateObservationStatus(obs.id, 'rejected');

      // Update local state immediately
      setObservations((prev) =>
        prev.map((o) => (o.id === obs.id ? { ...o, status: 'rejected' } : o))
      );

      // Trigger 8-second Undo toast
      showUndoToast(
        `Signalement #${obs.id.slice(0, 8)} rejeté (pas d'anomalie)`,
        [{ id: obs.id, previousStatus: prevStatus }]
      );

      setDataVersion((v) => v + 1);
    } catch (err) {
      alert(`Erreur lors du rejet du signalement : ${err.message}`);
    }
  }

  // ── 6c. Reject Entire Cluster Workflow (batch soft delete with id=in.(...)) ─
  function promptRejectCluster(cluster) {
    if (!isAuthorityUser) {
      setShowLoginModal(true);
      return;
    }
    setRejectClusterModal(cluster);
  }

  async function executeRejectCluster() {
    if (!rejectClusterModal) return;
    const cluster = rejectClusterModal;
    const members = cluster.members || [];
    const ids = members.map((m) => m.id);
    const previousStatuses = members.map((m) => ({ id: m.id, previousStatus: m.status }));
    setRejectClusterModal(null);

    try {
      await updateMultipleObservationsStatus(ids, 'rejected');

      // Update local state immediately
      const idSet = new Set(ids);
      setObservations((prev) =>
        prev.map((o) => (idSet.has(o.id) ? { ...o, status: 'rejected' } : o))
      );

      // Close the open cluster panel
      setSelectedCluster(null);

      // Trigger 8-second Undo toast
      showUndoToast(
        `Cluster rejeté (${ids.length} signalements)`,
        previousStatuses
      );

      setDataVersion((v) => v + 1);
    } catch (err) {
      alert(`Erreur lors du rejet du cluster : ${err.message}`);
    }
  }

  // ── 6d. Undo Reject Handler (restores previous status) ───────────────────────
  function showUndoToast(message, previousStatuses) {
    if (undoTimerRef.current) clearTimeout(undoTimerRef.current);
    setUndoState({ message, previousStatuses });
    undoTimerRef.current = setTimeout(() => {
      setUndoState(null);
    }, 8000);
  }

  async function handleUndoReject() {
    if (!undoState || !undoState.previousStatuses) return;
    if (undoTimerRef.current) clearTimeout(undoTimerRef.current);
    const items = undoState.previousStatuses;
    setUndoState(null);

    try {
      const groups = {};
      items.forEach(({ id, previousStatus }) => {
        const st = previousStatus || 'unconfirmed';
        if (!groups[st]) groups[st] = [];
        groups[st].push(id);
      });

      for (const [status, ids] of Object.entries(groups)) {
        if (ids.length === 1) {
          await updateObservationStatus(ids[0], status);
        } else {
          await updateMultipleObservationsStatus(ids, status);
        }
      }

      setDataVersion((v) => v + 1);
    } catch (err) {
      alert(`Erreur lors de l'annulation du rejet : ${err.message}`);
    }
  }

  // ── 6e. Restore Single Report from 'Rejetés' view ───────────────────────────
  async function handleRestoreReport(obsId) {
    if (!isAuthorityUser) return;
    try {
      await updateObservationStatus(obsId, 'unconfirmed');
      setObservations((prev) =>
        prev.map((o) => (o.id === obsId ? { ...o, status: 'unconfirmed' } : o))
      );
      setDataVersion((v) => v + 1);
    } catch (err) {
      alert(`Erreur lors de la restauration : ${err.message}`);
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
      `"${c.dominantClass || ''}"`,
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
      setDataVersion((v) => v + 1);
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
      setDataVersion((v) => v + 1);
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
            <p className="topbar-subtitle">{t.subtitle}</p>
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

      <MinistryOverview
        overview={ministry}
        lang={lang}
        period={period}
        onPeriodChange={setPeriod}
        loading={loading && observations.length === 0}
        error={error}
        onRetry={loadData}
        onOpenObservation={openObservation}
        onAskObservation={(item) => askObservationRef.current(item)}
      />

      <TechnicalRecommendation
        lang={lang}
        selection={ragSelection}
        request={ragRequest}
      />

      <div className="ministry-map-heading">
        <h2>{lang === 'fr' ? 'Intelligence géographique' : 'Geographic intelligence'}</h2>
        <p>
          {lang === 'fr'
            ? 'Agrégats serveur à 20 m. La couleur suit le score de priorité le plus élevé, la taille le nombre de signalements.'
            : 'Server clusters at 20 m. Colour follows the highest priority score. Size is the number of reports.'}
        </p>
      </div>

      {/* ── Main Layout: Map + Side Panel ───────────────────────────────────── */}
      <div id="ministry-map" className={`main-layout ${isSidebarCollapsed ? 'sidebar-collapsed' : ''}`}>
        {/* Left Map View */}
        <div className="map-wrapper">
          <div ref={mapRef} style={{ width: '100%', height: '100%' }} />

          {/* Expand Sidebar Button (when collapsed) */}
          {isSidebarCollapsed && (
            <button
              className="sidebar-expand-btn"
              onClick={() => setIsSidebarCollapsed(false)}
              title="Ouvrir le panneau d'inspection"
            >
              <ChevronLeft size={16} />
              <span>{selectedCluster ? 'Détails cluster' : 'File prioritaire'}</span>
            </button>
          )}

          {/* Quick Filters Overlay */}
          <div className="map-filter-overlay">
            <select
              className="select-input"
              value={classFilter}
              onChange={(e) => setClassFilter(e.target.value)}
              aria-label={lang === 'fr' ? 'Classe de dégradation' : 'Damage class'}
            >
              <option value="all">{lang === 'fr' ? 'Classe: Tous' : 'Class: All'}</option>
              {['D40', 'D20', 'D10', 'D00'].map((code) => (
                <option key={code} value={code}>
                  {code} ({lang === 'fr' ? DAMAGE_CLASSES[code].fr : DAMAGE_CLASSES[code].en})
                </option>
              ))}
            </select>

            <select
              className="select-input"
              value={priorityFilter}
              onChange={(e) => setPriorityFilter(e.target.value)}
              aria-label={lang === 'fr' ? 'Priorité' : 'Priority'}
            >
              <option value="all">{lang === 'fr' ? 'Priorité: Tous' : 'Priority: All'}</option>
              <option value="HIGH">HIGH</option>
              <option value="MEDIUM">MEDIUM</option>
              <option value="LOW">LOW</option>
            </select>

            <select
              className="select-input"
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              aria-label={lang === 'fr' ? 'Statut' : 'Status'}
            >
              <option value="all">{lang === 'fr' ? 'Statut: Tous' : 'Status: All'}</option>
              {['unconfirmed', 'confirmed', 'in_progress', 'repaired'].map((key) => (
                <option key={key} value={key}>
                  {lang === 'fr' ? STATUS_LABELS[key].fr : STATUS_LABELS[key].en}
                </option>
              ))}
            </select>
          </div>

          {/* Map Legend & GPS Accuracy Note */}
          <div className="map-legend">
            <span style={{ fontSize: '0.72rem', fontWeight: 800, color: 'var(--text-muted)' }}>
              {lang === 'fr'
                ? 'LÉGENDE (COULEUR = SCORE DE PRIORITÉ • TAILLE = SIGNALEMENTS)'
                : 'LEGEND (COLOUR = PRIORITY SCORE • SIZE = REPORTS)'}
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
            <div style={{ marginTop: '8px', paddingTop: '6px', borderTop: '1px solid var(--border-subtle)', fontSize: '0.70rem', color: 'var(--text-dim)', lineHeight: 1.3 }}>
              <span>Positions avec précision &gt; 25 m non affichées ({accuracyExcludedCount} signalements exclus)</span>
            </div>
          </div>
        </div>

        {/* Right Side Panel: Cluster Details & Report List */}
        <aside className="sidebar">
          {activeSidebarTab === 'rejected' && isAuthorityUser ? (
            <div className="rejected-view">
              <div className="rejected-header">
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span style={{ width: '8px', height: '8px', borderRadius: '50%', background: '#EF4444' }} />
                    <h2 style={{ fontSize: '1rem', fontWeight: 800 }}>Signalements rejetés</h2>
                  </div>
                  <p style={{ fontSize: '0.74rem', color: 'var(--text-muted)', marginTop: '4px' }}>
                    {rejectedObservations.length} signalement{rejectedObservations.length > 1 ? 's' : ''} exclu{rejectedObservations.length > 1 ? 's' : ''} de la carte publique
                  </p>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <button
                    className="icon-btn"
                    onClick={() => setIsSidebarCollapsed(true)}
                    title="Masquer le panneau"
                  >
                    <ChevronRight size={18} />
                  </button>
                  <button
                    className="icon-btn"
                    onClick={() => setActiveSidebarTab('clusters')}
                    title="Retour aux clusters"
                  >
                    <X size={16} />
                  </button>
                </div>
              </div>

              {rejectedObservations.length === 0 ? (
                <div className="panel-empty-state" style={{ height: '240px' }}>
                  <CheckCircle2 size={32} color="var(--color-success)" style={{ opacity: 0.6 }} />
                  <h4 style={{ fontSize: '0.9rem', fontWeight: 700, marginTop: '8px' }}>
                    Aucun signalement rejeté
                  </h4>
                  <p style={{ fontSize: '0.75rem', color: 'var(--text-muted)', textAlign: 'center', maxWidth: '240px', marginTop: '4px' }}>
                    Tous les signalements enregistrés sont actifs sur le réseau.
                  </p>
                </div>
              ) : (
                <div className="report-items-list" style={{ overflowY: 'auto' }}>
                  {rejectedObservations.map((obs, idx) => {
                    const det = obs.detections?.[0];
                    const classCode = obs.anomaly_type || det?.class_code || null;

                    return (
                      <div key={obs.id} className="report-card" style={{ borderColor: 'rgba(239, 68, 68, 0.3)' }}>
                        <div style={{ display: 'flex', gap: '14px', alignItems: 'flex-start' }}>
                          <ReportImageThumbnail
                            obs={obs}
                            clusterMedia={clusterMediaMap[obs.id]}
                            isAuthority={isAuthorityUser}
                            onOpenLightbox={(url, title, badge) =>
                              setLightboxImage({ url, title, badge })
                            }
                          />

                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '6px' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                                <span style={{ fontWeight: 700, fontSize: '0.82rem', color: DAMAGE_CLASSES[classCode]?.color || '#64748b' }}>
                                  #{idx + 1} {classCode || 'Non classé'}{DAMAGE_CLASSES[classCode] ? ` (${DAMAGE_CLASSES[classCode].fr})` : ''}
                                </span>
                                {obs.is_demo ? (
                                  <span className="badge badge-demo">DEMO</span>
                                ) : (
                                  <span className="badge badge-real">RÉEL</span>
                                )}
                              </div>
                              <span className="badge" style={{ fontSize: '0.65rem', background: 'rgba(239, 68, 68, 0.15)', color: '#f87171', border: '1px solid rgba(239, 68, 68, 0.3)' }}>
                                Rejeté
                              </span>
                            </div>

                            <div style={{ display: 'flex', gap: '12px', fontSize: '0.72rem', color: 'var(--text-muted)', marginTop: '4px' }}>
                              <div>
                                <span style={{ color: 'var(--text-dim)' }}>ID: </span>
                                <span className="mono">{obs.id.slice(0, 8)}</span>
                              </div>
                              <div>
                                <span style={{ color: 'var(--text-dim)' }}>Score: </span>
                                <strong className="mono">{formatScore(obs.priority_score)}</strong>
                              </div>
                            </div>

                            <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginTop: '4px' }}>
                              {new Date(obs.created_at).toLocaleString()}
                            </div>

                            <div style={{ marginTop: '8px' }}>
                              <button
                                className="btn-status btn-restore"
                                onClick={() => handleRestoreReport(obs.id)}
                                title="Restaurer comme non confirmé"
                              >
                                <RotateCcw size={12} />
                                <span>Restaurer</span>
                              </button>
                            </div>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          ) : selectedCluster ? (
            <div className="cluster-detail-panel">
              {/* Cluster Header */}
              <div className="panel-header">
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span
                      className="class-badge"
                      style={{
                        background: DAMAGE_CLASSES[selectedCluster.dominantClass]?.color || '#64748b',
                      }}
                    >
                      {selectedCluster.dominantClass || '—'}
                    </span>
                    <h2 style={{ fontSize: '1rem', fontWeight: 800 }}>
                      {DAMAGE_CLASSES[selectedCluster.dominantClass]?.fr || 'Non classé'}
                    </h2>
                  </div>
                  <p className="mono" style={{ fontSize: '0.74rem', color: 'var(--text-dim)', marginTop: '4px' }}>
                    {selectedCluster.latitude.toFixed(6)}, {selectedCluster.longitude.toFixed(6)}
                  </p>
                  {isAuthorityUser && (
                    <button
                      className="btn-danger-subtle"
                      onClick={() => promptRejectCluster(selectedCluster)}
                      title="Rejeter tous les signalements de ce cluster (pas d'anomalie)"
                      style={{ marginTop: '8px' }}
                    >
                      <Trash2 size={13} />
                      <span>Rejeter tout le cluster</span>
                    </button>
                  )}
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <button
                    className="icon-btn"
                    onClick={() => setIsSidebarCollapsed(true)}
                    title="Masquer le panneau"
                  >
                    <ChevronRight size={18} />
                  </button>
                  <button
                    className="icon-btn"
                    onClick={() => setSelectedCluster(null)}
                    title="Fermer la sélection"
                  >
                    <X size={16} />
                  </button>
                </div>
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
                    {formatScore(selectedCluster.maxPriorityScore)} ({selectedCluster.priorityLabel})
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
                    const classCode = obs.anomaly_type || det?.class_code || null;
                    const conf = det?.confidence !== undefined ? det.confidence : null;

                    return (
                      <div key={obs.id} className="report-card">
                        <div style={{ display: 'flex', gap: '14px', alignItems: 'flex-start' }}>
                          {/* Image thumbnail (150x110px with lightbox) */}
                          <ReportImageThumbnail
                            obs={obs}
                            clusterMedia={clusterMediaMap[obs.id]}
                            isAuthority={isAuthorityUser}
                            onOpenLightbox={(url, title, badge) =>
                              setLightboxImage({ url, title, badge })
                            }
                          />

                          {/* Report metadata */}
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '6px' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                                <span style={{ fontWeight: 700, fontSize: '0.82rem', color: DAMAGE_CLASSES[classCode]?.color || '#64748b' }}>
                                  #{idx + 1} {classCode || 'Non classé'}{DAMAGE_CLASSES[classCode] ? ` (${DAMAGE_CLASSES[classCode].fr})` : ''}
                                </span>
                                {obs.is_demo ? (
                                  <span className="badge badge-demo">DEMO</span>
                                ) : (
                                  <span className="badge badge-real">RÉEL</span>
                                )}
                              </div>
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
                                <strong className="mono">{formatScore(obs.priority_score)}</strong>
                              </div>
                            </div>

                            <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginTop: '4px' }}>
                              {new Date(obs.created_at).toLocaleString()}
                            </div>

                            <button
                              type="button"
                              className="btn btn-secondary rag-inline-btn"
                              onClick={() => askObservationRef.current(obs)}
                            >
                              <BookOpen size={12} />
                              <span>Recommandation technique</span>
                            </button>

                            {/* Authority Status Workflow Actions */}
                            {isAuthorityUser && (
                              <div style={{ display: 'flex', gap: '6px', marginTop: '8px', flexWrap: 'wrap' }}>
                                {obs.status === 'unconfirmed' && (
                                  <button
                                    className="btn-status btn-confirm"
                                    onClick={() => promptStatusUpdate(obs.id, 'unconfirmed', 'confirmed')}
                                  >
                                    <CheckCircle2 size={12} />
                                    <span>Confirmer anomalie</span>
                                  </button>
                                )}
                                {(obs.status === 'confirmed' || obs.status === 'in_progress') && (
                                  <button
                                    className="btn-status btn-repair"
                                    onClick={() => promptStatusUpdate(obs.id, obs.status, 'repaired')}
                                  >
                                    <Wrench size={12} />
                                    <span>Marquer réparé</span>
                                  </button>
                                )}
                                {obs.status === 'confirmed' && (
                                  <button
                                    className="btn-status btn-confirm"
                                    onClick={() => promptStatusUpdate(obs.id, 'confirmed', 'in_progress')}
                                  >
                                    <Clock size={12} />
                                    <span>Marquer en cours</span>
                                  </button>
                                )}
                                {obs.status === 'repaired' && (
                                  <span style={{ fontSize: '0.7rem', color: 'var(--color-success)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                                    <CheckCircle2 size={12} /> Réparé & Validé
                                  </span>
                                )}
                                <button
                                  className="btn-status btn-reject"
                                  onClick={() => promptRejectReport(obs)}
                                  title="Rejeter ce signalement (pas d'anomalie)"
                                >
                                  <XCircle size={12} />
                                  <span>Rejeter (pas d'anomalie)</span>
                                </button>
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
              <div style={{ width: '100%', display: 'flex', justifyContent: 'flex-end', marginBottom: '8px' }}>
                <button
                  className="icon-btn"
                  onClick={() => setIsSidebarCollapsed(true)}
                  title="Masquer le panneau"
                >
                  <ChevronRight size={18} />
                </button>
              </div>
              <Layers size={36} style={{ opacity: 0.4, color: 'var(--color-primary)' }} />
              <h3 style={{ fontSize: '0.95rem', fontWeight: 700, marginTop: '8px' }}>
                Sélectionnez un cluster sur la carte
              </h3>
              <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', textAlign: 'center', maxWidth: '280px', lineHeight: 1.4, marginTop: '4px' }}>
                Cliquez sur n'importe quel marqueur géodésique pour afficher les signalements concordants, les clichés certifiés et le workflow de réparation.
              </p>

              {/* Cluster Ranked List in Empty State */}
              <div style={{ width: '100%', marginTop: '16px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                  <span style={{ fontSize: '0.72rem', fontWeight: 800, color: 'var(--text-dim)', textTransform: 'uppercase' }}>
                    Top clusters prioritaires ({filteredClusters.length})
                  </span>
                  {isAuthorityUser && rejectedObservations.length > 0 && (
                    <button
                      className="btn-status btn-reject"
                      style={{ fontSize: '0.68rem', padding: '2px 8px' }}
                      onClick={() => setActiveSidebarTab('rejected')}
                    >
                      <span>Rejetés ({rejectedObservations.length})</span>
                    </button>
                  )}
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', maxHeight: '340px', overflowY: 'auto' }}>
                  {filteredClusters.map((c, i) => (
                    <div
                      key={c.id}
                      className="cluster-list-row"
                      onClick={() => setSelectedCluster(c)}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <span className="mono" style={{ fontSize: '0.75rem', color: 'var(--text-dim)' }}>#{i + 1}</span>
                        <span style={{ fontWeight: 700, fontSize: '0.8rem', color: DAMAGE_CLASSES[c.dominantClass]?.color || '#64748b' }}>
                          {c.dominantClass || '—'}
                        </span>
                        <span style={{ fontSize: '0.74rem', color: 'var(--text-muted)' }}>
                          {c.count} {c.count > 1 ? 'passages' : 'passage'}
                        </span>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <strong className="mono" style={{ fontSize: '0.8rem', color: PRIORITY_PIN_COLORS[c.priorityLabel] }}>
                          {formatScore(c.maxPriorityScore)}
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

              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '14px', padding: '12px', background: 'var(--bg-primary)', borderRadius: 'var(--radius-sm)', marginBottom: '18px' }}>
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

      {/* ── Reject Single Report Modal ────────────────────────────────────── */}
      {rejectReportModal && (
        <div className="modal-overlay" onClick={() => setRejectReportModal(null)}>
          <div className="modal-card" style={{ maxWidth: '440px' }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: '24px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <AlertTriangle size={20} color="#EF4444" />
                  <h3 style={{ fontSize: '1.05rem', fontWeight: 800, color: 'var(--text-main)' }}>
                    Rejeter le signalement
                  </h3>
                </div>
                <X size={18} style={{ cursor: 'pointer' }} onClick={() => setRejectReportModal(null)} />
              </div>

              <p style={{ fontSize: '0.84rem', color: 'var(--text-muted)', lineHeight: 1.5, marginBottom: '16px' }}>
                Ce signalement sera qualifié comme « sans anomalie » (soft-delete). Il sera retiré de la carte publique, des clusters géodésiques et des compteurs de voirie.
              </p>

              <div style={{ padding: '12px', background: 'rgba(255,255,255,0.03)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-sm)', marginBottom: '20px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontWeight: 700, fontSize: '0.82rem' }}>
                    #{rejectReportModal.id.slice(0, 8)} • {rejectReportModal.anomaly_type || 'Anomalie'}
                  </span>
                  {rejectReportModal.is_demo ? (
                    <span className="badge badge-demo">DEMO</span>
                  ) : (
                    <span className="badge badge-real">RÉEL</span>
                  )}
                </div>
                <div style={{ fontSize: '0.75rem', color: 'var(--text-dim)', marginTop: '4px' }}>
                  Score calculé : {formatScore(rejectReportModal.priority_score)} • Statut actuel : {rejectReportModal.status}
                </div>
              </div>

              <div style={{ display: 'flex', gap: '10px', justifyContent: 'flex-end' }}>
                <button className="btn btn-secondary" onClick={() => setRejectReportModal(null)}>
                  Annuler
                </button>
                <button
                  className="btn btn-primary"
                  style={{ background: '#EF4444', borderColor: '#EF4444' }}
                  onClick={executeRejectReport}
                >
                  Confirmer le rejet
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Reject Entire Cluster Modal ────────────────────────────────────── */}
      {rejectClusterModal && (() => {
        const members = rejectClusterModal.members || [];
        const realCount = members.filter((m) => !m.is_demo).length;
        const demoCount = members.filter((m) => m.is_demo).length;

        return (
          <div className="modal-overlay" onClick={() => setRejectClusterModal(null)}>
            <div className="modal-card" style={{ maxWidth: '460px' }} onClick={(e) => e.stopPropagation()}>
              <div style={{ padding: '24px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <Trash2 size={20} color="#EF4444" />
                    <h3 style={{ fontSize: '1.05rem', fontWeight: 800, color: 'var(--text-main)' }}>
                      Rejeter tout le cluster
                    </h3>
                  </div>
                  <X size={18} style={{ cursor: 'pointer' }} onClick={() => setRejectClusterModal(null)} />
                </div>

                <p style={{ fontSize: '0.84rem', color: 'var(--text-muted)', lineHeight: 1.5, marginBottom: '16px' }}>
                  Cette action appliquera le statut <code>rejected</code> à l'ensemble des signalements du cluster.
                </p>

                <div style={{ padding: '12px', background: 'rgba(239, 68, 68, 0.08)', border: '1px solid rgba(239, 68, 68, 0.3)', borderRadius: 'var(--radius-sm)', marginBottom: '20px' }}>
                  <div style={{ fontWeight: 700, fontSize: '0.85rem', color: '#f87171', marginBottom: '6px' }}>
                    {members.length} signalement{members.length > 1 ? 's' : ''} au total
                  </div>
                  <div style={{ display: 'flex', gap: '12px', fontSize: '0.78rem' }}>
                    <span>
                      Réels : <strong style={{ color: '#10B981' }}>{realCount}</strong>
                    </span>
                    <span>
                      Démo : <strong style={{ color: '#F59E0B' }}>{demoCount}</strong>
                    </span>
                  </div>
                  <div style={{ fontSize: '0.72rem', color: 'var(--text-dim)', marginTop: '6px' }}>
                    Coordonnées : {rejectClusterModal.latitude.toFixed(6)}, {rejectClusterModal.longitude.toFixed(6)}
                  </div>
                </div>

                <div style={{ display: 'flex', gap: '10px', justifyContent: 'flex-end' }}>
                  <button className="btn btn-secondary" onClick={() => setRejectClusterModal(null)}>
                    Annuler
                  </button>
                  <button
                    className="btn btn-primary"
                    style={{ background: '#EF4444', borderColor: '#EF4444' }}
                    onClick={executeRejectCluster}
                  >
                    Rejeter tout le cluster
                  </button>
                </div>
              </div>
            </div>
          </div>
        );
      })()}

      {/* ── Undo Reject Toast (8s notification) ────────────────────────────── */}
      {undoState && (
        <div className="toast-undo">
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Info size={16} color="#3B82F6" />
            <span>{undoState.message}</span>
          </div>
          <button className="btn-undo" onClick={handleUndoReject}>
            <RotateCcw size={13} />
            <span>Annuler</span>
          </button>
        </div>
      )}

      {/* ── Image Lightbox Modal ────────────────────────────────────────── */}
      <ImageLightbox
        image={lightboxImage}
        onClose={() => setLightboxImage(null)}
      />
    </div>
  );
}
