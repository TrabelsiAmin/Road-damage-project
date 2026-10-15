import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../models/observation.dart';
import '../services/observation_repository.dart';
import '../services/territorial_service.dart';
import 'annotated_image.dart';

class DashboardMap extends StatefulWidget {
  const DashboardMap({
    super.key,
    this.repository,
    this.initialObservations,
    this.initialLocations,
    this.initialDetections,
    this.initialMediaFiles,
  });

  final ObservationRepository? repository;
  final List<Map<String, dynamic>>? initialObservations;
  final List<Map<String, dynamic>>? initialLocations;
  final List<Map<String, dynamic>>? initialDetections;
  final List<Map<String, dynamic>>? initialMediaFiles;

  @override
  State<DashboardMap> createState() => _DashboardMapState();
}

class _DashboardMapState extends State<DashboardMap> {
  bool _loading = true;
  final List<Marker> _markers = [];
  String? _error;

  final MapController _mapController = MapController();
  LatLng? _userLocation;

  @override
  void initState() {
    super.initState();
    _fetchAnomalies();
    _fetchUserLocation();
  }

  Future<void> _fetchUserLocation() async {
    try {
      final locSvc = LocationService();
      final pos = await locSvc.currentPosition();
      if (mounted) {
        setState(() {
          _userLocation = LatLng(pos.latitude, pos.longitude);
        });
        try {
          _mapController.move(_userLocation!, 15.0);
        } catch (_) {}
      }
    } catch (_) {
      // Ignore if location is denied or disabled
    }
  }

