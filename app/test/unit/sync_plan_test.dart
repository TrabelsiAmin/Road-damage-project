import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/sync_plan.dart';

void main() {
  test('stable ids do not change across a retry', () {
    final first = stableDetectionId('obs-1', 0, 0);
    final second = stableDetectionId('obs-1', 0, 0);
    expect(second, first);
    expect(stableAgentRunId('obs-1', 0, 'road_damage'),
        '0b7e22ee-2f0d-5c02-89b3-b81c7ff0608a');
    expect(first, 'b22059ac-91f0-5481-a0f0-827e38a79359');
  });

  test('a retry inserts only ids that are not already stored', () {
    final rows = [
      {'id': 'keep'},
      {'id': 'missing'},
    ];
    final missing = rowsMissing(rows, {'keep'});
    expect(missing.map((row) => row['id']), ['missing']);
  });

  test('synced requires observation, children, and media', () {
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: true,
        mediaReady: false,
        authOk: true,
        networkOk: true,
      ),
      isFalse,
    );
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: false,
        mediaReady: true,
        authOk: true,
        networkOk: true,
      ),
      isFalse,
    );
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: true,
        mediaReady: true,
        authOk: false,
        networkOk: true,
      ),
      isFalse,
    );
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: true,
        mediaReady: true,
        authOk: true,
        networkOk: false,
      ),
      isFalse,
    );
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: true,
        mediaReady: true,
        authOk: true,
        networkOk: true,
      ),
      isTrue,
    );
  });

  test('a successful RPC owns the receipt and does not prove media', () {
    final synced = parseSubmitObservationAck({
      'success': true,
      'status': 'synced',
      'observation_id': 'obs-1',
    });
    final already = parseSubmitObservationAck({
      'success': true,
      'status': 'already_synced',
      'observation_id': 'obs-1',
    });
    expect(synced.provesMedia, isFalse);
    expect(already.provesMedia, isFalse);
    expect(rpcOwnsMetadataReceipt(synced), isTrue);
    expect(rpcOwnsMetadataReceipt(already), isTrue);
    expect(rpcTransactionStoredChildren(synced), isTrue);
    expect(rpcTransactionStoredChildren(already), isFalse);
    expect(clientSelectsAgentRuns(), isFalse);
    expect(
      clientReceiptInsertWithoutRead(
        rpcCallSucceeded: true,
        observationStored: true,
        originalConfirmed: true,
        thumbnailStepFinished: true,
      ),
      isFalse,
    );
    expect(
      childIdsStoredByRpc(ack: synced, submittedIds: ['run-1', 'det-1']),
      {'run-1', 'det-1'},
    );
    expect(
      childIdsStoredByRpc(ack: already, submittedIds: ['run-1', 'det-1']),
      isEmpty,
    );
    final repaired = parseSubmitObservationAck({
      'success': true,
      'status': 'repaired',
      'observation_id': 'obs-1',
    });
    expect(repaired.provesMedia, isFalse);
    expect(rpcTransactionStoredChildren(repaired), isFalse);
    expect(
      childIdsStoredByRpc(ack: repaired, submittedIds: ['run-1']),
      isEmpty,
    );
  });

  test('a rejected RPC does not own a receipt or stored child ids', () {
    final rejected = parseSubmitObservationAck({'success': false});
    expect(rejected.callSucceeded, isFalse);
    expect(rejected.provesMedia, isFalse);
    expect(rpcOwnsMetadataReceipt(rejected), isFalse);
    expect(rpcTransactionStoredChildren(rejected), isFalse);
    expect(clientSelectsAgentRuns(), isFalse);
    expect(
      childIdsStoredByRpc(ack: rejected, submittedIds: ['run-1']),
      isEmpty,
    );
    expect(
      clientReceiptInsertWithoutRead(
        rpcCallSucceeded: false,
        observationStored: true,
        originalConfirmed: true,
        thumbnailStepFinished: true,
      ),
      isTrue,
    );
    expect(
      clientReceiptInsertWithoutRead(
        rpcCallSucceeded: false,
        observationStored: true,
        originalConfirmed: false,
        thumbnailStepFinished: true,
      ),
      isFalse,
    );
  });

  test('a receipt conflict counts only when both identity columns match', () {
    const identity = {
      'observation_id': 'obs-1',
      'idempotency_key': 'obs-1',
    };
    expect(
      duplicateKeyMatchesIdentity(
        identity: identity,
        code: '23505',
        message:
            'duplicate key value violates unique constraint "sync_receipts_identity"',
        details:
            'Key (observation_id, idempotency_key)=(obs-1, obs-1) already exists.',
      ),
      isTrue,
    );
    expect(
      duplicateKeyMatchesIdentity(
        identity: identity,
        code: '23505',
        message: 'duplicate key value violates unique constraint "sync_receipts_pkey"',
        details: 'Key (observation_id)=(obs-1) already exists.',
      ),
      isFalse,
    );
    expect(
      duplicateKeyMatchesIdentity(
        identity: identity,
        code: '23505',
        message: 'duplicate key value violates unique constraint "sync_receipts_pkey"',
        details: null,
      ),
      isFalse,
    );
    expect(
      duplicateKeyMatchesIdentity(
        identity: identity,
        code: '23502',
        message: 'null value in column "payload_hash" violates not-null constraint',
        details: null,
      ),
      isFalse,
    );
    expect(
      duplicateKeyMatchesIdentity(
        identity: identity,
        code: '42501',
        message: 'permission denied for table sync_receipts',
        details: null,
      ),
      isFalse,
    );
    expect(
      duplicateKeyMatchesIdentity(
        identity: {
          'id': 'run-1',
          'observation_id': 'obs-1',
          'agent': 'road_damage',
        },
        code: '23505',
        message: 'duplicate key value violates unique constraint "agent_runs_pkey"',
        details: 'Key (id)=(run-1) already exists.',
      ),
      isFalse,
    );
    expect(
      duplicateKeyMatchesIdentity(
        identity: {
          'id': 'run-1',
          'observation_id': 'obs-1',
          'agent': 'road_damage',
        },
        code: '23505',
        message: 'duplicate key value violates unique constraint "agent_runs_identity"',
        details:
            'Key (id, observation_id, agent)=(run-1, obs-1, road_damage) already exists.',
      ),
      isTrue,
    );
  });

  test('already_synced repairs only detections that are not stored', () {
    final run = {
      'id': 'run-1',
      'observation_id': 'obs-1',
      'agent': 'road_damage',
    };
    final emptyRun = {
      'id': 'run-0',
      'observation_id': 'obs-1',
      'agent': 'road_damage',
    };
    final kept = {
      'id': 'det-kept',
      'observation_id': 'obs-1',
      'class_code': 'D00',
      'agent_run_id': 'run-1',
    };
    final missing = {
      'id': 'det-missing',
      'observation_id': 'obs-1',
      'class_code': 'D40',
      'agent_run_id': 'run-1',
    };
    final matched = matchedDetectionIds(
      storedRows: [kept],
      submitted: [kept, missing],
    );
    expect(matched, {'det-kept'});
    final repair = planChildRepair(
      trustTransaction: false,
      insertZeroDetectionRuns: false,
      agentRuns: [run, emptyRun],
      detections: [kept, missing],
      matchedDetectionIds: matched,
    );
    expect(repair.detectionsToInsert.map((row) => row['id']), ['det-missing']);
    expect(repair.agentRunsToInsert.map((row) => row['id']), ['run-1']);
  });

  test('a synced transaction does not insert children again', () {
    final repair = planChildRepair(
      trustTransaction: true,
      insertZeroDetectionRuns: false,
      agentRuns: [
        {'id': 'run-1', 'observation_id': 'obs-1', 'agent': 'road_damage'},
      ],
      detections: [
        {
          'id': 'det-1',
          'observation_id': 'obs-1',
          'class_code': 'D00',
          'agent_run_id': 'run-1',
        },
      ],
      matchedDetectionIds: const {},
    );
    expect(repair.agentRunsToInsert, isEmpty);
    expect(repair.detectionsToInsert, isEmpty);
  });

  test('direct insert still writes a run that has no detections', () {
    final repair = planChildRepair(
      trustTransaction: false,
      insertZeroDetectionRuns: true,
      agentRuns: [
        {'id': 'run-0', 'observation_id': 'obs-1', 'agent': 'road_damage'},
      ],
      detections: const [],
      matchedDetectionIds: const {},
    );
    expect(repair.agentRunsToInsert.single['id'], 'run-0');
    expect(repair.detectionsToInsert, isEmpty);
  });

  test('already_synced does not retry a run that has no detections', () {
    final repair = planChildRepair(
      trustTransaction: false,
      insertZeroDetectionRuns: false,
      agentRuns: [
        {'id': 'run-0', 'observation_id': 'obs-1', 'agent': 'road_damage'},
      ],
      detections: const [],
      matchedDetectionIds: const {},
    );
    expect(repair.agentRunsToInsert, isEmpty);
    expect(repair.detectionsToInsert, isEmpty);
  });

  test('a different stored class is not treated as the submitted detection', () {
    final submitted = {
      'id': 'det-1',
      'observation_id': 'obs-1',
      'class_code': 'D40',
      'agent_run_id': 'run-1',
    };
    final matched = matchedDetectionIds(
      storedRows: [
        {
          'id': 'det-1',
          'observation_id': 'obs-1',
          'class_code': 'D00',
          'agent_run_id': 'run-1',
        },
      ],
      submitted: [submitted],
    );
    expect(matched, isEmpty);
    expect(
      storedLocationMatches(
        stored: {
          'observation_id': 'obs-1',
          'latitude': 36.8,
          'longitude': 10.1,
        },
        submitted: {
          'observation_id': 'obs-1',
          'latitude': 36.80,
          'longitude': 10.10,
        },
      ),
      isTrue,
    );
  });

  test('a client receipt waits until the original and thumbnail step finish', () {
    expect(
      clientReceiptWriteAllowed(
        observationStored: true,
        originalConfirmed: false,
        thumbnailStepFinished: false,
      ),
      isFalse,
    );
    expect(
      clientReceiptWriteAllowed(
        observationStored: true,
        originalConfirmed: true,
        thumbnailStepFinished: false,
      ),
      isFalse,
    );
    expect(
      clientReceiptWriteAllowed(
        observationStored: false,
        originalConfirmed: true,
        thumbnailStepFinished: true,
      ),
      isFalse,
    );
    expect(
      clientReceiptWriteAllowed(
        observationStored: true,
        originalConfirmed: true,
        thumbnailStepFinished: true,
      ),
      isTrue,
    );
  });

  test('a failed photo is uploaded again without new child ids', () {
    const agents = [
      (index: 0, agent: 'road_damage', detectionCount: 1),
    ];
    final first = planRemoteSync(
      observationId: 'obs-1',
      agents: agents,
      mediaSyncStatus: MediaSyncStatus.pending,
      remoteOriginalPresent: false,
      existingAgentRunIds: const {},
      existingDetectionIds: const {},
    );
    expect(first.uploadPhoto, isTrue);
    expect(first.agentRunIdsToInsert, [stableAgentRunId('obs-1', 0, 'road_damage')]);
    expect(first.detectionIdsToInsert, [stableDetectionId('obs-1', 0, 0)]);
    expect(first.originalMediaId, stableOriginalMediaId('obs-1'));

    final retry = planRemoteSync(
      observationId: 'obs-1',
      agents: agents,
      mediaSyncStatus: MediaSyncStatus.failed,
      remoteOriginalPresent: false,
      existingAgentRunIds: first.agentRunIdsToInsert.toSet(),
      existingDetectionIds: first.detectionIdsToInsert.toSet(),
    );
    expect(retry.agentRunIdsToInsert, isEmpty);
    expect(retry.detectionIdsToInsert, isEmpty);
    expect(retry.uploadPhoto, isTrue);
    expect(retry.originalMediaId, first.originalMediaId);
  });

  test('an existing observation row does not skip a missing photo', () {
    expect(
      photoUploadRequired(
        mediaSyncStatus: MediaSyncStatus.failed,
        remoteOriginalPresent: false,
      ),
      isTrue,
    );
    expect(
      photoUploadRequired(
        mediaSyncStatus: MediaSyncStatus.originalUploaded,
        remoteOriginalPresent: true,
      ),
      isFalse,
    );
    expect(
      photoUploadRequired(
        mediaSyncStatus: MediaSyncStatus.failed,
        remoteOriginalPresent: true,
      ),
      isFalse,
    );
    expect(
      photoUploadRequired(
        mediaSyncStatus: MediaSyncStatus.pending,
        remoteOriginalPresent: false,
      ),
      isTrue,
    );
    expect(
      photoUploadRequired(
        mediaSyncStatus: MediaSyncStatus.uploaded,
        remoteOriginalPresent: true,
      ),
      isFalse,
    );
    expect(
      photoUploadRequired(
        mediaSyncStatus: MediaSyncStatus.uploaded,
        remoteOriginalPresent: false,
      ),
      isTrue,
    );
  });

  test('queue messages keep a failed photo out of the fully synced state', () {
    final pending = _obs(SyncStatus.pending, MediaSyncStatus.pending);
    final photoFailed = _obs(SyncStatus.failed, MediaSyncStatus.failed);
    final synced = _obs(SyncStatus.synced, MediaSyncStatus.uploaded);
    final dishonest = _obs(SyncStatus.synced, MediaSyncStatus.failed);
    final review = _obs(SyncStatus.needsReview, MediaSyncStatus.failed);

    expect(queueStatusMessage(pending), 'Observation not yet synced.');
    expect(queueStatusMessage(photoFailed),
        contains('Metadata synced, but the photo upload failed'));
    expect(queueSyncState(photoFailed), isNot(QueueSyncState.fullySynced));
    expect(queueStatusMessage(synced), 'Fully synced, including the photo.');
    expect(queueSyncState(dishonest), QueueSyncState.metadataSyncedPhotoFailed);
    expect(queueStatusMessage(review),
        contains('Manual review after retry exhaustion'));
  });

  test('storage 409 matches only the expected bucket and object path', () async {
    const bucket = 'observation-images';
    const path = 'obs-1/original.webp';
    expect(
      storageConflictMatchesIntendedObject(
        expectedBucket: bucket,
        expectedPath: path,
        confirmedBucket: bucket,
        confirmedPath: path,
      ),
      isTrue,
    );
    await acceptSameObjectConflict(
      expectedBucket: bucket,
      expectedPath: path,
      confirm: () async =>
          const ConfirmedStorageObject(bucket: bucket, path: path),
    );

    expect(
      storageConflictMatchesIntendedObject(
        expectedBucket: bucket,
        expectedPath: path,
        confirmedBucket: bucket,
        confirmedPath: 'obs-1/other.webp',
      ),
      isFalse,
    );
    expect(
      storageConflictMatchesIntendedObject(
        expectedBucket: bucket,
        expectedPath: path,
        confirmedBucket: 'other-bucket',
        confirmedPath: path,
      ),
      isFalse,
    );
    expect(
      storageConflictMatchesIntendedObject(
        expectedBucket: bucket,
        expectedPath: path,
      ),
      isFalse,
    );
    await expectLater(
      acceptSameObjectConflict(
        expectedBucket: bucket,
        expectedPath: path,
        confirm: () async => const ConfirmedStorageObject(
          bucket: bucket,
          path: 'obs-1/other.webp',
        ),
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      acceptSameObjectConflict(
        expectedBucket: bucket,
        expectedPath: path,
        confirm: () async => null,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('every upload path accepts only a confirmed same object', () {
    const observationId = 'obs-upload-paths';
    final paths = <String, ({String bucket, String path})>{
      'ApiClient original': (
        bucket: 'observation-images',
        path: originalObjectPath(observationId, 'webp'),
      ),
      'ApiClient public thumbnail': (
        bucket: 'public-photos',
        path: publicThumbnailObjectPath(observationId),
      ),
      'SupabaseService.uploadObservationImage': (
        bucket: 'observation-images',
        path: originalObjectPath(observationId, 'webp'),
      ),
      'SupabaseService.uploadObservationImageBytes': (
        bucket: 'observation-images',
        path: originalObjectPath(observationId, 'webp'),
      ),
      'SupabaseService.uploadPublicThumbnail': (
        bucket: 'public-photos',
        path: publicThumbnailObjectPath(observationId),
      ),
    };

    for (final entry in paths.entries) {
      final same = decideRemoteConflict(RemoteConflictQuery.storage(
        expectedBucket: entry.value.bucket,
        expectedPath: entry.value.path,
        confirmedBucket: entry.value.bucket,
        confirmedPath: entry.value.path,
      ));
      final differentPath = decideRemoteConflict(RemoteConflictQuery.storage(
        expectedBucket: entry.value.bucket,
        expectedPath: entry.value.path,
        confirmedBucket: entry.value.bucket,
        confirmedPath: 'other-obs/other.webp',
      ));
      final differentBucket = decideRemoteConflict(RemoteConflictQuery.storage(
        expectedBucket: entry.value.bucket,
        expectedPath: entry.value.path,
        confirmedBucket: 'other-bucket',
        confirmedPath: entry.value.path,
      ));
      final unconfirmed = decideRemoteConflict(RemoteConflictQuery.storage(
        expectedBucket: entry.value.bucket,
        expectedPath: entry.value.path,
      ));
      expect(same, RemoteConflictDecision.accept, reason: entry.key);
      expect(differentPath, RemoteConflictDecision.reject, reason: entry.key);
      expect(differentBucket, RemoteConflictDecision.reject, reason: entry.key);
      expect(unconfirmed, RemoteConflictDecision.reject, reason: entry.key);
    }
  });

  test('unique conflicts accept only the same stored identity', () {
    const childId = 'child-1';
    const observationId = 'obs-1';
    final cases = <String, Map<String, Object?>>{
      'observations': {'id': observationId, 'capture_id': 'cap-1'},
      'locations': {
        'observation_id': observationId,
        'latitude': 36.8,
        'longitude': 10.1,
      },
      'agent_runs': {
        'id': childId,
        'observation_id': observationId,
        'agent': 'road_damage',
      },
      'detections': {
        'id': childId,
        'observation_id': observationId,
        'class_code': 'D10',
        'agent_run_id': 'run-1',
      },
      'media_files': {
        'id': childId,
        'observation_id': observationId,
        'bucket': 'observation-images',
        'storage_path': originalObjectPath(observationId, 'webp'),
        'media_type': 'image',
      },
      'sync_receipts': {
        'observation_id': observationId,
        'idempotency_key': observationId,
      },
    };

    for (final entry in cases.entries) {
      final expected = identityFieldsForTable(entry.key, entry.value);
      final child = entry.value['id']?.toString();
      final observation = entry.key == 'observations'
          ? observationId
          : entry.value['observation_id']?.toString();
      expect(
        decideRemoteConflict(RemoteConflictQuery.row(
          childId: child,
          observationId: observation,
          expectedIdentity: expected,
          storedRow: expected,
        )),
        RemoteConflictDecision.accept,
        reason: entry.key,
      );
      final mismatched = Map<String, Object?>.from(expected);
      final changedKey = mismatched.keys.first;
      mismatched[changedKey] = 'different-value';
      expect(
        decideRemoteConflict(RemoteConflictQuery.row(
          childId: child,
          observationId: observation,
          expectedIdentity: expected,
          storedRow: mismatched,
        )),
        RemoteConflictDecision.reject,
        reason: entry.key,
      );
      expect(
        decideRemoteConflict(RemoteConflictQuery.row(
          childId: child,
          observationId: observation,
          expectedIdentity: expected,
          storedRow: null,
        )),
        RemoteConflictDecision.reject,
        reason: '${entry.key} unconfirmed',
      );
    }
  });

  test('a listed storage name confirms only that exact object', () {
    const bucket = 'observation-images';
    const path = 'obs-1/file.webp';
    expect(
      confirmedObjectFromListing(
        bucket: bucket,
        path: path,
        listedNames: const ['file.webp'],
      ),
      isNotNull,
    );
    expect(
      confirmedObjectFromListing(
        bucket: bucket,
        path: path,
        listedNames: const ['other.webp'],
      ),
      isNull,
    );
    expect(
      confirmedObjectFromListing(
        bucket: bucket,
        path: path,
        listedNames: const ['file.webp', 'file.webp'],
      ),
      isNull,
    );
  });

  test('both upload clients call decideRemoteConflict', () {
    final api = File('lib/data/remote/api_client.dart').readAsStringSync();
    final service =
        File('lib/data/remote/supabase_service.dart').readAsStringSync();
    expect(api, contains('decideRemoteConflict('));
    expect(service, contains('decideRemoteConflict('));
    expect(api, isNot(contains('409/duplicate conflict treated as success')));
    expect(service, isNot(contains('treated as success')));
  });

  test('sync errors do not keep a JWT-shaped token', () {
    const leaked =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidGVzdCJ9.c2lnbmF0dXJl';
    expect(redactSecrets('failed $leaked'), isNot(contains('eyJ')));
  });
}

Observation _obs(SyncStatus sync, MediaSyncStatus media) {
  return Observation(
    id: 'obs-1',
    captureId: 'cap',
    imagePath: '/tmp/missing-photo.jpg',
    createdAt: DateTime.utc(2026, 11, 7),
    latitude: 36.8,
    longitude: 10.1,
    agentResults: const <AgentResult>[],
    actor: 'Municipality',
    syncStatus: sync,
    mediaSyncStatus: media,
  );
}
