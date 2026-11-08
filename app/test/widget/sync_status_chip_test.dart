import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/widgets/sync_status_chip.dart';

Observation _observation({
  required SyncStatus syncStatus,
  required MediaSyncStatus media,
  String? syncError,
}) {
  return Observation(
    id: 'obs-chip',
    captureId: 'cap',
    imagePath: '/tmp/missing.jpg',
    createdAt: DateTime.utc(2026, 1, 1),
    latitude: 36.8,
    longitude: 10.1,
    actor: 'Municipality',
    syncStatus: syncStatus,
    mediaSyncStatus: media,
    syncError: syncError,
    agentResults: const [
      AgentResult(
        agent: 'road_damage',
        detections: [
          Detection(
            agent: 'road_damage',
            classCode: 'D10',
            confidence: 0.5,
            box: BoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          ),
        ],
      ),
    ],
  );
}

Future<String> _pump(
  WidgetTester tester,
  Observation observation, {
  bool manualRetryInProgress = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ObservationSyncChip(
        observation: observation,
        manualRetryInProgress: manualRetryInProgress,
      ),
    ),
  ));
  expect(find.byType(ObservationSyncChip), findsOneWidget);
  final semantics = tester.getSemantics(find.byType(ObservationSyncChip));
  return semantics.label;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('queue labels stay distinct for the settled states', (tester) async {
    final handle = tester.ensureSemantics();

    expect(
      await _pump(
        tester,
        _observation(syncStatus: SyncStatus.pending, media: MediaSyncStatus.pending),
      ),
      'NOT SYNCED. Observation not yet synced.',
    );
    expect(find.text('NOT SYNCED'), findsOneWidget);

    expect(
      await _pump(
        tester,
        _observation(syncStatus: SyncStatus.failed, media: MediaSyncStatus.pending),
      ),
      'FAILED. Observation not yet synced.',
    );
    expect(find.text('FAILED'), findsOneWidget);
    expect(find.text('PHOTO FAILED'), findsNothing);

    expect(
      await _pump(
        tester,
        _observation(syncStatus: SyncStatus.synced, media: MediaSyncStatus.failed),
      ),
      contains('PHOTO FAILED. Metadata synced, but the photo upload failed'),
    );
    expect(find.text('PHOTO FAILED'), findsOneWidget);

    expect(
      await _pump(
        tester,
        _observation(
          syncStatus: SyncStatus.synced,
          media: MediaSyncStatus.originalUploaded,
        ),
      ),
      contains('THUMBNAIL FAILED. Original photo is stored'),
    );
    expect(find.text('THUMBNAIL FAILED'), findsOneWidget);

    expect(
      await _pump(
        tester,
        _observation(syncStatus: SyncStatus.synced, media: MediaSyncStatus.uploaded),
      ),
      'SYNCED. Fully synced, including the photo.',
    );
    expect(find.text('SYNCED'), findsOneWidget);

    expect(
      await _pump(
        tester,
        _observation(
          syncStatus: SyncStatus.needsReview,
          media: MediaSyncStatus.pending,
        ),
      ),
      contains('NEEDS REVIEW. Manual review after retry exhaustion'),
    );
    expect(find.text('NEEDS REVIEW'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('conflicting and transitional states do not call a photo unsynced early',
      (tester) async {
    final handle = tester.ensureSemantics();

    final pendingPhoto = await _pump(
      tester,
      _observation(syncStatus: SyncStatus.pending, media: MediaSyncStatus.failed),
    );
    expect(find.text('NOT SYNCED'), findsOneWidget);
    expect(find.text('PHOTO FAILED'), findsNothing);
    expect(pendingPhoto, 'NOT SYNCED. Observation not yet synced.');
    expect(pendingPhoto, isNot(contains('Metadata synced')));
    expect(pendingPhoto, isNot(contains('photo upload failed')));

    final uploadingPhoto = await _pump(
      tester,
      _observation(syncStatus: SyncStatus.uploading, media: MediaSyncStatus.failed),
    );
    expect(find.text('UPLOADING'), findsOneWidget);
    expect(uploadingPhoto, 'UPLOADING. Observation not yet synced.');
    expect(uploadingPhoto, isNot(contains('photo upload failed')));

    final uploading = await _pump(
      tester,
      _observation(syncStatus: SyncStatus.uploading, media: MediaSyncStatus.pending),
    );
    expect(find.text('UPLOADING'), findsOneWidget);
    expect(uploading, 'UPLOADING. Observation not yet synced.');

    final metadataFailed = await _pump(
      tester,
      _observation(syncStatus: SyncStatus.failed, media: MediaSyncStatus.uploading),
    );
    expect(find.text('FAILED'), findsOneWidget);
    expect(metadataFailed, 'FAILED. Observation not yet synced.');
    expect(metadataFailed, isNot(contains('PHOTO FAILED')));

    final photoFailed = await _pump(
      tester,
      _observation(syncStatus: SyncStatus.failed, media: MediaSyncStatus.failed),
    );
    expect(find.text('PHOTO FAILED'), findsOneWidget);
    expect(photoFailed, contains('Metadata synced, but the photo upload failed'));

    final retrying = await _pump(
      tester,
      _observation(
        syncStatus: SyncStatus.uploading,
        media: MediaSyncStatus.failed,
        syncError: 'Manual retry in progress',
      ),
      manualRetryInProgress: true,
    );
    expect(find.text('RETRYING'), findsOneWidget);
    expect(retrying, 'RETRYING. Manual retry in progress.');
    expect(retrying, isNot(contains('PHOTO FAILED')));

    handle.dispose();
  });
}
