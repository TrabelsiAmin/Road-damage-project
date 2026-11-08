import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';
import 'package:tariqmap/services/sync_plan.dart';
import 'package:tariqmap/services/sync_policy.dart';

class MockDetailedSyncClient implements ObservationSyncClient {
  int uploadCount = 0;
  int photoAttempts = 0;
  int originalUploadAttempts = 0;
  int thumbnailAttempts = 0;
  bool shouldFail = false;
  bool failPhoto = false;
  bool failThumbnail = false;
  bool failReceipt = false;
  int receiptAttempts = 0;
  int receiptSelects = 0;
  int agentRunSelects = 0;

  /// When true, metadata came from submit_observation. The client must not
  /// read or insert a second receipt, and must not read agent_runs.
  bool rpcMetadataAccepted = false;
  String rpcStatus = 'synced';

  /// Injected direct-path receipt insert error. Null means the insert works.
  String? receiptInsertCode;
  String? receiptInsertMessage;
  String? receiptInsertDetails;
  bool simulateStorageConflict = false;
  ConfirmedStorageObject? confirmedConflict;
  bool simulateThumbnailConflict = false;
  ConfirmedStorageObject? confirmedThumbnail;
  bool originalStored = false;
  List<Observation> uploaded = [];

  // Simulated backend database tables to test idempotency and duplicate prevention
  final Map<String, Map<String, dynamic>> observationsTable = {};
  final Map<String, Map<String, dynamic>> locationsTable = {};
  final Map<String, Map<String, dynamic>> agentRunsTable = {};
  final Map<String, Map<String, dynamic>> detectionsTable = {};
  final Map<String, Map<String, dynamic>> mediaFilesTable = {};
  final Map<String, Map<String, dynamic>> receiptsTable = {};

  // Interception callbacks
  void Function(Observation obs, SyncCancelToken? token)? onBeforeObservationRow;
  void Function(Observation obs, SyncCancelToken? token)? onMidObservation;
  void Function(Observation obs, SyncCancelToken? token)? onImageUpload;

