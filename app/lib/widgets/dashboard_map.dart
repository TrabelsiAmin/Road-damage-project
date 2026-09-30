import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';

/// Home-screen map of recorded road anomalies.
///
/// The base map is always shown. A failed Supabase read keeps the map and
/// offers a retry instead of replacing the whole panel with an error.
class DashboardMap extends StatefulWidget {
  const DashboardMap({super.key});

  @override
  State<DashboardMap> createState() => _DashboardMapState();
}

class _DashboardMapState extends State<DashboardMap> {
  static const _defaultCenter = LatLng(36.8065, 10.1815);

  final MapController _mapController = MapController();
  bool _loading = true;
  final List<Marker> _markers = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAnomalies();
  }

  Future<void> _fetchAnomalies() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final client = Supabase.instance.client;
      final obsData = await client
          .from('observations')
          .select('id, priority_score, priority_label');
      final locData = await client
          .from('locations')
          .select('observation_id, latitude, longitude');
      final detData = await client
          .from('detections')
          .select('observation_id, class_code, confidence');

      final markers = _markersFrom(obsData, locData, detData);
      if (!mounted) return;
      setState(() {
        _markers
          ..clear()
          ..addAll(markers);
        _loading = false;
      });
      if (markers.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            _mapController.move(markers.first.point, 12);
          } catch (e) {
            debugPrint('[DashboardMap] camera move skipped: $e');
          }
        });
      }
    } catch (e) {
      debugPrint('[DashboardMap] load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load anomalies';
        _loading = false;
      });
    }
  }

  List<Marker> _markersFrom(
    List<dynamic> obsData,
    List<dynamic> locData,
    List<dynamic> detData,
  ) {
    final locMap = <String, ({double lat, double lng})>{};
    for (final raw in locData) {
      if (raw is! Map) continue;
      final id = raw['observation_id']?.toString();
      final lat = _asDouble(raw['latitude']);
      final lng = _asDouble(raw['longitude']);
      if (id == null || lat == null || lng == null) continue;
      if (lat == 0 && lng == 0) continue;
      locMap[id] = (lat: lat, lng: lng);
    }

    final detMap = <String, List<Map<dynamic, dynamic>>>{};
    for (final raw in detData) {
      if (raw is! Map) continue;
      final id = raw['observation_id']?.toString();
      if (id == null) continue;
      detMap.putIfAbsent(id, () => []).add(raw);
    }

    final clusters = <String, _Cluster>{};
    for (final raw in obsData) {
      if (raw is! Map) continue;
      final obsId = raw['id']?.toString();
      if (obsId == null) continue;
      final loc = locMap[obsId];
      if (loc == null) continue;

      final dets = detMap[obsId] ?? [];
      if (dets.isEmpty) continue;

      dets.sort((a, b) {
        final left = _asDouble(a['confidence']) ?? 0;
        final right = _asDouble(b['confidence']) ?? 0;
        return right.compareTo(left);
      });
      final dominantClass = dets.first['class_code']?.toString() ?? '';
      if (dominantClass.isEmpty) continue;

      final gridKey =
          '${loc.lat.toStringAsFixed(4)}_${loc.lng.toStringAsFixed(4)}';
      final existing = clusters[gridKey];
      if (existing != null) {
        existing.count++;
      } else {
        clusters[gridKey] = _Cluster(
          lat: loc.lat,
          lng: loc.lng,
          dominantClass: dominantClass,
          count: 1,
        );
      }
    }

    return clusters.values
        .map(
          (c) => Marker(
            point: LatLng(c.lat, c.lng),
            width: 40,
            height: 40,
            child: _buildMarkerWidget(c),
          ),
        )
        .toList();
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Widget _buildMarkerWidget(_Cluster cluster) {
    final color = _colorFor(cluster.dominantClass);
    final icon = _iconFor(cluster.dominantClass);
    final label = TariqMapConstants.labelFor(cluster.dominantClass);

    return Tooltip(
      message: cluster.count > 1 ? '$label · ${cluster.count}' : label,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(50),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: cluster.count > 1
              ? Text(
                  '${cluster.count}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                )
              : Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }

  Color _colorFor(String code) {
    switch (code) {
      case 'D40':
        return AppColors.d40Color;
      case 'D20':
        return AppColors.d20Color;
      case 'D10':
        return AppColors.d10Color;
      case 'D00':
        return AppColors.d00Color;
      default:
        final name = code.toLowerCase();
        if (name.contains('pothole')) return AppColors.d40Color;
        if (name.contains('crack')) return AppColors.d00Color;
        return AppColors.teal;
    }
  }

  IconData _iconFor(String code) {
    if (code == 'D40' || code.toLowerCase().contains('pothole')) {
      return Icons.radio_button_unchecked;
    }
    if (code == 'D00' ||
        code == 'D10' ||
        code == 'D20' ||
        code.toLowerCase().contains('crack')) {
      return Icons.timeline;
    }
    return Icons.warning_amber_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 12,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tariqmap.app',
              ),
              MarkerLayer(markers: _markers),
            ],
          ),
          if (_loading)
            const ColoredBox(
              color: Color(0x66F0F4F8),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.teal),
              ),
            ),
          if (_error != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _MapNotice(
                message: _error!,
                actionLabel: 'Retry',
                onAction: _fetchAnomalies,
              ),
            )
          else if (!_loading && _markers.isEmpty)
            const Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _MapNotice(message: 'No anomalies on the map yet'),
            ),
        ],
      ),
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withAlpha(235),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

class _Cluster {
  final double lat;
  final double lng;
  final String dominantClass;
  int count;

  _Cluster({
    required this.lat,
    required this.lng,
    required this.dominantClass,
    required this.count,
  });
}