  Future<void> _fetchAnomalies() async {
    try {
      List<dynamic> obsData;
      List<dynamic> locData;
      List<dynamic> detData;
      List<dynamic> mediaData;

      if (widget.initialObservations != null &&
          widget.initialLocations != null &&
          widget.initialDetections != null) {
        obsData = widget.initialObservations!;
        locData = widget.initialLocations!;
        detData = widget.initialDetections!;
        mediaData = widget.initialMediaFiles ?? [];
      } else {
        final client = Supabase.instance.client;
        obsData = await client
            .from('observations')
            .select('id, capture_id, anomaly_type, priority_score, priority_label, status, created_at, captured_at');
        locData = await client
            .from('locations')
            .select('observation_id, latitude, longitude, accuracy_meters');
        detData = await client
            .from('detections')
            .select('observation_id, class_code, confidence, box_x, box_y, box_w, box_h');
        try {
          mediaData = await client
              .from('media_files')
              .select('observation_id, bucket, storage_path, public_url, media_type')
              .eq('bucket', 'public-photos');
        } catch (e) {
          debugPrint('[DashboardMap] Could not fetch public-photos media_files: $e');
          mediaData = [];
        }
      }

      final locMap = <String, Map<String, dynamic>>{};
      for (final l in locData) {
        final obsId = l['observation_id']?.toString() ?? '';
        final lat = (l['latitude'] as num?)?.toDouble() ?? 0.0;
        final lng = (l['longitude'] as num?)?.toDouble() ?? 0.0;
        if (lat != 0.0 && lng != 0.0 && obsId.isNotEmpty) {
          locMap[obsId] = Map<String, dynamic>.from(l as Map);
        }
      }

      final detMap = <String, List<Map<String, dynamic>>>{};
      for (final d in detData) {
        final obsId = d['observation_id']?.toString() ?? '';
        if (obsId.isNotEmpty) {
          detMap.putIfAbsent(obsId, () => []).add(Map<String, dynamic>.from(d as Map));
        }
      }

      final mediaMap = <String, Map<String, dynamic>>{};
      for (final m in mediaData) {
        final obsId = m['observation_id']?.toString() ?? '';
        final bucket = m['bucket']?.toString() ?? '';
        if (obsId.isNotEmpty && bucket == 'public-photos' && !mediaMap.containsKey(obsId)) {
          mediaMap[obsId] = Map<String, dynamic>.from(m as Map);
        }
      }

      // Group by proximity (approx 11-20 meters)
      final Map<String, _Cluster> clusters = {};

      for (final rawObs in obsData) {
        final obs = Map<String, dynamic>.from(rawObs as Map);
        final obsId = obs['id']?.toString() ?? '';
        final loc = locMap[obsId];
        if (loc == null) continue;

        final lat = (loc['latitude'] as num).toDouble();
        final lng = (loc['longitude'] as num).toDouble();
        final gridKey = '${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';

        final dets = detMap[obsId] ?? [];
        String dominantClass = 'D40';
        double highestConfidence = 0.0;

        if (dets.isNotEmpty) {
          dets.sort((a, b) =>
              ((b['confidence'] as num?) ?? 0).compareTo((a['confidence'] as num?) ?? 0));
          dominantClass = dets.first['class_code']?.toString() ?? 'D40';
          highestConfidence = ((dets.first['confidence'] as num?) ?? 0).toDouble();
        } else if (TariqMapConstants.allCodes.contains(obs['anomaly_type'])) {
          dominantClass = obs['anomaly_type'] as String;
        } else if (TariqMapConstants.allCodes.contains(obs['priority_label'])) {
          dominantClass = obs['priority_label'] as String;
        }

        final media = mediaMap[obsId];
        String? publicThumbnailUrl;
        if (media != null) {
          final storagePath = media['storage_path']?.toString();
          if (storagePath != null && storagePath.isNotEmpty) {
            try {
              publicThumbnailUrl = Supabase.instance.client.storage
                  .from('public-photos')
                  .getPublicUrl(storagePath);
            } catch (_) {}
          }
          publicThumbnailUrl ??= media['public_url']?.toString();
        }

        final enrichedObs = {
          ...obs,
          'latitude': lat,
          'longitude': lng,
          'accuracy_meters': loc['accuracy_meters'],
          'dominant_class': dominantClass,
          'highest_confidence': highestConfidence,
          'detections': dets,
          'public_thumbnail_url': publicThumbnailUrl,
        };

        if (clusters.containsKey(gridKey)) {
          clusters[gridKey]!.count++;
          clusters[gridKey]!.observations.add(enrichedObs);
        } else {
          clusters[gridKey] = _Cluster(
            lat: lat,
            lng: lng,
            dominantClass: dominantClass,
            count: 1,
            observations: [enrichedObs],
          );
        }
      }

      final markers = clusters.values.map((c) {
        return Marker(
          point: LatLng(c.lat, c.lng),
          width: 44,
          height: 44,
          child: _buildMarkerWidget(c),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _markers.clear();
          _markers.addAll(markers);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load map data: $e';
          _loading = false;
        });
      }
    }
  }