  @override
  Future<void> upload(
    Observation observation, {
    required String idempotencyKey,
    SyncCancelToken? cancelToken,
    ObservationRepository? repository,
  }) async {
    uploadCount++;
    if (shouldFail) {
      throw Exception('Mock network failure');
    }

    cancelToken?.throwIfCancelled();
    onBeforeObservationRow?.call(observation, cancelToken);
    cancelToken?.throwIfCancelled();

    final ack = SubmitObservationAck(
      callSucceeded: rpcMetadataAccepted,
      status: rpcMetadataAccepted ? rpcStatus : null,
    );
    // agent_runs is not read on either path. A successful RPC contributes no
    // child ids, and the direct path writes the stable ids itself.
    if (agentRunSelects != 0) {
      throw StateError('agent_runs was read');
    }
    if (rpcMetadataAccepted && !receiptsTable.containsKey(idempotencyKey)) {
      receiptsTable[idempotencyKey] = {
        'observation_id': observation.id,
        'idempotency_key': idempotencyKey,
        'payload_hash': 'atomic-rpc-sync',
      };
    }

    // 1. Observations row. An existing row continues only when its identity matches.
    _insertOrMatch(
      table: observationsTable,
      key: observation.id,
      childId: observation.id,
      observationId: observation.id,
      identity: {
        'id': observation.id,
        'capture_id': observation.captureId,
      },
      row: {
        'id': observation.id,
        'capture_id': observation.captureId,
      },
    );

    // Hook to simulate cancel mid-observation after partial row insertion
    cancelToken?.throwIfCancelled();
    onMidObservation?.call(observation, cancelToken);
    cancelToken?.throwIfCancelled();

    // 2. Locations row
    _insertOrMatch(
      table: locationsTable,
      key: observation.id,
      observationId: observation.id,
      identity: {
        'observation_id': observation.id,
        'latitude': observation.latitude,
        'longitude': observation.longitude,
      },
      row: {
        'observation_id': observation.id,
        'latitude': observation.latitude,
        'longitude': observation.longitude,
        'lat': observation.latitude,
        'lng': observation.longitude,
      },
    );

    // 3. Agent runs and detections reuse UUID v5 ids. An existing child is kept.
    for (var i = 0; i < observation.agentResults.length; i++) {
      final result = observation.agentResults[i];
      final runId = stableAgentRunId(observation.id, i, result.agent);
      _insertOrMatch(
        table: agentRunsTable,
        key: runId,
        childId: runId,
        observationId: observation.id,
        identity: {
          'id': runId,
          'observation_id': observation.id,
          'agent': result.agent,
        },
        row: {
          'id': runId,
          'observation_id': observation.id,
          'agent': result.agent,
        },
      );
      for (var j = 0; j < result.detections.length; j++) {
        final detId = stableDetectionId(observation.id, i, j);
        _insertOrMatch(
          table: detectionsTable,
          key: detId,
          childId: detId,
          observationId: observation.id,
          identity: {
            'id': detId,
            'observation_id': observation.id,
            'class_code': result.detections[j].classCode,
            'agent_run_id': runId,
          },
          row: {
            'id': detId,
            'observation_id': observation.id,
            'class_code': result.detections[j].classCode,
            'agent_run_id': runId,
            'class': result.detections[j].classCode,
          },
        );
      }
    }

    // 4. Original photo, then thumbnail. A confirmed original is not sent again.
    cancelToken?.throwIfCancelled();
    onImageUpload?.call(observation, cancelToken);
    cancelToken?.throwIfCancelled();
    final storedMedia =
        (await repository?.findById(observation.id))?.mediaSyncStatus;
    final originalAlreadyStored = originalStored ||
        storedMedia == MediaSyncStatus.originalUploaded ||
        storedMedia == MediaSyncStatus.uploaded;
    var originalConfirmed = originalAlreadyStored;
    if (!originalAlreadyStored) {
      photoAttempts++;
      if (failPhoto) {
        await repository?.updateMediaSyncStatus(
            observation.id, MediaSyncStatus.failed);
        throw Exception('photo upload failed');
      }
      final mediaId = stableOriginalMediaId(observation.id);
      const expectedBucket = 'observation-images';
      final expectedPath = '${observation.id}/$mediaId.webp';
      if (simulateStorageConflict) {
        try {
          final confirmed = confirmedConflict;
          final decision = decideRemoteConflict(RemoteConflictQuery.storage(
            expectedBucket: expectedBucket,
            expectedPath: expectedPath,
            confirmedBucket: confirmed?.bucket,
            confirmedPath: confirmed?.path,
          ));
          if (decision != RemoteConflictDecision.accept) {
            throw StateError(
              'Storage conflict is not the intended object at $expectedBucket/$expectedPath',
            );
          }
        } catch (e) {
          await repository?.updateMediaSyncStatus(
              observation.id, MediaSyncStatus.failed);
          rethrow;
        }
      }
      originalUploadAttempts++;
      _insertOrMatch(
        table: mediaFilesTable,
        key: observation.id,
        childId: mediaId,
        observationId: observation.id,
        identity: {
          'id': mediaId,
          'observation_id': observation.id,
          'bucket': expectedBucket,
          'storage_path': expectedPath,
          'media_type': 'image',
        },
        row: {
          'id': mediaId,
          'observation_id': observation.id,
          'bucket': expectedBucket,
          'storage_path': expectedPath,
          'media_type': 'image',
        },
      );
      originalStored = true;
      originalConfirmed = true;
      await repository?.updateMediaSyncStatus(
          observation.id, MediaSyncStatus.originalUploaded);
    }

    thumbnailAttempts++;
    if (simulateThumbnailConflict) {
      const thumbBucket = 'public-photos';
      final thumbPath = publicThumbnailObjectPath(observation.id);
      final decision = decideRemoteConflict(RemoteConflictQuery.storage(
        expectedBucket: thumbBucket,
        expectedPath: thumbPath,
        confirmedBucket: confirmedThumbnail?.bucket,
        confirmedPath: confirmedThumbnail?.path,
      ));
      if (decision != RemoteConflictDecision.accept) {
        throw StateError(
          'Storage conflict is not the intended object at $thumbBucket/$thumbPath',
        );
      }
    }
    if (failThumbnail) {
      throw Exception('thumbnail step failed');
    }
    await repository?.updateMediaSyncStatus(
        observation.id, MediaSyncStatus.uploaded);

    // 5. Receipt. A successful RPC already stored one. The direct path inserts
    // one after media and does not SELECT sync_receipts.
    cancelToken?.throwIfCancelled();
    final thumbnailFinished =
        (await repository?.findById(observation.id))?.mediaSyncStatus ==
            MediaSyncStatus.uploaded;
    if (rpcOwnsMetadataReceipt(ack)) {
      uploaded.add(observation);
      return;
    }
    if (!clientReceiptInsertWithoutRead(
      rpcCallSucceeded: ack.callSucceeded,
      observationStored: observationsTable.containsKey(observation.id),
      originalConfirmed: originalConfirmed,
      thumbnailStepFinished: thumbnailFinished,
    )) {
      return;
    }
    receiptAttempts++;
    if (failReceipt) {
      throw Exception('receipt creation failed');
    }
    final identity = {
      'observation_id': observation.id,
      'idempotency_key': idempotencyKey,
    };
    if (receiptInsertCode != null) {
      final same = duplicateKeyMatchesIdentity(
        identity: identity,
        code: receiptInsertCode,
        message: receiptInsertMessage,
        details: receiptInsertDetails,
      );
      if (!same) {
        throw StateError('receipt insert failed: $receiptInsertCode');
      }
      uploaded.add(observation);
      return;
    }
    final storedReceipt = receiptsTable[idempotencyKey];
    if (storedReceipt != null) {
      final same = duplicateKeyMatchesIdentity(
        identity: identity,
        code: '23505',
        message:
            'duplicate key value violates unique constraint "sync_receipts_identity"',
        details:
            'Key (observation_id, idempotency_key)=(${storedReceipt['observation_id']}, ${storedReceipt['idempotency_key']}) already exists.',
      );
      if (!same) {
        throw StateError('receipt conflict was not the same identity');
      }
      uploaded.add(observation);
      return;
    }
    receiptsTable[idempotencyKey] = {
      'observation_id': observation.id,
      'idempotency_key': idempotencyKey,
      'payload_hash': 'flutter-direct-sync',
    };

    uploaded.add(observation);
  }

  void _insertOrMatch({
    required Map<String, Map<String, dynamic>> table,
    required String key,
    String? childId,
    String? observationId,
    required Map<String, Object?> identity,
    required Map<String, dynamic> row,
  }) {
    final stored = table[key];
    if (stored == null) {
      table[key] = row;
      return;
    }
    final decision = decideRemoteConflict(RemoteConflictQuery.row(
      childId: childId,
      observationId: observationId,
      expectedIdentity: identity,
      storedRow: stored,
    ));
    if (decision != RemoteConflictDecision.accept) {
      throw StateError(
        'Unique conflict does not match the stored observation row',
      );
    }
  }
}

SyncCoordinator _testSync(
  ObservationRepository repo,
  ObservationSyncClient client, {
  int maxRetries = 5,
  SyncSettingsReader? readSettings,
  SyncNetworkReader? readNetwork,
  DateTime Function()? clock,
}) {
  return SyncCoordinator(
    repo,
    client,
    maxRetries: maxRetries,
    readSettings: readSettings ??
        () async => const SyncSettings(wifiOnly: false, retentionDays: 0),
    readNetwork: readNetwork ?? () async => SyncNetworkType.wifi,
    clock: clock,
  );
}

