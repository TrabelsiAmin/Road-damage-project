import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';

class MockDetailedSyncClient implements ObservationSyncClient {
  int uploadCount = 0;
  bool shouldFail = false;
  List<Observation> uploaded = [];

  // Simulated backend database tables to test idempotency and duplicate prevention
  final Map<String, Map<String, dynamic>> observationsTable = {};
  final Map<String, Map<String, dynamic>> locationsTable = {};
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
  }) async {
    uploadCount++;
    if (shouldFail) {
      throw Exception('Mock network failure');
    }

    cancelToken?.throwIfCancelled();
    onBeforeObservationRow?.call(observation, cancelToken);
    cancelToken?.throwIfCancelled();

    // 1. Observations row (idempotent: ignore if already exists)
    if (!observationsTable.containsKey(observation.id)) {
      observationsTable[observation.id] = {
        'id': observation.id,
        'capture_id': observation.captureId,
      };
    }

    // Hook to simulate cancel mid-observation after partial row insertion
    cancelToken?.throwIfCancelled();
    onMidObservation?.call(observation, cancelToken);
    cancelToken?.throwIfCancelled();

    // 2. Locations row
    if (!locationsTable.containsKey(observation.id)) {
      locationsTable[observation.id] = {
        'observation_id': observation.id,
        'lat': observation.latitude,
        'lng': observation.longitude,
      };
    }

    // 3. Detections
    for (final r in observation.agentResults) {
      for (final d in r.detections) {
        final detKey = '${observation.id}_${d.classCode}';
        if (!detectionsTable.containsKey(detKey)) {
          detectionsTable[detKey] = {
            'observation_id': observation.id,
            'class': d.classCode,
          };
        }
      }
    }

    // 4. Image upload step
    cancelToken?.throwIfCancelled();
    onImageUpload?.call(observation, cancelToken);
    cancelToken?.throwIfCancelled();

    if (!mediaFilesTable.containsKey(observation.id)) {
      mediaFilesTable[observation.id] = {
        'observation_id': observation.id,
        'storage_path': '${observation.id}/image.webp',
      };
    }

    // 5. Sync receipt
    cancelToken?.throwIfCancelled();
    if (!receiptsTable.containsKey(idempotencyKey)) {
      receiptsTable[idempotencyKey] = {
        'observation_id': observation.id,
        'idempotency_key': idempotencyKey,
      };
    }

    uploaded.add(observation);
  }
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
      coordinator = SyncCoordinator(repo, client, maxRetries: 2);
    });

    Observation createObs(String id, {List<Detection>? detections}) {
      return Observation(
        id: id,
        captureId: 'cap_$id',
        imagePath: '/tmp/$id.jpg',
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
      expect(item2!.syncStatus, equals(SyncStatus.synced));
      expect(item3!.syncStatus, equals(SyncStatus.synced));
    });
  });
}
