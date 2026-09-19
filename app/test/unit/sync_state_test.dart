import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';

class MockSyncClient implements ObservationSyncClient {
  int uploadCount = 0;
  bool shouldFail = false;
  List<Observation> uploaded = [];

  @override
  Future<void> upload(Observation observation, {required String idempotencyKey}) async {
    uploadCount++;
    if (shouldFail) {
      throw Exception('Mock network failure');
    }
    uploaded.add(observation);
  }
}

void main() {
  group('SyncCoordinator', () {
    late MemoryObservationRepository repo;
    late MockSyncClient client;
    late SyncCoordinator coordinator;

    setUp(() {
      repo = MemoryObservationRepository();
      client = MockSyncClient();
      // Set maxRetries to a small number for testing to avoid long tests
      coordinator = SyncCoordinator(repo, client, maxRetries: 2);
    });

    Observation createObs(String id) {
      return Observation(
        id: id,
        captureId: 'cap_$id',
        imagePath: '/tmp/$id.jpg',
        createdAt: DateTime.now(),
        latitude: 0,
        longitude: 0,
        agentResults: [],
        actor: 'TestActor',
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

    test('successful sync updates status to synced', () async {
      final obs = createObs('pending1');
      await repo.save(obs);

      await coordinator.syncPending();

      expect(client.uploadCount, 1);
      final updated = await repo.findById('pending1');
      expect(updated!.syncStatus, SyncStatus.synced);
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
  });
}
