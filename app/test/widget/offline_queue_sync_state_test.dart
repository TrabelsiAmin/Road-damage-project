import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';
import 'package:tariqmap/services/sync_policy.dart';
import 'package:tariqmap/screens/offline_queue_screen.dart';

Observation _obs({
  required String id,
  required SyncStatus syncStatus,
  required MediaSyncStatus mediaSyncStatus,
}) {
  return Observation(
    id: id,
    captureId: 'cap-$id',
    imagePath: '/tmp/tariqmap-queue-missing-$id.jpg',
    createdAt: DateTime.utc(2026, 11, 7, 12),
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
    syncStatus: syncStatus,
    mediaSyncStatus: mediaSyncStatus,
  );
}

class _RecoveringClient implements ObservationSyncClient {
  int photoAttempts = 0;
  Completer<void>? gate;

  @override
  Future<void> upload(
    Observation observation, {
    required String idempotencyKey,
    SyncCancelToken? cancelToken,
    ObservationRepository? repository,
  }) async {
    photoAttempts++;
    final pending = gate;
    if (pending != null) await pending.future;
    await repository?.updateMediaSyncStatus(
        observation.id, MediaSyncStatus.uploaded);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('queue distinguishes unsynced, photo failure, full sync, and review',
      (tester) async {
    final repo = MemoryObservationRepository();
    await repo.save(_obs(
      id: 'pending',
      syncStatus: SyncStatus.pending,
      mediaSyncStatus: MediaSyncStatus.pending,
    ));
    await repo.save(_obs(
      id: 'photo',
      syncStatus: SyncStatus.failed,
      mediaSyncStatus: MediaSyncStatus.failed,
    ));
    await repo.save(_obs(
      id: 'done',
      syncStatus: SyncStatus.synced,
      mediaSyncStatus: MediaSyncStatus.uploaded,
    ));
    await repo.save(_obs(
      id: 'review',
      syncStatus: SyncStatus.needsReview,
      mediaSyncStatus: MediaSyncStatus.failed,
    ));

    await tester.pumpWidget(MaterialApp(
      home: OfflineQueueScreen(
        repository: repo,
        onSync: ({cancelToken}) async => const SyncResult(
          uploadedCount: 0,
          totalCount: 0,
          cancelled: false,
          message: 'Sync complete: 0 of 0 uploaded',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Observation not yet synced.'), findsOneWidget);

    await tester.tap(find.textContaining('Failed ('));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Metadata synced, but the photo upload failed'),
      findsWidgets,
    );
    expect(
      find.textContaining('Manual review after retry exhaustion'),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('Synced ('));
    await tester.pumpAndSettle();
    expect(find.text('Fully synced, including the photo.'), findsOneWidget);

    await tester.tap(find.textContaining('Failed ('));
    await tester.pumpAndSettle();

    final photoCard = find.byKey(const ValueKey('queue-card-photo'));
    expect(
      find.descendant(
        of: photoCard,
        matching: find.text('Fully synced, including the photo.'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: photoCard,
        matching: find.textContaining(
          'Metadata synced, but the photo upload failed',
        ),
      ),
      findsOneWidget,
    );

    final reviewCard = find.byKey(const ValueKey('queue-card-review'));
    expect(
      find.descendant(
        of: reviewCard,
        matching: find.textContaining('Manual review after retry exhaustion'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('retrying a failed photo shows the fully synced state',
      (tester) async {
    final repo = MemoryObservationRepository();
    final client = _RecoveringClient();
    final coordinator = SyncCoordinator(
      repo,
      client,
      maxRetries: 5,
      readSettings: () async =>
          const SyncSettings(wifiOnly: false, retentionDays: 0),
      readNetwork: () async => SyncNetworkType.wifi,
    );
    await repo.save(_obs(
      id: 'photo',
      syncStatus: SyncStatus.failed,
      mediaSyncStatus: MediaSyncStatus.failed,
    ));

    await tester.pumpWidget(MaterialApp(
      home: OfflineQueueScreen(
        repository: repo,
        onSync: ({cancelToken}) =>
            coordinator.syncPending(cancelToken: cancelToken),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Failed ('));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Metadata synced, but the photo upload failed'),
      findsOneWidget,
    );
    expect(find.text('Fully synced, including the photo.'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Synced ('));
    await tester.pumpAndSettle();

    final stored = await repo.findById('photo');
    expect(client.photoAttempts, 1);
    expect(stored!.syncStatus, SyncStatus.synced);
    expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
    expect(find.text('Fully synced, including the photo.'), findsOneWidget);
    expect(
      find.textContaining('Metadata synced, but the photo upload failed'),
      findsNothing,
    );
  });

  testWidgets('manual retry shows progress, then full sync', (tester) async {
    final repo = MemoryObservationRepository();
    final client = _RecoveringClient();
    final gate = Completer<void>();
    client.gate = gate;
    final coordinator = SyncCoordinator(
      repo,
      client,
      maxRetries: 5,
      readSettings: () async =>
          const SyncSettings(wifiOnly: false, retentionDays: 0),
      readNetwork: () async => SyncNetworkType.wifi,
    );
    final obs = _obs(
      id: 'review',
      syncStatus: SyncStatus.needsReview,
      mediaSyncStatus: MediaSyncStatus.failed,
    );
    obs.uploadAttempts = 5;
    await repo.save(obs);

    await tester.pumpWidget(MaterialApp(
      home: OfflineQueueScreen(
        repository: repo,
        onSync: ({cancelToken}) =>
            coordinator.syncPending(cancelToken: cancelToken),
        onManualRetry: (id, {cancelToken}) =>
            coordinator.retryNeedsReview(id, cancelToken: cancelToken),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Failed ('));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Manual review after retry exhaustion'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry once'));
    await tester.pump();
    expect(find.text('Manual retry in progress.'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Synced ('));
    await tester.pumpAndSettle();

    final stored = await repo.findById('review');
    expect(client.photoAttempts, 1);
    expect(stored!.syncStatus, SyncStatus.synced);
    expect(stored.mediaSyncStatus, MediaSyncStatus.uploaded);
    expect(stored.uploadAttempts, 5);
    expect(find.text('Fully synced, including the photo.'), findsOneWidget);
    expect(find.text('Manual retry in progress.'), findsNothing);
  });

  testWidgets('Wi-Fi-only block is explained on the queue', (tester) async {
    final repo = MemoryObservationRepository();
    await repo.save(_obs(
      id: 'held',
      syncStatus: SyncStatus.needsReview,
      mediaSyncStatus: MediaSyncStatus.failed,
    ));

    await tester.pumpWidget(MaterialApp(
      home: OfflineQueueScreen(
        repository: repo,
        onSync: ({cancelToken}) async => const SyncResult(
          uploadedCount: 0,
          totalCount: 1,
          cancelled: false,
          blocked: true,
          message: wifiOnlyBlockedMessage,
        ),
        onManualRetry: (id, {cancelToken}) async => const SyncResult(
          uploadedCount: 0,
          totalCount: 1,
          cancelled: false,
          blocked: true,
          message: wifiOnlyBlockedMessage,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Failed ('));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry once'));
    await tester.pumpAndSettle();

    expect(find.text(wifiOnlyBlockedMessage), findsWidgets);
    expect(find.text('Fully synced, including the photo.'), findsNothing);
    final stored = await repo.findById('held');
    expect(stored!.syncStatus, SyncStatus.needsReview);
  });
}
