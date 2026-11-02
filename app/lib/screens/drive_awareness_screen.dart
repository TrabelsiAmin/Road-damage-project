import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../models/driving_position.dart';
import '../models/upcoming_anomaly.dart';
import '../services/drive_alert_service.dart';
import '../services/drive_anomaly_repository.dart';
import '../services/driving_location_service.dart';
import '../services/route_matching_service.dart';
import '../services/upcoming_anomaly_service.dart';

/// Full-screen vehicle-centered Drive Awareness interface.
/// Provides passive, glanceable road hazard alerts without continuous model inference or path uploading.
class DriveAwarenessScreen extends StatefulWidget {
  const DriveAwarenessScreen({
    super.key,
    this.locationService,
    this.anomalyRepository,
    this.upcomingService,
    this.alertService,
    this.skipDisclaimerForTesting = false,
    this.skipPermissionCheckForTesting = false,
  });

  final DrivingLocationService? locationService;
  final DriveAnomalyRepository? anomalyRepository;
  final UpcomingAnomalyService? upcomingService;
  final DriveAlertService? alertService;
  final bool skipDisclaimerForTesting;
  final bool skipPermissionCheckForTesting;

  @override
  State<DriveAwarenessScreen> createState() => _DriveAwarenessScreenState();
}

class _DriveAwarenessScreenState extends State<DriveAwarenessScreen> with WidgetsBindingObserver {
  late final DrivingLocationService _locationService;
  late final DriveAnomalyRepository _anomalyRepository;
  late final UpcomingAnomalyService _upcomingService;
  late final DriveAlertService _alertService;

  final MapController _mapController = MapController();
  StreamSubscription<DrivingPosition>? _positionSubscription;

  DrivingPosition? _currentPosition;
  UpcomingAnomalyResult _upcomingResult = UpcomingAnomalyResult.none;
  List<UpcomingAnomaly> _nearbyAnomalies = [];

  bool _isHeadingUp = false;
  bool _isMuted = false;
  bool _isLoading = true;
  bool _autoRecenter = true;
  bool _mapReady = false;
  bool _disclaimerAccepted = false;
  DateTime? _lastDataFetchTime;
  String? _statusBannerText;

  static const String _disclaimerKey = 'drive_awareness_disclaimer_accepted';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _locationService = widget.locationService ?? DrivingLocationService();
    _anomalyRepository = widget.anomalyRepository ?? DefaultDriveAnomalyRepository();
    _upcomingService = widget.upcomingService ??
        UpcomingAnomalyService(routeMatcher: const ForwardConeRouteMatcher());
    _alertService = widget.alertService ?? DriveAlertService();

    _isMuted = !_alertService.soundEnabled;

    if (widget.skipDisclaimerForTesting) {
      _disclaimerAccepted = true;
      _startDriveSession();
    } else {
      _checkDisclaimerAndStart();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Release GPS stream when app is in background or closed
      _locationService.stopTracking();
    } else if (state == AppLifecycleState.resumed && _disclaimerAccepted) {
      _locationService.startTracking();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    if (widget.locationService == null) {
      _locationService.dispose();
    }
    if (widget.anomalyRepository == null) {
      _anomalyRepository.dispose();
    }
    super.dispose();
  }

  Future<void> _checkDisclaimerAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(_disclaimerKey) ?? false;