  Widget _buildMarkerWidget(_Cluster cluster) {
    final color = AppColors.forClassCode(cluster.dominantClass);
    final icon = switch (cluster.dominantClass) {
      'D00' || 'D10' => Icons.timeline,
      'D20' => Icons.grid_4x4,
      'D40' => Icons.radio_button_unchecked,
      _ => Icons.warning_amber_rounded,
    };

    return Semantics(
      label: 'Map pin ${cluster.dominantClass} (${cluster.count})',
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          key: ValueKey('pin_${cluster.lat.toStringAsFixed(4)}_${cluster.lng.toStringAsFixed(4)}'),
          onTap: () {
            debugPrint('[DashboardMap] Pin tapped at ${cluster.lat}, ${cluster.lng}');
            _showClusterDetails(cluster);
          },
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(70),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: cluster.count > 1
                ? Text(
                    '${cluster.count}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  void _showClusterDetails(_Cluster cluster) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ClusterDetailsSheet(
        cluster: cluster,
        repository: widget.repository ?? SqliteObservationRepository(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    }

    // Default center to Tunisia if no markers, else center on first marker
    final center = _userLocation ??
        (_markers.isNotEmpty ? _markers.first.point : const LatLng(36.8065, 10.1815));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _userLocation != null ? 15.0 : 12.0,
              onMapReady: () {
                if (_userLocation != null) {
                  _mapController.move(_userLocation!, 15.0);
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
              MarkerLayer(markers: _markers),
              if (_userLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
                      width: 32,
                      height: 32,
                      child: IgnorePointer(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue.withAlpha(50),
                              ),
                            ),
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            bottom: 10,
            left: 10,
            child: _buildLegend(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(240),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLegendItem(AppColors.high, Icons.timeline, 'Cracks'),
          const SizedBox(height: 6),
          _buildLegendItem(AppColors.critical, Icons.radio_button_unchecked, 'Potholes'),
          const SizedBox(height: 6),
          _buildLegendItem(AppColors.teal, Icons.warning_amber_rounded, 'Other / Unknown'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 10),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _Cluster {
  final double lat;
  final double lng;
  final String dominantClass;
  int count;
  final List<Map<String, dynamic>> observations;

  _Cluster({
    required this.lat,
    required this.lng,
    required this.dominantClass,
    required this.count,
    required this.observations,
  });
}

class _ClusterDetailsSheet extends StatelessWidget {
  final _Cluster cluster;
  final ObservationRepository repository;

  const _ClusterDetailsSheet({
    required this.cluster,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final title = '${cluster.count} Anomaly Record${cluster.count > 1 ? 's' : ''}';

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: cluster.observations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (ctx, i) {
                final obs = cluster.observations[i];
                return _ObservationCard(
                  obs: obs,
                  repository: repository,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ObservationCard extends StatelessWidget {
  final Map<String, dynamic> obs;
  final ObservationRepository repository;

  const _ObservationCard({
    required this.obs,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final obsId = obs['id']?.toString() ?? '';
    final classCode = obs['dominant_class']?.toString() ?? 'D40';
    final classLabel = TariqMapConstants.labelFor(classCode);
    final color = AppColors.forClassCode(classCode);

    final priorityScore = (obs['priority_score'] as num?)?.toDouble() ?? 0.0;
    final priorityLabel = obs['priority_label']?.toString() ??
        (priorityScore >= 70 ? 'CRITICAL' : priorityScore >= 40 ? 'HIGH' : 'MEDIUM');

    final highestConfidence = (obs['highest_confidence'] as num?)?.toDouble() ?? 0.0;
    final confidenceText = highestConfidence > 0
        ? '${(highestConfidence * 100).toStringAsFixed(0)}%'
        : 'N/A';

    final status = obs['status']?.toString() ?? 'unconfirmed';

    final lat = (obs['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (obs['longitude'] as num?)?.toDouble() ?? 0.0;
    final accuracy = (obs['accuracy_meters'] as num?)?.toDouble();

    final dateStr = (obs['created_at'] ?? obs['captured_at'])?.toString() ?? '';
    String formattedDate = 'Recent';
    if (dateStr.isNotEmpty) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) {
        final local = parsed.toLocal();
        formattedDate = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      }
    }

    return Container(
      key: ValueKey('detail_card_$obsId'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: Class Pill and Status Badge ─────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: color.withAlpha(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        classCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      classLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Telemetry Grid (Anon-Readable: confidence, priority, date, position) ──
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        label: 'CONFIDENCE',
                        value: confidenceText,
                        valueColor: AppColors.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'PRIORITY',
                        value: '${priorityScore.toStringAsFixed(0)} ($priorityLabel)',
                        valueColor: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        label: 'DATE',
                        value: formattedDate,
                        valueColor: AppColors.navy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricTile(
                        label: 'STATUS',
                        value: status.toUpperCase(),
                        valueColor: AppColors.navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        label: 'POSITION',
                        value: '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}${accuracy != null ? ' (±${accuracy.toStringAsFixed(0)}m)' : ''}',
                        valueColor: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Image Section (3-Tier Fallback: Public Thumbnail -> Local Image -> Neutral Placeholder) ──
          _ObservationImageSection(
            observationId: obsId,
            repository: repository,
            remoteDetections: (obs['detections'] as List?) ?? [],
            publicThumbnailUrl: obs['public_thumbnail_url'] as String?,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ObservationImageSection extends StatefulWidget {
  final String observationId;
  final ObservationRepository repository;
  final List<dynamic> remoteDetections;
  final String? publicThumbnailUrl;

  const _ObservationImageSection({
    required this.observationId,
    required this.repository,
    required this.remoteDetections,
    this.publicThumbnailUrl,
  });

  @override
  State<_ObservationImageSection> createState() => _ObservationImageSectionState();
}

class _ObservationImageSectionState extends State<_ObservationImageSection> {
  bool _networkError = false;

  @override
  Widget build(BuildContext context) {
    if (widget.observationId.isEmpty) {
      return _buildNeutralPlaceholder();
    }

    return FutureBuilder<Observation?>(
      future: widget.repository.findById(widget.observationId),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 140,
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
            ),
          );
        }

        final localObs = snapshot.data;
        final localPath = localObs?.annotatedImagePath ?? localObs?.imagePath;
        final hasLocalImage = localPath != null && File(localPath).existsSync();

        // ── 1. Public Thumbnail (via getPublicUrl for 'public-photos' bucket) ──
        if (widget.publicThumbnailUrl != null &&
            widget.publicThumbnailUrl!.isNotEmpty &&
            !_networkError) {
          return Container(
            key: const ValueKey('public_thumbnail_container'),
            height: 220,
            color: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.network(
                    widget.publicThumbnailUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey.shade900,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.teal,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('[DashboardMap] Failed to load thumbnail from network, falling back: $error');
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _networkError = true);
                      });
                      return hasLocalImage
                          ? _buildLocalImage(localPath, localObs)
                          : _buildNeutralPlaceholder();
                    },
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.teal.withAlpha(220),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.public, color: Colors.white, size: 11),
                        SizedBox(width: 4),
                        Text(
                          'Public preview (cropped to the damage)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // ── 2. Local Image (own captures on device with bounding boxes) ──
        if (hasLocalImage) {
          return _buildLocalImage(localPath, localObs);
        }

        // ── 3. Neutral Placeholder ("Photo not public") ──
        return _buildNeutralPlaceholder();
      },
    );
  }

  Widget _buildLocalImage(String localPath, Observation? localObs) {
    final detections = localObs?.detections.isNotEmpty == true
        ? localObs!.detections
        : widget.remoteDetections.map((d) {
            final map = Map<String, dynamic>.from(d as Map);
            return Detection(
              agent: 'road_damage',
              classCode: map['class_code']?.toString() ?? 'D40',
              confidence: ((map['confidence'] as num?) ?? 0.0).toDouble(),
              box: BoundingBox(
                x: ((map['box_x'] as num?) ?? 0.0).toDouble(),
                y: ((map['box_y'] as num?) ?? 0.0).toDouble(),
                width: ((map['box_w'] as num?) ?? 0.0).toDouble(),
                height: ((map['box_h'] as num?) ?? 0.0).toDouble(),
              ),
            );
          }).toList();

    return Container(
      key: const ValueKey('local_image_container'),
      height: 220,
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnnotatedImageWidget(
              imagePath: localPath,
              detections: detections,
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.teal.withAlpha(220),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Local capture (on device)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeutralPlaceholder() {
    return Container(
      key: const ValueKey('neutral_placeholder_container'),
      height: 130,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Slate 100
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 24, color: Color(0xFF64748B)),
          SizedBox(height: 6),
          Text(
            'Photo not public',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Photo not shared publicly.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
