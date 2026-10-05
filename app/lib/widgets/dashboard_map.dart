import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_colors.dart';
import '../services/territorial_service.dart';

class DashboardMap extends StatefulWidget {
  const DashboardMap({super.key});

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
        // Try to move if map is already built
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
      final client = Supabase.instance.client;
      
      // Fetch observations with their locations and highest confidence detections
      // We do separate queries if joins fail, but let's try direct first.
      // A safer approach for a hackathon without guaranteed FKs is querying separately.
      
      final obsData = await client.from('observations').select('id, capture_id, priority_score, priority_label');
      final locData = await client.from('locations').select('observation_id, latitude, longitude');
      final detData = await client.from('detections').select('observation_id, class_code, confidence');

      final locMap = <String, Map<String, dynamic>>{};
      for (final l in locData) {
        if (l['latitude'] != 0.0 && l['longitude'] != 0.0) {
          locMap[l['observation_id'] as String] = l;
        }
      }

      final detMap = <String, List<Map<String, dynamic>>>{};
      for (final d in detData) {
        final obsId = d['observation_id'] as String;
        detMap.putIfAbsent(obsId, () => []).add(d);
      }

      // Group by proximity (rounding to 4 decimal places, approx 11 meters)
      final Map<String, _Cluster> clusters = {};

      for (final obs in obsData) {
        final obsId = obs['id'] as String;
        final loc = locMap[obsId];
        if (loc == null) continue;

        final lat = (loc['latitude'] as num).toDouble();
        final lng = (loc['longitude'] as num).toDouble();
        
        final gridKey = '${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';
        
        final dets = detMap[obsId] ?? [];
        
        String dominantClass = 'unknown';
        if (dets.isNotEmpty) {
          // Find the dominant class for this observation
          dets.sort((a, b) => (b['confidence'] as num).compareTo(a['confidence'] as num));
          dominantClass = dets.first['class_code'] as String;
        } else if (obs['priority_label'] != null && (obs['priority_label'] as String).isNotEmpty) {
          dominantClass = obs['priority_label'] as String;
        }

        if (clusters.containsKey(gridKey)) {
          clusters[gridKey]!.count++;
          clusters[gridKey]!.observations.add(obs);
        } else {
          clusters[gridKey] = _Cluster(
            lat: lat,
            lng: lng,
            dominantClass: dominantClass,
            count: 1,
            observations: [obs],
          );
        }
      }

      final markers = clusters.values.map((c) {
        return Marker(
          point: LatLng(c.lat, c.lng),
          width: 40,
          height: 40,
          child: _buildMarkerWidget(c),
        );
      }).toList();

      if (mounted) {
        setState(() {
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
    Color color;
    IconData icon;
    
    // Assign colors based on anomaly type
    if (cluster.dominantClass.contains('crack')) {
      color = AppColors.high;
      icon = Icons.timeline;
    } else if (cluster.dominantClass.contains('pothole')) {
      color = AppColors.critical;
      icon = Icons.radio_button_unchecked;
    } else {
      color = AppColors.teal;
      icon = Icons.warning_amber_rounded;
    }

    return GestureDetector(
      onTap: () {
        _showClusterDetails(cluster);
      },
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

  void _showClusterDetails(_Cluster cluster) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ClusterDetailsSheet(cluster: cluster),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
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
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue.withAlpha(50),
                        ),
                      ),
                      Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                          ],
                        ),
                      ),
                    ],
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

  const _ClusterDetailsSheet({required this.cluster});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
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
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '${cluster.count} Anomaly Record${cluster.count > 1 ? 's' : ''}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: cluster.observations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (ctx, i) {
                final obs = cluster.observations[i];
                final id = obs['id'];
                final captureId = obs['capture_id'];
                
                final client = Supabase.instance.client;
                final futureUrl = client
                    .from('media_files')
                    .select('public_url')
                    .eq('observation_id', id)
                    .maybeSingle()
                    .then((row) => row != null ? row['public_url'] as String : null);

                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 200,
                        color: Colors.grey.shade100,
                        child: FutureBuilder<String?>(
                          future: futureUrl,
                          builder: (ctx, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final imageUrl = snapshot.data;
                            if (imageUrl == null) {
                              return const Center(
                                child: Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                              );
                            }
                            return Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => const Center(
                                child: Icon(Icons.broken_image, size: 40, color: Colors.grey),
                              ),
                              loadingBuilder: (ctx, child, progress) {
                                if (progress == null) return child;
                                return const Center(child: CircularProgressIndicator());
                              },
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          'Label: ${obs['priority_label'] ?? 'Unknown'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