    if (!accepted && mounted) {
      final agreed = await _showSafetyDisclaimerDialog();
      if (agreed == true) {
        await prefs.setBool(_disclaimerKey, true);
        if (mounted) {
          setState(() => _disclaimerAccepted = true);
          _startDriveSession();
        }
      } else {
        if (mounted) Navigator.of(context).pop();
      }
    } else {
      if (mounted) {
        setState(() => _disclaimerAccepted = true);
        _startDriveSession();
      }
    }
  }

  Future<bool?> _showSafetyDisclaimerDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyMid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderDark, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: AppColors.tealGlow, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Safety First',
                style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Drive Awareness provides passive, informational road-hazard warnings ahead of your vehicle.\n',
              style: TextStyle(color: AppColors.textOnDark, fontSize: 14, height: 1.4),
            ),
            Text(
              '• Never interact with this screen while driving.\n'
              '• Informational warnings do not replace driver vigilance or traffic signs.\n'
              '• Always keep your eyes on the road and drive safely.',
              style: TextStyle(color: AppColors.textSubtleOnDark, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSubtleOnDark)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('I Agree & Understand'),
          ),
        ],
      ),
    );
  }

  Future<void> _startDriveSession() async {
    if (!widget.skipPermissionCheckForTesting) {
      final hasPermission = await _locationService.checkAndRequestPermissions();
      if (!hasPermission) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusBannerText = 'Location permission is required for Drive Awareness.';
          });
        }
        return;
      }
    }

    _positionSubscription = _locationService.positionStream.listen(
      _handlePositionUpdate,
      onError: (err) {
        debugPrint('[DriveAwarenessScreen] Location error: $err');
      },
    );

    await _locationService.startTracking();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePositionUpdate(DrivingPosition pos) async {
    if (!mounted) return;

    setState(() {
      _currentPosition = pos;
    });

    // Animate map camera
    if (_autoRecenter && _mapReady) {
      try {
        final targetCenter = LatLng(pos.latitude, pos.longitude);
        final zoom = _mapController.camera.zoom > 10.0 ? _mapController.camera.zoom : 16.5;

        if (_isHeadingUp && pos.headingDegrees != null) {
          _mapController.moveAndRotate(targetCenter, zoom, -pos.headingDegrees!);
        } else {
          _mapController.moveAndRotate(targetCenter, zoom, 0.0);
        }
      } catch (_) {}
    }

    // Refresh anomalies from repository (with spatial/temporal debouncing)
    try {
      final anomalies = await _anomalyRepository.getNearbyAnomalies(
        latitude: pos.latitude,
        longitude: pos.longitude,
        radiusMeters: 1500.0,
      );

      if (mounted) {
        setState(() {
          _nearbyAnomalies = anomalies;
          _lastDataFetchTime = DateTime.now();
        });
      }

      // Evaluate upcoming anomaly
      final eval = _upcomingService.evaluateUpcomingAnomaly(
        position: pos,
        candidates: anomalies,
      );

      if (mounted) {
        setState(() {
          _upcomingResult = eval;
        });
      }

      // Trigger non-intrusive alert if necessary
      await _alertService.processAlert(eval);
    } catch (e) {
      debugPrint('[DriveAwarenessScreen] Error updating anomalies: $e');
    }
  }

  void _recenterMap() {
    if (_currentPosition == null || !_mapReady) return;
    setState(() => _autoRecenter = true);
    final target = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    try {
      if (_isHeadingUp && _currentPosition!.headingDegrees != null) {
        _mapController.moveAndRotate(target, 16.5, -_currentPosition!.headingDegrees!);
      } else {
        _mapController.moveAndRotate(target, 16.5, 0.0);
      }
    } catch (_) {}
  }

  void _toggleHeadingMode() {
    setState(() {
      _isHeadingUp = !_isHeadingUp;
    });
    if (_currentPosition != null && _mapReady) {
      try {
        final rot = (_isHeadingUp && _currentPosition!.headingDegrees != null)
            ? -_currentPosition!.headingDegrees!
            : 0.0;
        _mapController.rotate(rot);
      } catch (_) {}
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _alertService.soundEnabled = !_isMuted;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Stack(
        children: [
          // 1. Full-screen Map
          _buildMap(),

          // 2. Top HUD Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopHud(),
          ),

          // 3. Floating Recenter & Orientation controls
          Positioned(
            right: 16,
            bottom: 230,
            child: _buildMapControls(),
          ),

          // 4. Large Passive Bottom Card
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _buildBottomCard(),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: AppColors.navy.withValues(alpha: 0.85),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.tealGlow),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final initialCenter = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(36.8065, 10.1815);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 16.5,
        onMapReady: () {
          _mapReady = true;
        },
        onPositionChanged: (pos, hasGesture) {
          if (hasGesture && _autoRecenter) {
            setState(() => _autoRecenter = false);
          }
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.tariqmap.app',
        ),
        // Anomaly markers
        MarkerLayer(
          markers: _buildAnomalyMarkers(),
        ),
        // Vehicle marker
        if (_currentPosition != null)
          MarkerLayer(
            markers: [_buildVehicleMarker()],
          ),
      ],
    );
  }

  List<Marker> _buildAnomalyMarkers() {
    final markers = <Marker>[];
    final selectedId = _upcomingResult.anomaly?.observationId;

    for (final a in _nearbyAnomalies) {
      final isSelected = a.observationId == selectedId;
      final classColor = AppColors.forClassCode(a.anomalyType);

      markers.add(
        Marker(
          point: LatLng(a.latitude, a.longitude),
          width: isSelected ? 48 : 32,
          height: isSelected ? 48 : 32,
          child: isSelected
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: classColor.withValues(alpha: 0.3),
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: classColor,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          a.anomalyType,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: classColor.withValues(alpha: 0.9),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      a.anomalyType,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
        ),
      );
    }
    return markers;
  }

  Marker _buildVehicleMarker() {
    final pos = _currentPosition!;
    final heading = pos.headingDegrees ?? 0.0;
    // In Heading-Up mode, the map is rotated, so the marker arrow points straight up.
    // In North-Up mode, the marker arrow rotates by the heading angle.
    final markerRotation = _isHeadingUp ? 0.0 : heading;

    return Marker(
      point: LatLng(pos.latitude, pos.longitude),
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // GPS Accuracy Halo
          if (pos.accuracyMeters > 20)
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: 0.2),
              ),
            ),
          // Directional vehicle arrow
          Transform.rotate(
            angle: markerRotation * (math.pi / 180.0),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.tealGlow,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: const Icon(
                Icons.navigation_rounded,
                color: AppColors.navy,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHud() {
    final mediaQuery = MediaQuery.of(context);
    final isGpsAccurate = _currentPosition?.isAccurate() ?? false;
    final gpsAccuracy = _currentPosition?.accuracyMeters;

    return Container(
      padding: EdgeInsets.only(
        top: mediaQuery.padding.top + 10,
        left: 16,
        right: 16,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.navy.withValues(alpha: 0.95),
            AppColors.navy.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Exit button
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.navyMid.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 10),

          // GPS Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.navyMid.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isGpsAccurate ? Colors.green.withValues(alpha: 0.5) : Colors.orange.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.gps_fixed_rounded,
                  size: 14,
                  color: isGpsAccurate ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  gpsAccuracy != null
                      ? (isGpsAccurate ? 'GPS Good' : 'GPS ±${gpsAccuracy.toStringAsFixed(0)}m')
                      : 'Acquiring GPS...',
                  style: TextStyle(
                    color: isGpsAccurate ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          if (_lastDataFetchTime != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.navyLight.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Live',
                style: TextStyle(color: AppColors.tealGlow, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],

          const Spacer(),

          // Sound Toggle
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _isMuted ? Colors.white54 : AppColors.tealGlow,
            ),
            onPressed: _toggleMute,
            tooltip: _isMuted ? 'Unmute alerts' : 'Mute alerts',
          ),

          // Heading Mode Toggle
          IconButton(
            icon: Icon(
              _isHeadingUp ? Icons.explore_rounded : Icons.navigation_outlined,
              color: _isHeadingUp ? AppColors.tealGlow : Colors.white70,
            ),
            onPressed: _toggleHeadingMode,
            tooltip: _isHeadingUp ? 'Switch to North-Up' : 'Switch to Heading-Up',
          ),
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    return Column(
      children: [
        if (!_autoRecenter)
          FloatingActionButton.small(
            heroTag: 'recenter_btn',
            backgroundColor: AppColors.teal,
            foregroundColor: Colors.white,
            onPressed: _recenterMap,
            child: const Icon(Icons.my_location_rounded),
          ),
      ],
    );
  }

  Widget _buildBottomCard() {
    final pos = _currentPosition;

    // State 0: Explicit error / permission denied
    if (_statusBannerText != null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.navyMid.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Text(
          _statusBannerText!,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      );
    }

    // State 1: GPS Weak / Unavailable
    if (pos == null || !pos.isAccurate()) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.navyMid.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.6), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.satellite_alt_rounded, color: Colors.orangeAccent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'GPS Accuracy Degraded',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pos == null
                        ? 'Waiting for satellite fix...'
                        : 'Current accuracy ±${pos.accuracyMeters.toStringAsFixed(0)}m. Road warnings paused until signal stabilizes.',
                    style: const TextStyle(color: AppColors.textSubtleOnDark, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // State 2: Anomaly Ahead Detected!
    if (_upcomingResult.hasAnomaly && _upcomingResult.distanceMeters != null) {
      final anomaly = _upcomingResult.anomaly!;
      final distance = _upcomingResult.distanceMeters!;
      final classColor = AppColors.forClassCode(anomaly.anomalyType);
      final isVeryClose = distance <= 70.0;

      final distStr = distance < 1000
          ? '${distance.toStringAsFixed(0)} m'
          : '${(distance / 1000.0).toStringAsFixed(1)} km';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.navyMid.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isVeryClose ? classColor : AppColors.borderDark,
            width: isVeryClose ? 2.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isVeryClose ? classColor.withValues(alpha: 0.3) : Colors.black45,
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Hazard badge icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: classColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: classColor, width: 1.5),
                  ),
                  child: Icon(
                    anomaly.isPothole ? Icons.warning_rounded : Icons.report_problem_rounded,
                    color: classColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anomaly.humanReadableType.toUpperCase(),
                        style: TextStyle(
                          color: classColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        distStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                // Priority Pill
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: classColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        anomaly.priorityLabel.toUpperCase(),
                        style: TextStyle(
                          color: classColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${anomaly.reportCount} ${anomaly.reportCount == 1 ? 'report' : 'reports'}',
                      style: const TextStyle(
                        color: AppColors.textSubtleOnDark,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Subtitle / road advice
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.textSubtleOnDark, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isVeryClose
                        ? 'Caution: Hazard immediately ahead, reduce speed.'
                        : 'Approaching road defect in current driving direction.',
                    style: const TextStyle(color: AppColors.textSubtleOnDark, fontSize: 12),
                  ),
                ),
                Text(
                  '${pos.speedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // State 3: Clear Road Ahead
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.navyMid.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderDark, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Road Clear Ahead',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'No verified road defects detected in your path',
                  style: TextStyle(color: AppColors.textSubtleOnDark, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${pos.speedKmh.toStringAsFixed(0)} km/h',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
