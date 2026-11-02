import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tariqmap/data/local/database.dart';
import 'package:tariqmap/models/upcoming_anomaly.dart';
import 'package:tariqmap/services/driving_cache_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DrivingCacheService', () {
    late Database testDb;
    late DrivingCacheService cacheService;

    setUp(() async {
      testDb = await openDatabase(inMemoryDatabasePath);
      await AppDatabase.createSchema(testDb);
      cacheService = DrivingCacheService(database: testDb);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('saves and retrieves anomalies within radius', () async {
      final anomaly1 = UpcomingAnomaly(
        observationId: 'tunis-pothole',
        latitude: 36.8065,
        longitude: 10.1815,
        anomalyType: 'D40',
        priorityScore: 85.0,
        priorityLabel: 'high',
        status: 'confirmed',
        createdAt: DateTime.now(),
        reportCount: 3,
      );

      // Far away in Sousse (~120 km)
      final anomaly2 = UpcomingAnomaly(
        observationId: 'sousse-crack',
        latitude: 35.8256,
        longitude: 10.6369,
        anomalyType: 'D00',
        priorityScore: 40.0,
        priorityLabel: 'low',
        status: 'confirmed',
        createdAt: DateTime.now(),
        reportCount: 1,
      );

      await cacheService.saveAnomalies([anomaly1, anomaly2]);

      // Query around Tunis center (radius 2000m)
      final results = await cacheService.getCachedAnomaliesNearby(
        latitude: 36.8065,
        longitude: 10.1815,
        radiusMeters: 2000.0,
      );

      expect(results.length, 1);
      expect(results.first.observationId, 'tunis-pothole');
      expect(results.first.reportCount, 3);
    });

    test('filters out expired anomalies', () async {
      final oldDate = DateTime.now().subtract(const Duration(hours: 48));
      final expiredAnomaly = UpcomingAnomaly(
        observationId: 'expired-pothole',
        latitude: 36.8065,
        longitude: 10.1815,
        anomalyType: 'D40',
        priorityScore: 90.0,
        priorityLabel: 'critical',
        status: 'confirmed',
        createdAt: oldDate,
        cachedAt: oldDate,
      );

      // Insert directly with old cached_at date
      await testDb.insert(DrivingCacheService.tableName, expiredAnomaly.toMap());

      final results = await cacheService.getCachedAnomaliesNearby(
        latitude: 36.8065,
        longitude: 10.1815,
        radiusMeters: 2000.0,
        maxAge: const Duration(hours: 24),
      );

      expect(results, isEmpty);
    });

    test('clearCache removes all cached records', () async {
      final anomaly = UpcomingAnomaly(
        observationId: 'to-clear',
        latitude: 36.8065,
        longitude: 10.1815,
        anomalyType: 'D40',
        priorityScore: 85.0,
        priorityLabel: 'high',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      await cacheService.saveAnomalies([anomaly]);
      expect(await cacheService.getCachedAnomaliesNearby(
        latitude: 36.8065,
        longitude: 10.1815,
      ), isNotEmpty);

      await cacheService.clearCache();
      expect(await cacheService.getCachedAnomaliesNearby(
        latitude: 36.8065,
        longitude: 10.1815,
      ), isEmpty);
    });
  });
}
