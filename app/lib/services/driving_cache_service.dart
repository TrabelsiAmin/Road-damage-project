import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../data/local/database.dart';
import '../models/upcoming_anomaly.dart';
import '../utils/geospatial_math.dart';

/// Manages offline caching of road anomalies for Drive Awareness in SQLite.
class DrivingCacheService {
  DrivingCacheService({Database? database}) : _database = database;

  final Database? _database;

  Future<Database> get _db async {
    final db = _database;
    if (db != null) return db;
    return AppDatabase.instance.database;
  }

  static const String tableName = 'cached_anomalies';
  static const int defaultMaxRecords = 500;

  /// Caches a batch of anomalies in SQLite.
  Future<void> saveAnomalies(List<UpcomingAnomaly> anomalies) async {
    if (anomalies.isEmpty) return;

    try {
      final db = await _db;
      final batch = db.batch();
      final now = DateTime.now().toIso8601String();

      for (final a in anomalies) {
        batch.insert(
          tableName,
          {
            'observation_id': a.observationId,
            'latitude': a.latitude,
            'longitude': a.longitude,
            'anomaly_type': a.anomalyType,
            'priority_score': a.priorityScore,
            'priority_label': a.priorityLabel,
            'status': a.status,
            'accuracy_meters': a.accuracyMeters,
            'created_at': a.createdAt.toIso8601String(),
            'report_count': a.reportCount,
            'cached_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      await _enforceMaxRecords(db);
    } catch (e) {
      debugPrint('[DrivingCacheService] Error caching anomalies: $e');
    }
  }

  /// Retrieves cached anomalies within [radiusMeters] of the given coordinate.
  Future<List<UpcomingAnomaly>> getCachedAnomaliesNearby({
    required double latitude,
    required double longitude,
    double radiusMeters = 2000.0,
    Duration maxAge = const Duration(hours: 24),
  }) async {
    try {
      final db = await _db;
      final cutoff = DateTime.now().subtract(maxAge).toIso8601String();

      // Rough bounding box in degrees (1 degree lat ≈ 111,000 m)
      final latDelta = (radiusMeters / 111000.0) * 1.2;
      final lonDelta = (radiusMeters / (111000.0 * math.cos(latitude * math.pi / 180.0).abs().clamp(0.1, 1.0))) * 1.2;

      final rows = await db.query(
        tableName,
        where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ? AND cached_at >= ?',
        whereArgs: [
          latitude - latDelta,
          latitude + latDelta,
          longitude - lonDelta,
          longitude + lonDelta,
          cutoff,
        ],
      );

      final results = <UpcomingAnomaly>[];
      for (final row in rows) {
        final anomaly = UpcomingAnomaly.fromMap(row);
        final dist = GeospatialMath.haversineDistanceMeters(
          latitude,
          longitude,
          anomaly.latitude,
          anomaly.longitude,
        );
        if (dist <= radiusMeters) {
          results.add(anomaly);
        }
      }

      // Sort by proximity
      results.sort((a, b) {
        final distA = GeospatialMath.haversineDistanceMeters(latitude, longitude, a.latitude, a.longitude);
        final distB = GeospatialMath.haversineDistanceMeters(latitude, longitude, b.latitude, b.longitude);
        return distA.compareTo(distB);
      });

      return results;
    } catch (e) {
      debugPrint('[DrivingCacheService] Error reading cached anomalies: $e');
      return [];
    }
  }

  /// Prunes records if the table exceeds [maxRecords].
  Future<void> _enforceMaxRecords(Database db, {int maxRecords = defaultMaxRecords}) async {
    try {
      final countRes = await db.rawQuery('SELECT COUNT(*) as cnt FROM $tableName');
      final total = Sqflite.firstIntValue(countRes) ?? 0;
      if (total > maxRecords) {
        final toDelete = total - maxRecords;
        await db.rawDelete('''
          DELETE FROM $tableName WHERE observation_id IN (
            SELECT observation_id FROM $tableName ORDER BY cached_at ASC LIMIT ?
          )
        ''', [toDelete]);
      }
    } catch (e) {
      debugPrint('[DrivingCacheService] Error enforcing max records: $e');
    }
  }

  /// Deletes all cached records.
  Future<void> clearCache() async {
    try {
      final db = await _db;
      await db.delete(tableName);
    } catch (e) {
      debugPrint('[DrivingCacheService] Error clearing cache: $e');
    }
  }
}
