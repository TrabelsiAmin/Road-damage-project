import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';
import 'package:tariqmap/services/sync_policy.dart';

Observation _obs({
  required String id,
  required String imagePath,
  required SyncStatus syncStatus,
  required MediaSyncStatus mediaSyncStatus,
  required DateTime createdAt,
  String? annotatedImagePath,
  String? sourceVideoPath,
  List<AgentResult>? agentResults,
}) {
  return Observation(
    id: id,
    captureId: 'cap-$id',
    imagePath: imagePath,
    annotatedImagePath: annotatedImagePath,
    sourceVideoPath: sourceVideoPath,
    createdAt: createdAt,
    latitude: 36.8,
    longitude: 10.1,
    agentResults: agentResults ?? const [],
    actor: 'Municipality',
    syncStatus: syncStatus,
    mediaSyncStatus: mediaSyncStatus,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 7);

  test('network names treat only wifi as Wi-Fi', () {
    expect(syncNetworkTypeFromNames(const ['wifi']), SyncNetworkType.wifi);
    expect(
      syncNetworkTypeFromNames(const ['wifi', 'mobile']),
      SyncNetworkType.wifi,
    );
    expect(syncNetworkTypeFromNames(const ['mobile']), SyncNetworkType.mobile);
    expect(syncNetworkTypeFromNames(const ['none']), SyncNetworkType.unknown);
    expect(
      syncNetworkTypeFromNames(const ['ethernet']),
      SyncNetworkType.unknown,
    );
    expect(syncNetworkTypeFromNames(const []), SyncNetworkType.unknown);
    expect(
      decideSyncTransport(wifiOnly: true, network: SyncNetworkType.unknown),
      SyncTransportDecision.blocked,
    );
    expect(
      decideSyncTransport(wifiOnly: false, network: SyncNetworkType.mobile),
      SyncTransportDecision.allowed,
    );
  });

  test('sync settings persist across a new read', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await const SyncSettings(wifiOnly: false, retentionDays: 30).write(prefs);

    final again = SyncSettings.fromPrefs(await SharedPreferences.getInstance());
    expect(again.wifiOnly, isFalse);
    expect(again.retentionDays, 30);

    await const SyncSettings(wifiOnly: true, retentionDays: 0).write(prefs);
    final stored = SyncSettings.fromPrefs(await SharedPreferences.getInstance());
    expect(stored.wifiOnly, isTrue);
    expect(stored.retentionDays, 0);
  });

  test('pending, failed, and needsReview photos are never deleted', () async {
    final dir = await Directory.systemTemp.createTemp('tariqmap-retain');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    Future<File> photo(String name) async {
      final file = File('${dir.path}/$name.jpg');
      await file.writeAsBytes(const [1, 2, 3, 4]);
      return file;
    }

    final old = now.subtract(const Duration(days: 200));
    final pending = await photo('pending');
    final failed = await photo('failed');
    final review = await photo('review');
    final photoFailed = await photo('photo-failed');
    final later = await photo('later');
    final young = await photo('young');
    final ready = await photo('ready');
    final annotated = await photo('annotated');
    final video = await photo('video');
    final shared = await photo('shared');

    final observations = [
      _obs(
        id: 'pending',
        imagePath: pending.path,
        syncStatus: SyncStatus.pending,
        mediaSyncStatus: MediaSyncStatus.pending,
        createdAt: old,
      ),
      _obs(
        id: 'failed',
        imagePath: failed.path,
        syncStatus: SyncStatus.failed,
        mediaSyncStatus: MediaSyncStatus.failed,
        createdAt: old,
      ),
      _obs(
        id: 'review',
        imagePath: review.path,
        syncStatus: SyncStatus.needsReview,
        mediaSyncStatus: MediaSyncStatus.failed,
        createdAt: old,
      ),
      _obs(
        id: 'photo-failed',
        imagePath: photoFailed.path,
        syncStatus: SyncStatus.synced,
        mediaSyncStatus: MediaSyncStatus.failed,
        createdAt: old,
      ),
      _obs(
        id: 'later',
        imagePath: later.path,
        syncStatus: SyncStatus.failed,
        mediaSyncStatus: MediaSyncStatus.originalUploaded,
        createdAt: old,
      ),
      _obs(
        id: 'young',
        imagePath: young.path,
        syncStatus: SyncStatus.synced,
        mediaSyncStatus: MediaSyncStatus.uploaded,
        createdAt: now.subtract(const Duration(days: 10)),
      ),
      _obs(
        id: 'ready',
        imagePath: ready.path,
        annotatedImagePath: annotated.path,
        sourceVideoPath: video.path,
        syncStatus: SyncStatus.synced,
        mediaSyncStatus: MediaSyncStatus.uploaded,
        createdAt: old,
      ),
      _obs(
        id: 'shared-pending',
        imagePath: shared.path,
        syncStatus: SyncStatus.pending,
        mediaSyncStatus: MediaSyncStatus.pending,
        createdAt: old,
      ),
      _obs(
        id: 'shared-synced',
        imagePath: shared.path,
        syncStatus: SyncStatus.synced,
        mediaSyncStatus: MediaSyncStatus.uploaded,
        createdAt: old,
      ),
    ];

    final deleted = await deleteEligibleLocalPhotos(
      observations: observations,
      retentionDays: 90,
      now: now,
    );

    expect(deleted, 2);
    expect(pending.existsSync(), isTrue);
    expect(failed.existsSync(), isTrue);
    expect(review.existsSync(), isTrue);
    expect(photoFailed.existsSync(), isTrue);
    expect(later.existsSync(), isTrue);
    expect(young.existsSync(), isTrue);
    expect(ready.existsSync(), isFalse);
    expect(annotated.existsSync(), isFalse);
    expect(video.existsSync(), isTrue);
    expect(shared.existsSync(), isTrue);

    final forever = await deleteEligibleLocalPhotos(
      observations: [
        _obs(
          id: 'forever',
          imagePath: pending.path,
          syncStatus: SyncStatus.synced,
          mediaSyncStatus: MediaSyncStatus.uploaded,
          createdAt: old,
        ),
      ],
      retentionDays: 0,
      now: now,
    );
    expect(forever, 0);
    expect(pending.existsSync(), isTrue);
  });

  test('retention runs from the coordinator without removing a retry photo',
      () async {
    final dir = await Directory.systemTemp.createTemp('tariqmap-retain-sync');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final keep = File('${dir.path}/keep.jpg');
    final drop = File('${dir.path}/drop.jpg');
    await keep.writeAsBytes(const [9]);
    await drop.writeAsBytes(const [8]);
    final repo = MemoryObservationRepository();
    await repo.save(_obs(
      id: 'keep',
      imagePath: keep.path,
      syncStatus: SyncStatus.needsReview,
      mediaSyncStatus: MediaSyncStatus.failed,
      createdAt: now.subtract(const Duration(days: 400)),
    ));
    await repo.save(_obs(
      id: 'drop',
      imagePath: drop.path,
      syncStatus: SyncStatus.synced,
      mediaSyncStatus: MediaSyncStatus.uploaded,
      createdAt: now.subtract(const Duration(days: 400)),
    ));
    final sync = SyncCoordinator(
      repo,
      _NoUpload(),
      readSettings: () async => const SyncSettings(wifiOnly: true, retentionDays: 90),
      readNetwork: () async => SyncNetworkType.mobile,
      clock: () => now,
    );

    final result = await sync.syncPending();

    expect(result.blocked, isTrue);
    expect(keep.existsSync(), isTrue);
    expect(drop.existsSync(), isFalse);
    expect(await repo.findById('drop'), isNotNull);
    expect(await repo.findById('keep'), isNotNull);
  });

  test('repeated cleanup keeps sync status, detections, and the remote url',
      () async {
    final dir = await Directory.systemTemp.createTemp('tariqmap-retain-twice');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final photo = File('${dir.path}/old.jpg');
    final pendingPhoto = File('${dir.path}/pending.jpg');
    final failedPhoto = File('${dir.path}/failed.jpg');
    final reviewPhoto = File('${dir.path}/review.jpg');
    await photo.writeAsBytes(const [1]);
    await pendingPhoto.writeAsBytes(const [2]);
    await failedPhoto.writeAsBytes(const [3]);
    await reviewPhoto.writeAsBytes(const [4]);
    final repo = MemoryObservationRepository();
    final synced = _obs(
      id: 'synced',
      imagePath: photo.path,
      syncStatus: SyncStatus.synced,
      mediaSyncStatus: MediaSyncStatus.uploaded,
      createdAt: now.subtract(const Duration(days: 120)),
      agentResults: const [
        AgentResult(
          agent: 'road_damage',
          detections: [
            Detection(
              agent: 'road_damage',
              classCode: 'D10',
              confidence: 0.8,
              box: BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            ),
          ],
        ),
      ],
    );
    synced.remoteImageUrl = 'https://cdn.example/original.webp';
    await repo.save(synced);
    await repo.save(_obs(
      id: 'pending',
      imagePath: pendingPhoto.path,
      syncStatus: SyncStatus.pending,
      mediaSyncStatus: MediaSyncStatus.pending,
      createdAt: now.subtract(const Duration(days: 120)),
    ));
    await repo.save(_obs(
      id: 'failed',
      imagePath: failedPhoto.path,
      syncStatus: SyncStatus.failed,
      mediaSyncStatus: MediaSyncStatus.failed,
      createdAt: now.subtract(const Duration(days: 120)),
    ));
    await repo.save(_obs(
      id: 'review',
      imagePath: reviewPhoto.path,
      syncStatus: SyncStatus.needsReview,
      mediaSyncStatus: MediaSyncStatus.failed,
      createdAt: now.subtract(const Duration(days: 120)),
    ));
    final coordinator = SyncCoordinator(
      repo,
      _NoUpload(),
      readSettings: () async =>
          const SyncSettings(wifiOnly: false, retentionDays: 90),
      clock: () => now,
    );

    await coordinator.applyPhotoRetention();
    await coordinator.applyPhotoRetention();

    final stored = await repo.findById('synced');
    expect(stored!.syncStatus, SyncStatus.synced);
    expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
    expect(stored.remoteImageUrl, 'https://cdn.example/original.webp');
    expect(stored.imagePath, photo.path);
    expect(stored.detections.single.classCode, 'D10');
    expect(stored.detections.single.box.width, 0.3);
    expect(photo.existsSync(), isFalse);
    expect(pendingPhoto.existsSync(), isTrue);
    expect(failedPhoto.existsSync(), isTrue);
    expect(reviewPhoto.existsSync(), isTrue);
  });
}

class _NoUpload implements ObservationSyncClient {
  @override
  Future<void> upload(
    Observation observation, {
    required String idempotencyKey,
    SyncCancelToken? cancelToken,
    ObservationRepository? repository,
  }) async {
    throw StateError('upload must not run');
  }
}
