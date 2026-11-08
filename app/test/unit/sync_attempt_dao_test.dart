import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tariqmap/data/local/database.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('a failed attempt increments once and uploading does not reset it', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    await AppDatabase.createSchema(db);
    final repo = SqliteObservationRepository(
      db: AppDatabase.withDatabase(db),
    );
    addTearDown(db.close);

    await repo.save(Observation(
      id: 'obs-attempts',
      captureId: 'cap',
      imagePath: '/tmp/tariqmap-missing-phasec.jpg',
      createdAt: DateTime.utc(2026, 11, 7),
      latitude: 36.8,
      longitude: 10.1,
      agentResults: const [
        AgentResult(agent: 'road_damage', detections: []),
      ],
      actor: 'Municipality',
    ));

    await repo.updateSyncStatus('obs-attempts', SyncStatus.uploading);
    expect((await repo.findById('obs-attempts'))!.uploadAttempts, 0);

    await repo.updateSyncStatus('obs-attempts', SyncStatus.failed,
        error: 'photo upload failed');
    expect((await repo.findById('obs-attempts'))!.uploadAttempts, 1);

    await repo.updateSyncStatus('obs-attempts', SyncStatus.uploading);
    expect((await repo.findById('obs-attempts'))!.uploadAttempts, 1);

    await repo.updateSyncStatus('obs-attempts', SyncStatus.failed,
        error: 'photo upload failed');
    expect((await repo.findById('obs-attempts'))!.uploadAttempts, 2);
  });

  test('older rows without a remote url still open', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE observations (
        id TEXT PRIMARY KEY,
        capture_id TEXT NOT NULL,
        image_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        actor TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        media_sync_status TEXT NOT NULL,
        upload_attempts INTEGER NOT NULL DEFAULT 0,
        model_bundle_version TEXT NOT NULL,
        failed_agents INTEGER NOT NULL DEFAULT 0,
        any_mock INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE TABLE agent_results (observation_id TEXT, agent TEXT, error TEXT, is_mock INTEGER, latency_ms INTEGER)');
    await db.execute(
        'CREATE TABLE detections (observation_id TEXT, agent TEXT, class_code TEXT, confidence REAL, box_x REAL, box_y REAL, box_w REAL, box_h REAL, frame_index INTEGER, model_version TEXT, detected_at TEXT)');
    await db.insert('observations', {
      'id': 'old-row',
      'capture_id': 'cap',
      'image_path': '/tmp/tariqmap-missing-old.jpg',
      'created_at': '2026-01-01T00:00:00.000Z',
      'latitude': 36.8,
      'longitude': 10.1,
      'actor': 'Municipality',
      'sync_status': 'synced',
      'media_sync_status': 'uploaded',
      'model_bundle_version': 'test',
    });
    await db.insert('agent_results', {
      'observation_id': 'old-row',
      'agent': 'road_damage',
      'is_mock': 0,
    });
    await db.insert('detections', {
      'observation_id': 'old-row',
      'agent': 'road_damage',
      'class_code': 'D00',
      'confidence': 0.9,
      'box_x': 0.1,
      'box_y': 0.1,
      'box_w': 0.2,
      'box_h': 0.2,
    });

    await AppDatabase.addRemoteImageUrlColumn(db);
    final repo = SqliteObservationRepository(db: AppDatabase.withDatabase(db));
    final loaded = await repo.findById('old-row');
    expect(loaded, isNotNull);
    expect(loaded!.remoteImageUrl, isNull);
    expect(loaded.syncStatus, SyncStatus.synced);
    expect(loaded.detections.single.classCode, 'D00');

    await repo.updateRemoteImageUrl('old-row', ' https://cdn.example/a.webp ');
    final again = await repo.findById('old-row');
    expect(again!.remoteImageUrl, 'https://cdn.example/a.webp');
    expect(again.syncStatus, SyncStatus.synced);
    expect(again.detections.single.classCode, 'D00');

    await repo.updateRemoteImageUrl('old-row', 'https://cdn.example/a.webp');
    expect((await repo.findById('old-row'))!.remoteImageUrl,
        'https://cdn.example/a.webp');
  });
}
