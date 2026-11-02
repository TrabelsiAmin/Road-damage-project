import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/remote/supabase_service.dart';
import '../models/upcoming_anomaly.dart';
import '../utils/geospatial_math.dart';
import 'driving_cache_service.dart';

/// Abstract repository for fetching road anomalies around the driver.
abstract class DriveAnomalyRepository {
  Future<List<UpcomingAnomaly>> getNearbyAnomalies({
    required double latitude,
    required double longitude,
    double radiusMeters = 1500.0,
    bool forceRefresh = false,
  });

  /// Releases resources if applicable.
  void dispose() {}
}

/// Production implementation with offline SQLite caching, spatial debounce,
/// and remote PostGIS RPC query.
class DefaultDriveAnomalyRepository implements DriveAnomalyRepository {
  DefaultDriveAnomalyRepository({
    DrivingCacheService? cacheService,
    SupabaseService? supabaseService,
    this.minDistanceBetweenQueriesMeters = 75.0,
    this.minIntervalBetweenQueries = const Duration(seconds: 15),
  })  : _cacheService = cacheService ?? DrivingCacheService(),
        _supabaseService = supabaseService ?? SupabaseService.instance;

  final DrivingCacheService _cacheService;
  final SupabaseService _supabaseService;
  final double minDistanceBetweenQueriesMeters;
  final Duration minIntervalBetweenQueries;

  double? _lastFetchLat;
  double? _lastFetchLon;
  DateTime? _lastFetchTime;
  List<UpcomingAnomaly> _inMemoryBuffer = [];

  bool _shouldFetchRemote(double lat, double lon, bool forceRefresh) {
    if (forceRefresh) return true;
    if (_lastFetchTime == null || _lastFetchLat == null || _lastFetchLon == null) return true;

    final elapsed = DateTime.now().difference(_lastFetchTime!);
    if (elapsed > minIntervalBetweenQueries) return true;

    final dist = GeospatialMath.haversineDistanceMeters(_lastFetchLat!, _lastFetchLon!, lat, lon);
    return dist >= minDistanceBetweenQueriesMeters;
  }

  @override
  Future<List<UpcomingAnomaly>> getNearbyAnomalies({
    required double latitude,
    required double longitude,
    double radiusMeters = 1500.0,
    bool forceRefresh = false,
  }) async {
    final needsRemote = _shouldFetchRemote(latitude, longitude, forceRefresh);

    if (needsRemote) {
      try {
        final remote = await _supabaseService.fetchNearbyAnomalies(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: radiusMeters,
        );

        if (remote.isNotEmpty) {
          _lastFetchLat = latitude;
          _lastFetchLon = longitude;
          _lastFetchTime = DateTime.now();
          _inMemoryBuffer = remote;

          // Asynchronously persist to offline SQLite cache
          unawaited(_cacheService.saveAnomalies(remote));
          return _filterByRadius(remote, latitude, longitude, radiusMeters);
        }
      } catch (e) {
        debugPrint('[DriveAnomalyRepository] Remote query failed, falling back to cache: $e');
      }
    }

    // Fallback: Read from local SQLite cache
    final cached = await _cacheService.getCachedAnomaliesNearby(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );

    if (cached.isNotEmpty) {
      _inMemoryBuffer = cached;
      return cached;
    }

    // Last resort: return whatever is currently in memory buffer
    return _filterByRadius(_inMemoryBuffer, latitude, longitude, radiusMeters);
  }

  List<UpcomingAnomaly> _filterByRadius(
    List<UpcomingAnomaly> items,
    double lat,
    double lon,
    double radiusMeters,
  ) {
    final filtered = items.where((a) {
      final d = GeospatialMath.haversineDistanceMeters(lat, lon, a.latitude, a.longitude);
      return d <= radiusMeters;
    }).toList();

    filtered.sort((a, b) {
      final da = GeospatialMath.haversineDistanceMeters(lat, lon, a.latitude, a.longitude);
      final db = GeospatialMath.haversineDistanceMeters(lat, lon, b.latitude, b.longitude);
      return da.compareTo(db);
    });

    return filtered;
  }

  @override
  void dispose() {}
}

/// In-memory repository implementation for unit testing and offline preview.
class MemoryDriveAnomalyRepository implements DriveAnomalyRepository {
  MemoryDriveAnomalyRepository([List<UpcomingAnomaly>? initialItems])
      : items = List.from(initialItems ?? []);

  final List<UpcomingAnomaly> items;

  void add(UpcomingAnomaly anomaly) => items.add(anomaly);
  void clear() => items.clear();

  @override
  Future<List<UpcomingAnomaly>> getNearbyAnomalies({
    required double latitude,
    required double longitude,
    double radiusMeters = 1500.0,
    bool forceRefresh = false,
  }) async {
    final filtered = items.where((a) {
      final d = GeospatialMath.haversineDistanceMeters(latitude, longitude, a.latitude, a.longitude);
      return d <= radiusMeters;
    }).toList();

    filtered.sort((a, b) {
      final da = GeospatialMath.haversineDistanceMeters(latitude, longitude, a.latitude, a.longitude);
      final db = GeospatialMath.haversineDistanceMeters(latitude, longitude, b.latitude, b.longitude);
      return da.compareTo(db);
    });

    return filtered;
  }

  @override
  void dispose() {}
}