void main() {
  group('SyncCoordinator', () {
    late MemoryObservationRepository repo;
    late MockDetailedSyncClient client;
    late SyncCoordinator coordinator;

    setUp(() {
      repo = MemoryObservationRepository();
      client = MockDetailedSyncClient();
      // Set maxRetries to a small number for testing
      coordinator = _testSync(repo, client, maxRetries: 2);
    });

    Observation createObs(String id,
        {List<Detection>? detections, String? imagePath}) {
      return Observation(
        id: id,
        captureId: 'cap_$id',
        imagePath: imagePath ?? '/tmp/$id.jpg',
        createdAt: DateTime.now(),
        latitude: 36.8,
        longitude: 10.1,
        agentResults: [
          AgentResult(
            agent: 'road_damage',
            detections: detections ??
                [
                  const Detection(
                    agent: 'road_damage',
                    classCode: 'D40',
                    confidence: 0.9,
                    box: BoundingBox(x: 0, y: 0, width: 10, height: 10),
                  ),
                ],
          ),
        ],
        actor: 'Municipality',
      );
    }

    test('recovers stuck uploads by marking them pending', () async {
      final obs = createObs('stuck1');
      obs.syncStatus = SyncStatus.uploading;
      await repo.save(obs);

      await coordinator.recoverStuckUploads();

      final updated = await repo.findById('stuck1');
      expect(updated!.syncStatus, SyncStatus.pending);
    });

    test('failed sync updates status to failed and increments attempts', () async {
      client.shouldFail = true;
      final obs = createObs('pending1');
      await repo.save(obs);

      await coordinator.syncPending();

      expect(client.uploadCount, 1);
      final updated = await repo.findById('pending1');
      expect(updated!.syncStatus, SyncStatus.failed);
      expect(updated.uploadAttempts, 1);
      expect(updated.syncError, isNotNull);
    });

    test('exceeding max retries marks status as needsReview', () async {
      final obs = createObs('pending1');
      obs.uploadAttempts = 2; // Equal to maxRetries
      await repo.save(obs);

      await coordinator.syncPending();

      expect(client.uploadCount, 0); // shouldn't even try
      final updated = await repo.findById('pending1');
      expect(updated!.syncStatus, SyncStatus.needsReview);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Task C required unit tests with mocked client
    // ─────────────────────────────────────────────────────────────────────────

    test('cancel before start leaves items pending with zero uploads', () async {
      final obs1 = createObs('obs-pre-1');
      final obs2 = createObs('obs-pre-2');
      await repo.save(obs1);
      await repo.save(obs2);

      final token = SyncCancelToken();
      token.cancel(); // Cancelled before starting

      final result = await coordinator.syncPending(cancelToken: token);

      expect(result.cancelled, isTrue);
      expect(result.uploadedCount, equals(0));
      expect(result.totalCount, equals(0));
      expect(client.uploadCount, equals(0));
      expect(result.message, equals('Sync cancelled: 0 of 0 uploaded'));

      // Items remain pending locally and are not deleted
      final stored1 = await repo.findById('obs-pre-1');
      final stored2 = await repo.findById('obs-pre-2');
      expect(stored1!.syncStatus, equals(SyncStatus.pending));
      expect(stored2!.syncStatus, equals(SyncStatus.pending));
    });

    test('cancel mid-observation (partial rows) then retry produces no duplicates', () async {
      final obs = createObs('obs-mid-1');
      await repo.save(obs);

      final token = SyncCancelToken();

      // Configure client to cancel mid-observation after the observation row is written
      client.onMidObservation = (o, t) {
        token.cancel();
      };

      final result = await coordinator.syncPending(cancelToken: token);

      expect(result.cancelled, isTrue);
      expect(result.uploadedCount, equals(0));
      expect(result.message, equals('Sync cancelled: 0 of 1 uploaded'));

      // Must be safely reverted to pending, not marked synced, never deleted locally
      final afterCancel = await repo.findById('obs-mid-1');
      expect(afterCancel, isNotNull);
      expect(afterCancel!.syncStatus, equals(SyncStatus.pending));

      // Partial row exists in mock observations table, but not completed
      expect(client.observationsTable.containsKey('obs-mid-1'), isTrue);
      expect(client.locationsTable.containsKey('obs-mid-1'), isFalse);
      expect(client.receiptsTable.containsKey('obs-mid-1'), isFalse);

      // Now RETRY without cancellation: must complete safely without duplicates
      client.onMidObservation = null;
      final retryResult = await coordinator.syncPending();

      expect(retryResult.cancelled, isFalse);
      expect(retryResult.uploadedCount, equals(1));
      expect(retryResult.totalCount, equals(1));

      // Database tables have exactly 1 record each (no duplicates)
      expect(client.observationsTable.length, equals(1));
      expect(client.locationsTable.length, equals(1));
      expect(client.detectionsTable.length, equals(1));
      expect(client.mediaFilesTable.length, equals(1));
      expect(client.receiptsTable.length, equals(1));

      final afterRetry = await repo.findById('obs-mid-1');
      expect(afterRetry!.syncStatus, equals(SyncStatus.synced));
    });

    test('cancel during image upload reverts item to pending and succeeds on retry', () async {
      final obs = createObs('obs-img-1');
      await repo.save(obs);

      final token = SyncCancelToken();

      client.onImageUpload = (o, t) {
        token.cancel();
      };

      final result = await coordinator.syncPending(cancelToken: token);

      expect(result.cancelled, isTrue);
      expect(result.uploadedCount, equals(0));
      expect(result.message, equals('Sync cancelled: 0 of 1 uploaded'));

      // Item was NOT marked synced because image upload did not succeed
      final midState = await repo.findById('obs-img-1');
      expect(midState!.syncStatus, equals(SyncStatus.pending));
      expect(client.mediaFilesTable.containsKey('obs-img-1'), isFalse);

      // Retry
      client.onImageUpload = null;
      final retryResult = await coordinator.syncPending();

      expect(retryResult.cancelled, isFalse);
      expect(retryResult.uploadedCount, equals(1));
      expect(client.mediaFilesTable.containsKey('obs-img-1'), isTrue);

      final finalState = await repo.findById('obs-img-1');
      expect(finalState!.syncStatus, equals(SyncStatus.synced));
    });

    test('normal completion marks all observations synced with correct message', () async {
      final obs1 = createObs('obs-norm-1');
      final obs2 = createObs('obs-norm-2');
      final obs3 = createObs('obs-norm-3');
      await repo.save(obs1);
      await repo.save(obs2);
      await repo.save(obs3);

      final result = await coordinator.syncPending();

      expect(result.cancelled, isFalse);
      expect(result.uploadedCount, equals(3));
      expect(result.totalCount, equals(3));
      expect(result.message, equals('Sync complete: 3 of 3 uploaded'));

      final item1 = await repo.findById('obs-norm-1');
      final item2 = await repo.findById('obs-norm-2');
      final item3 = await repo.findById('obs-norm-3');
      expect(item1!.syncStatus, equals(SyncStatus.synced));
      expect(item1.mediaSyncStatus, equals(MediaSyncStatus.uploaded));
      expect(item2!.syncStatus, equals(SyncStatus.synced));
      expect(item3!.syncStatus, equals(SyncStatus.synced));
    });

    test('metadata success then photo failure is not fully synced', () async {
      final image = File(
          '${Directory.systemTemp.path}/tariqmap-phasec-photo-fail.jpg');
      await image.writeAsBytes(const [1, 2, 3, 4]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });

      final obs = createObs('obs-photo-1', imagePath: image.path);
      await repo.save(obs);
      client.failPhoto = true;

      await coordinator.syncPending();

      final stored = await repo.findById('obs-photo-1');
      expect(stored!.syncStatus, SyncStatus.failed);
      expect(stored.mediaSyncStatus, MediaSyncStatus.failed);
      expect(stored.syncStatus, isNot(SyncStatus.synced));
      expect(queueSyncState(stored), QueueSyncState.metadataSyncedPhotoFailed);
      expect(queueStatusMessage(stored),
          contains('Metadata synced, but the photo upload failed'));
      expect(client.observationsTable.length, 1);
      expect(client.locationsTable.length, 1);
      expect(client.agentRunsTable.length, 1);
      expect(client.detectionsTable.length, 1);
      expect(client.mediaFilesTable, isEmpty);
      expect(client.receiptsTable, isEmpty);
      expect(client.receiptAttempts, 0);
      expect(client.photoAttempts, 1);
      expect(image.existsSync(), isTrue);
      expect(stored.imagePath, image.path);
    });

    test('photo retry reuses child ids and then becomes fully synced', () async {
      final obs = createObs('obs-photo-retry');
      await repo.save(obs);
      client.failPhoto = true;
      await coordinator.syncPending();

      final runId = client.agentRunsTable.keys.single;
      final detectionId = client.detectionsTable.keys.single;
      final beforeRuns = Map<String, Map<String, dynamic>>.from(
        client.agentRunsTable.map((key, value) => MapEntry(key, Map.of(value))),
      );

      client.failPhoto = false;
      final retry = await coordinator.syncPending();

      expect(retry.uploadedCount, 1);
      expect(client.observationsTable.length, 1);
      expect(client.locationsTable.length, 1);
      expect(client.agentRunsTable.keys, [runId]);
      expect(client.detectionsTable.keys, [detectionId]);
      expect(client.agentRunsTable[runId], beforeRuns[runId]);
      expect(client.mediaFilesTable.length, 1);
      expect(client.mediaFilesTable['obs-photo-retry']!['id'],
          stableOriginalMediaId('obs-photo-retry'));
      expect(client.photoAttempts, 2);

      final stored = await repo.findById('obs-photo-retry');
      expect(stored!.syncStatus, SyncStatus.synced);
      expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
      expect(queueSyncState(stored), QueueSyncState.fullySynced);
      expect(queueStatusMessage(stored), 'Fully synced, including the photo.');
    });

    test('retry exhaustion reaches manual review and keeps the local row', () async {
      coordinator = _testSync(repo, client, maxRetries: 1);
      final obs = createObs('obs-review');
      await repo.save(obs);
      client.failPhoto = true;

      await coordinator.syncPending();
      final failed = await repo.findById('obs-review');
      expect(failed!.syncStatus, SyncStatus.failed);
      expect(failed.uploadAttempts, 1);
      expect(client.photoAttempts, 1);

      await coordinator.syncPending();
      final review = await repo.findById('obs-review');
      expect(review!.syncStatus, SyncStatus.needsReview);
      expect(review.mediaSyncStatus, MediaSyncStatus.failed);
      expect(queueSyncState(review), QueueSyncState.manualReview);
      expect(queueStatusMessage(review),
          contains('Manual review after retry exhaustion'));
      expect(client.photoAttempts, 1);
      expect(client.observationsTable.length, 1);
      expect(await repo.findById('obs-review'), isNotNull);
    });

    test('manual retry uploads a needsReview row once and syncPending leaves it', () async {
      coordinator = _testSync(repo, client, maxRetries: 1);
      final image = File(
          '${Directory.systemTemp.path}/tariqmap-phasec1-manual.jpg');
      await image.writeAsBytes(const [9, 9, 9]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-manual', imagePath: image.path);
      await repo.save(obs);
      client.failPhoto = true;
      await coordinator.syncPending();
      await coordinator.syncPending();
      final review = await repo.findById('obs-manual');
      expect(review!.syncStatus, SyncStatus.needsReview);
      expect(review.uploadAttempts, 1);
      expect(client.photoAttempts, 1);

      await coordinator.syncPending();
      expect(client.photoAttempts, 1);
      expect((await repo.findById('obs-manual'))!.syncStatus,
          SyncStatus.needsReview);

      client.failPhoto = false;
      final result = await coordinator.retryNeedsReview('obs-manual');
      expect(result.uploadedCount, 1);
      final synced = await repo.findById('obs-manual');
      expect(synced!.syncStatus, SyncStatus.synced);
      expect(synced.mediaSyncStatus, MediaSyncStatus.uploaded);
      expect(synced.uploadAttempts, 1);
      expect(queueStatusMessage(synced), 'Fully synced, including the photo.');
      expect(client.observationsTable.length, 1);
      expect(client.locationsTable.length, 1);
      expect(client.agentRunsTable.length, 1);
      expect(client.detectionsTable.length, 1);
      expect(client.mediaFilesTable.length, 1);
      expect(image.existsSync(), isTrue);

      await coordinator.syncPending();
      expect(client.photoAttempts, 2);
    });

    test('a failed manual retry stays in review and does not reset the counter', () async {
      coordinator = _testSync(repo, client, maxRetries: 1);
      final obs = createObs('obs-manual-fail');
      await repo.save(obs);
      client.failPhoto = true;
      await coordinator.syncPending();
      await coordinator.syncPending();
      expect((await repo.findById('obs-manual-fail'))!.uploadAttempts, 1);

      final result = await coordinator.retryNeedsReview('obs-manual-fail');
      expect(result.uploadedCount, 0);
      final again = await repo.findById('obs-manual-fail');
      expect(again!.syncStatus, SyncStatus.needsReview);
      expect(again.uploadAttempts, 1);
      expect(again.mediaSyncStatus, isNot(MediaSyncStatus.uploaded));
      expect(queueSyncState(again), isNot(QueueSyncState.fullySynced));
      expect(queueStatusMessage(again),
          contains('The last manual retry failed'));
      final attempts = client.photoAttempts;
      await coordinator.syncPending();
      expect(client.photoAttempts, attempts);
      expect((await repo.findById('obs-manual-fail'))!.syncStatus,
          SyncStatus.needsReview);
    });

    test('409 for the same storage path is fully synced', () async {
      final image =
          File('${Directory.systemTemp.path}/tariqmap-phasec1-409-same.jpg');
      await image.writeAsBytes(const [1, 2]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-409-same', imagePath: image.path);
      await repo.save(obs);
      final path = '${obs.id}/${stableOriginalMediaId(obs.id)}.webp';
      client.simulateStorageConflict = true;
      client.confirmedConflict = ConfirmedStorageObject(
        bucket: 'observation-images',
        path: path,
      );

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, SyncStatus.synced);
      expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
      expect(client.mediaFilesTable.length, 1);
      expect(client.mediaFilesTable[obs.id]!['storage_path'], path);
      expect(client.originalUploadAttempts, 1);
      expect(image.existsSync(), isTrue);
    });

    test('409 for a different object is not fully synced', () async {
      final image =
          File('${Directory.systemTemp.path}/tariqmap-phasec1-409-other.jpg');
      await image.writeAsBytes(const [3, 4]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-409-other', imagePath: image.path);
      await repo.save(obs);
      client.simulateStorageConflict = true;
      client.confirmedConflict = const ConfirmedStorageObject(
        bucket: 'observation-images',
        path: 'someone-else/other.webp',
      );

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, isNot(SyncStatus.synced));
      expect(stored.mediaSyncStatus, MediaSyncStatus.failed);
      expect(queueSyncState(stored), isNot(QueueSyncState.fullySynced));
      expect(client.mediaFilesTable, isEmpty);
      expect(client.observationsTable.length, 1);
      expect(image.existsSync(), isTrue);
    });

    test('a thumbnail failure retries the later step without a second original', () async {
      final image =
          File('${Directory.systemTemp.path}/tariqmap-phasec1-thumb.jpg');
      await image.writeAsBytes(const [5, 6, 7]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-thumb', imagePath: image.path);
      await repo.save(obs);
      client.failThumbnail = true;

      await coordinator.syncPending();
      final midway = await repo.findById(obs.id);
      expect(midway!.syncStatus, SyncStatus.failed);
      expect(midway.mediaSyncStatus, MediaSyncStatus.originalUploaded);
      expect(queueSyncState(midway), QueueSyncState.laterStepIncomplete);
      expect(queueStatusMessage(midway), contains('Original photo is stored'));
      expect(queueSyncState(midway), isNot(QueueSyncState.fullySynced));
      expect(client.originalUploadAttempts, 1);
      expect(client.thumbnailAttempts, 1);
      expect(client.mediaFilesTable.length, 1);
      expect(client.receiptsTable, isEmpty);
      expect(client.receiptAttempts, 0);
      expect(image.existsSync(), isTrue);

      client.failThumbnail = false;
      await coordinator.syncPending();
      final done = await repo.findById(obs.id);
      expect(done!.syncStatus, SyncStatus.synced);
      expect(done.mediaSyncStatus, MediaSyncStatus.uploaded);
      expect(queueStatusMessage(done), 'Fully synced, including the photo.');
      expect(client.originalUploadAttempts, 1);
      expect(client.thumbnailAttempts, 2);
      expect(client.mediaFilesTable.length, 1);
      expect(client.observationsTable.length, 1);
      expect(client.agentRunsTable.length, 1);
      expect(client.detectionsTable.length, 1);
      expect(image.existsSync(), isTrue);
    });

    test('unconfirmed storage conflict is not fully synced', () async {
      final image =
          File('${Directory.systemTemp.path}/tariqmap-phasec2-409-none.jpg');
      await image.writeAsBytes(const [8]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-409-none', imagePath: image.path);
      await repo.save(obs);
      client.simulateStorageConflict = true;
      client.confirmedConflict = null;

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, isNot(SyncStatus.synced));
      expect(stored.mediaSyncStatus, MediaSyncStatus.failed);
      expect(queueSyncState(stored), isNot(QueueSyncState.fullySynced));
      expect(client.mediaFilesTable, isEmpty);
      expect(image.existsSync(), isTrue);
    });

    test('thumbnail 409 for the same object finishes the later step', () async {
      final image =
          File('${Directory.systemTemp.path}/tariqmap-phasec2-thumb-same.jpg');
      await image.writeAsBytes(const [9]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-thumb-409-same', imagePath: image.path);
      await repo.save(obs);
      client.simulateThumbnailConflict = true;
      client.confirmedThumbnail = ConfirmedStorageObject(
        bucket: 'public-photos',
        path: publicThumbnailObjectPath(obs.id),
      );

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, SyncStatus.synced);
      expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
      expect(client.originalUploadAttempts, 1);
      expect(client.thumbnailAttempts, 1);
      expect(image.existsSync(), isTrue);
    });

    test('thumbnail 409 for a different object is not fully synced', () async {
      final image =
          File('${Directory.systemTemp.path}/tariqmap-phasec2-thumb-other.jpg');
      await image.writeAsBytes(const [10]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-thumb-409-other', imagePath: image.path);
      await repo.save(obs);
      client.simulateThumbnailConflict = true;
      client.confirmedThumbnail = const ConfirmedStorageObject(
        bucket: 'public-photos',
        path: 'someone-else/other.webp',
      );

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, isNot(SyncStatus.synced));
      expect(stored.mediaSyncStatus, MediaSyncStatus.originalUploaded);
      expect(queueSyncState(stored), isNot(QueueSyncState.fullySynced));
      expect(client.originalUploadAttempts, 1);
      expect(image.existsSync(), isTrue);
    });

    test('thumbnail 409 without confirmation is not fully synced', () async {
      final image =
          File('${Directory.systemTemp.path}/tariqmap-phasec2-thumb-none.jpg');
      await image.writeAsBytes(const [11]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-thumb-409-none', imagePath: image.path);
      await repo.save(obs);
      client.simulateThumbnailConflict = true;

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.mediaSyncStatus, isNot(MediaSyncStatus.uploaded));
      expect(queueSyncState(stored), isNot(QueueSyncState.fullySynced));
      expect(image.existsSync(), isTrue);
    });

    test('a matching stored observation row is reused', () async {
      final image =
          File('${Directory.systemTemp.path}/tariqmap-phasec2-row-same.jpg');
      await image.writeAsBytes(const [12]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-row-same', imagePath: image.path);
      await repo.save(obs);
      client.observationsTable[obs.id] = {
        'id': obs.id,
        'capture_id': obs.captureId,
      };

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, SyncStatus.synced);
      expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
      expect(client.observationsTable.length, 1);
      expect(client.observationsTable[obs.id]!['capture_id'], obs.captureId);
      expect(image.existsSync(), isTrue);
    });

    test('photo success then receipt failure stays retryable without a receipt',
        () async {
      final obs = createObs('obs-receipt-fail');
      await repo.save(obs);
      client.failReceipt = true;

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, SyncStatus.failed);
      expect(stored.syncStatus, isNot(SyncStatus.synced));
      expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
      expect(client.receiptsTable, isEmpty);
      expect(client.receiptAttempts, 1);
      expect(client.originalUploadAttempts, 1);
      expect(client.mediaFilesTable.length, 1);
      expect(client.observationsTable.length, 1);

      client.failReceipt = false;
      final retry = await coordinator.syncPending();

      expect(retry.uploadedCount, 1);
      expect(client.originalUploadAttempts, 1);
      expect(client.photoAttempts, 1);
      expect(client.observationsTable.length, 1);
      expect(client.locationsTable.length, 1);
      expect(client.agentRunsTable.length, 1);
      expect(client.detectionsTable.length, 1);
      expect(client.mediaFilesTable.length, 1);
      expect(client.receiptsTable.length, 1);
      expect(client.receiptsTable[obs.id]!['observation_id'], obs.id);
      final done = await repo.findById(obs.id);
      expect(done!.syncStatus, SyncStatus.synced);
      expect(done.mediaSyncStatus, MediaSyncStatus.uploaded);
    });

    test('a second upload reuses ids and does not send the original again',
        () async {
      final obs = createObs('obs-duplicate');
      await repo.save(obs);

      await coordinator.syncPending();
      expect(client.receiptsTable.length, 1);
      expect(client.originalUploadAttempts, 1);

      await client.upload(
        (await repo.findById(obs.id))!,
        idempotencyKey: obs.id,
        repository: repo,
      );

      expect(client.observationsTable.length, 1);
      expect(client.locationsTable.length, 1);
      expect(client.agentRunsTable.length, 1);
      expect(client.detectionsTable.length, 1);
      expect(client.mediaFilesTable.length, 1);
      expect(client.receiptsTable.length, 1);
      expect(client.originalUploadAttempts, 1);
      expect(client.photoAttempts, 1);
      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, SyncStatus.synced);
      expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
    });

    test('a successful RPC does not read or insert a second receipt', () async {
      final obs = createObs('obs-rpc-receipt');
      await repo.save(obs);
      client.rpcMetadataAccepted = true;
      client.rpcStatus = 'synced';

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, SyncStatus.synced);
      expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
      expect(client.receiptSelects, 0);
      expect(client.agentRunSelects, 0);
      expect(client.receiptAttempts, 0);
      expect(client.receiptsTable.length, 1);
      expect(client.receiptsTable[obs.id]!['payload_hash'], 'atomic-rpc-sync');
      expect(client.observationsTable.length, 1);
      expect(client.mediaFilesTable.length, 1);
    });

    test('RPC success then photo failure stays retryable without a second receipt',
        () async {
      final obs = createObs('obs-rpc-photo');
      await repo.save(obs);
      client.rpcMetadataAccepted = true;
      client.rpcStatus = 'already_synced';
      client.failPhoto = true;

      await coordinator.syncPending();

      final failed = await repo.findById(obs.id);
      expect(failed!.syncStatus, SyncStatus.failed);
      expect(failed.mediaSyncStatus, MediaSyncStatus.failed);
      expect(failed.syncStatus, isNot(SyncStatus.synced));
      expect(client.receiptSelects, 0);
      expect(client.agentRunSelects, 0);
      expect(client.receiptAttempts, 0);
      expect(client.receiptsTable.length, 1);
      expect(client.mediaFilesTable, isEmpty);
      expect(client.photoAttempts, 1);

      client.failPhoto = false;
      final retry = await coordinator.syncPending();
      expect(retry.uploadedCount, 1);
      expect(client.receiptsTable.length, 1);
      expect(client.receiptAttempts, 0);
      expect(client.receiptSelects, 0);
      expect(client.observationsTable.length, 1);
      expect(client.agentRunsTable.length, 1);
      expect(client.detectionsTable.length, 1);
      expect(client.mediaFilesTable.length, 1);
      expect(client.originalUploadAttempts, 1);
      final done = await repo.findById(obs.id);
      expect(done!.syncStatus, SyncStatus.synced);
      expect(done.mediaSyncStatus, MediaSyncStatus.uploaded);
    });

    test('direct insert writes one receipt after the photo and not before',
        () async {
      final obs = createObs('obs-direct-receipt');
      await repo.save(obs);
      client.failPhoto = true;
      await coordinator.syncPending();
      expect(client.receiptsTable, isEmpty);
      expect(client.receiptSelects, 0);
      expect(client.agentRunSelects, 0);

      client.failPhoto = false;
      await coordinator.syncPending();
      expect(client.receiptsTable.length, 1);
      expect(
        client.receiptsTable[obs.id]!['payload_hash'],
        'flutter-direct-sync',
      );
      expect(client.receiptSelects, 0);
      expect(client.agentRunSelects, 0);
      expect((await repo.findById(obs.id))!.syncStatus, SyncStatus.synced);
    });

    test('an identified duplicate receipt is kept as the same row', () async {
      final obs = createObs('obs-receipt-dup');
      await repo.save(obs);
      client.receiptsTable[obs.id] = {
        'observation_id': obs.id,
        'idempotency_key': obs.id,
        'payload_hash': 'flutter-direct-sync',
      };
      client.receiptInsertCode = '23505';
      client.receiptInsertMessage =
          'duplicate key value violates unique constraint "sync_receipts_identity"';
      client.receiptInsertDetails =
          'Key (observation_id, idempotency_key)=(${obs.id}, ${obs.id}) already exists.';

      await coordinator.syncPending();

      expect(client.receiptsTable.length, 1);
      expect(client.receiptSelects, 0);
      expect((await repo.findById(obs.id))!.syncStatus, SyncStatus.synced);
      expect(
        (await repo.findById(obs.id))!.mediaSyncStatus,
        MediaSyncStatus.uploaded,
      );
    });

    test('an unidentified receipt error does not count as success', () async {
      final obs = createObs('obs-receipt-other');
      await repo.save(obs);
      client.receiptInsertCode = '23505';
      client.receiptInsertMessage =
          'duplicate key value violates unique constraint "sync_receipts_pkey"';
      client.receiptInsertDetails = null;

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, isNot(SyncStatus.synced));
      expect(client.receiptsTable, isEmpty);
      expect(client.receiptSelects, 0);
      expect(client.mediaFilesTable.length, 1);
    });

    test('a denied agent_runs read is not performed', () async {
      final obs = createObs('obs-agent-runs');
      await repo.save(obs);
      client.rpcMetadataAccepted = true;

      await coordinator.syncPending();

      expect(client.agentRunSelects, 0);
      expect(client.receiptSelects, 0);
      expect((await repo.findById(obs.id))!.syncStatus, SyncStatus.synced);
      expect((await repo.findById(obs.id))!.mediaSyncStatus,
          MediaSyncStatus.uploaded);
    });

    test('a confirmed original is not uploaded again', () async {
      final obs = createObs('obs-confirmed-original');
      obs.mediaSyncStatus = MediaSyncStatus.originalUploaded;
      await repo.save(obs);
      client.originalStored = true;
      client.mediaFilesTable[obs.id] = {
        'id': stableOriginalMediaId(obs.id),
        'observation_id': obs.id,
        'bucket': 'observation-images',
        'storage_path': '${obs.id}/${stableOriginalMediaId(obs.id)}.webp',
        'media_type': 'image',
      };

      await coordinator.syncPending();

      expect(client.photoAttempts, 0);
      expect(client.originalUploadAttempts, 0);
      expect(client.mediaFilesTable.length, 1);
      expect(client.observationsTable.length, 1);
      expect(client.receiptsTable.length, 1);
      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, SyncStatus.synced);
      expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
    });

    test('a mismatched stored observation row is not fully synced', () async {
      final image =
          File('${Directory.systemTemp.path}/tariqmap-phasec2-row-other.jpg');
      await image.writeAsBytes(const [13]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = createObs('obs-row-other', imagePath: image.path);
      await repo.save(obs);
      client.observationsTable[obs.id] = {
        'id': obs.id,
        'capture_id': 'different-capture',
      };

      await coordinator.syncPending();

      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, isNot(SyncStatus.synced));
      expect(stored.mediaSyncStatus, isNot(MediaSyncStatus.uploaded));
      expect(queueSyncState(stored), isNot(QueueSyncState.fullySynced));
      expect(client.observationsTable[obs.id]!['capture_id'],
          'different-capture');
      expect(client.mediaFilesTable, isEmpty);
      expect(image.existsSync(), isTrue);
    });
  });

  group('Wi-Fi-only sync', () {
    late MemoryObservationRepository repo;
    late MockDetailedSyncClient client;
    late bool wifiOnly;
    late SyncNetworkType network;

    setUp(() {
      repo = MemoryObservationRepository();
      client = MockDetailedSyncClient();
      wifiOnly = true;
      network = SyncNetworkType.wifi;
    });

    SyncCoordinator coordinator() {
      return _testSync(
        repo,
        client,
        readSettings: () async => SyncSettings(
          wifiOnly: wifiOnly,
          retentionDays: 0,
        ),
        readNetwork: () async => network,
      );
    }

    Future<Observation> pendingObs(String id) async {
      final image = File('${Directory.systemTemp.path}/tariqmap-wifi-$id.jpg');
      await image.writeAsBytes(const [1, 2, 3]);
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final obs = Observation(
        id: id,
        captureId: 'cap_$id',
        imagePath: image.path,
        createdAt: DateTime.now(),
        latitude: 36.8,
        longitude: 10.1,
        agentResults: const [
          AgentResult(
            agent: 'road_damage',
            detections: [
              Detection(
                agent: 'road_damage',
                classCode: 'D40',
                confidence: 0.9,
                box: BoundingBox(x: 0, y: 0, width: 10, height: 10),
              ),
            ],
          ),
        ],
        actor: 'Municipality',
      );
      await repo.save(obs);
      return obs;
    }

    test('Wi-Fi allows automatic sync when Wi-Fi-only is on', () async {
      final obs = await pendingObs('wifi-ok');
      network = SyncNetworkType.wifi;
      final result = await coordinator().syncPending();
      expect(result.blocked, isFalse);
      expect(client.uploadCount, 1);
      expect((await repo.findById(obs.id))!.syncStatus, SyncStatus.synced);
      expect(File(obs.imagePath).existsSync(), isTrue);
    });

    test('mobile data blocks automatic sync when Wi-Fi-only is on', () async {
      final obs = await pendingObs('wifi-mobile');
      network = SyncNetworkType.mobile;
      final result = await coordinator().syncPending();
      expect(result.blocked, isTrue);
      expect(result.message, wifiOnlyBlockedMessage);
      expect(client.uploadCount, 0);
      final stored = await repo.findById(obs.id);
      expect(stored!.syncStatus, SyncStatus.pending);
      expect(stored.uploadAttempts, 0);
      expect(File(obs.imagePath).existsSync(), isTrue);
    });

    test('an unknown network blocks automatic sync when Wi-Fi-only is on',
        () async {
      final obs = await pendingObs('wifi-unknown');
      network = SyncNetworkType.unknown;
      final result = await coordinator().syncPending();
      expect(result.blocked, isTrue);
      expect(result.message, contains('Wi-Fi-only mode blocked this upload'));
      expect(client.uploadCount, 0);
      expect((await repo.findById(obs.id))!.syncStatus, SyncStatus.pending);
    });

    test('a throwing network reader is not treated as Wi-Fi', () async {
      final obs = await pendingObs('wifi-throw');
      final sync = _testSync(
        repo,
        client,
        readSettings: () async =>
            const SyncSettings(wifiOnly: true, retentionDays: 0),
        readNetwork: () async => throw StateError('radio unavailable'),
      );
      final result = await sync.syncPending();
      expect(result.blocked, isTrue);
      expect(client.uploadCount, 0);
      expect((await repo.findById(obs.id))!.syncStatus, SyncStatus.pending);
    });

    test('Wi-Fi-only off syncs on mobile without requiring Wi-Fi', () async {
      final obs = await pendingObs('wifi-off');
      wifiOnly = false;
      network = SyncNetworkType.mobile;
      final result = await coordinator().syncPending();
      expect(result.blocked, isFalse);
      expect(client.uploadCount, 1);
      expect((await repo.findById(obs.id))!.syncStatus, SyncStatus.synced);
    });

    test('Wi-Fi-only off syncs when the network type is unknown', () async {
      final obs = await pendingObs('wifi-off-unknown');
      wifiOnly = false;
      network = SyncNetworkType.unknown;
      final result = await coordinator().syncPending();
      expect(result.blocked, isFalse);
      expect(client.uploadCount, 1);
      expect((await repo.findById(obs.id))!.mediaSyncStatus,
          MediaSyncStatus.uploaded);
    });

    test('the next attempt reads the Wi-Fi-only setting again', () async {
      final obs = await pendingObs('wifi-reread');
      network = SyncNetworkType.mobile;
      final blocked = await coordinator().syncPending();
      expect(blocked.blocked, isTrue);
      expect(client.uploadCount, 0);

      wifiOnly = false;
      final allowed = await coordinator().syncPending();
      expect(allowed.blocked, isFalse);
      expect(client.uploadCount, 1);
      expect((await repo.findById(obs.id))!.syncStatus, SyncStatus.synced);
    });

    test('manual retry is blocked off Wi-Fi and allowed on Wi-Fi', () async {
      final obs = await pendingObs('wifi-manual');
      obs.syncStatus = SyncStatus.needsReview;
      obs.uploadAttempts = 5;
      obs.mediaSyncStatus = MediaSyncStatus.failed;
      await repo.save(obs);

      network = SyncNetworkType.mobile;
      final blocked = await coordinator().retryNeedsReview(obs.id);
      expect(blocked.blocked, isTrue);
      expect(blocked.message, wifiOnlyBlockedMessage);
      expect(client.uploadCount, 0);
      final still = await repo.findById(obs.id);
      expect(still!.syncStatus, SyncStatus.needsReview);
      expect(still.uploadAttempts, 5);
      expect(still.mediaSyncStatus, MediaSyncStatus.failed);
      expect(File(obs.imagePath).existsSync(), isTrue);

      network = SyncNetworkType.unknown;
      final unknown = await coordinator().retryNeedsReview(obs.id);
      expect(unknown.blocked, isTrue);
      expect(client.uploadCount, 0);
      expect((await repo.findById(obs.id))!.uploadAttempts, 5);

      network = SyncNetworkType.wifi;
      final allowed = await coordinator().retryNeedsReview(obs.id);
      expect(allowed.blocked, isFalse);
      expect(client.uploadCount, 1);
      final synced = await repo.findById(obs.id);
      expect(synced!.syncStatus, SyncStatus.synced);
      expect(synced.mediaSyncStatus, MediaSyncStatus.uploaded);
      expect(synced.uploadAttempts, 5);
      expect(File(obs.imagePath).existsSync(), isTrue);
    });
  });
}
