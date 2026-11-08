import 'package:uuid/uuid.dart';
import '../models/observation.dart';

/// Stable child ids for one local observation.
///
/// The same strings are used by the Python backend planner. A retry inserts
/// a row only when that id is absent. Existing rows are not deleted.
const _uuid = Uuid();

String stableAgentRunId(String observationId, int index, String agent) =>
    _uuid.v5(Namespace.url.value, '$observationId:agent:$index:$agent');

String stableDetectionId(String observationId, int agentIndex, int detectionIndex) =>
    _uuid.v5(Namespace.url.value, '$observationId:det:$agentIndex:$detectionIndex');

String stableOriginalMediaId(String observationId) =>
    _uuid.v5(Namespace.url.value, '$observationId:original');

String stableThumbnailObjectId(String observationId) =>
    _uuid.v5(Namespace.url.value, observationId);

String stableThumbnailMediaId(String observationId) =>
    _uuid.v5(Namespace.url.value, '$observationId:thumbnail');

String stableSyncReceiptKey(String observationId) =>
    _uuid.v5(Namespace.url.value, '$observationId:receipt');

/// Object path for this observation's original media UUID.
String originalObjectPath(String observationId, String extension) =>
    '$observationId/${stableOriginalMediaId(observationId)}.$extension';

/// Object path for this observation's public thumbnail UUID.
String publicThumbnailObjectPath(String observationId) =>
    '$observationId/${stableThumbnailObjectId(observationId)}.webp';

/// One agent result, in stored order, used to rebuild the same child ids.
typedef SyncAgentSlice = ({int index, String agent, int detectionCount});

class RemoteSyncPlan {
  const RemoteSyncPlan({
    required this.agentRunIdsToInsert,
    required this.detectionIdsToInsert,
    required this.uploadPhoto,
    required this.retryThumbnailOnly,
    required this.originalMediaId,
  });

  final List<String> agentRunIdsToInsert;
  final List<String> detectionIdsToInsert;

  /// False when the original object is already confirmed at its stable path.
  final bool uploadPhoto;

  /// Original is confirmed. Finish the public thumbnail without sending the original again.
  final bool retryThumbnailOnly;
  final String originalMediaId;
}

class ConfirmedStorageObject {
  const ConfirmedStorageObject({required this.bucket, required this.path});

  final String bucket;
  final String path;
}

/// Child ids already stored are left out. The photo decision does not depend
/// on whether the observation row itself already exists.
RemoteSyncPlan planRemoteSync({
  required String observationId,
  required List<SyncAgentSlice> agents,
  required MediaSyncStatus mediaSyncStatus,
  required bool remoteOriginalPresent,
  required Set<String> existingAgentRunIds,
  required Set<String> existingDetectionIds,
}) {
  final runIds = <String>[];
  final detectionIds = <String>[];
  for (final agent in agents) {
    final runId = stableAgentRunId(observationId, agent.index, agent.agent);
    if (!existingAgentRunIds.contains(runId)) runIds.add(runId);
    for (var detectionIndex = 0;
        detectionIndex < agent.detectionCount;
        detectionIndex++) {
      final detectionId =
          stableDetectionId(observationId, agent.index, detectionIndex);
      if (!existingDetectionIds.contains(detectionId)) {
        detectionIds.add(detectionId);
      }
    }
  }
  final uploadPhoto = photoUploadRequired(
    mediaSyncStatus: mediaSyncStatus,
    remoteOriginalPresent: remoteOriginalPresent,
  );
  return RemoteSyncPlan(
    agentRunIdsToInsert: runIds,
    detectionIdsToInsert: detectionIds,
    uploadPhoto: uploadPhoto,
    retryThumbnailOnly: remoteOriginalPresent &&
        mediaSyncStatus != MediaSyncStatus.uploaded,
    originalMediaId: stableOriginalMediaId(observationId),
  );
}

/// Whether this client may insert its own `sync_receipts` row.
///
/// The row is written only after the observation is stored, the original
/// photo is confirmed, and the thumbnail step has finished. A failed photo
/// or a failed thumbnail does not get a client receipt.
///
/// This gate does not describe `submit_observation`. That RPC can insert its
/// own receipt when metadata is stored, before this client uploads the photo.
/// The deployed function is not changed here, and an existing RPC receipt is
/// not deleted.
bool clientReceiptWriteAllowed({
  required bool observationStored,
  required bool originalConfirmed,
  required bool thumbnailStepFinished,
}) {
  return observationStored && originalConfirmed && thumbnailStepFinished;
}

/// What a successful `submit_observation` call told the client.
///
/// [callSucceeded] means the RPC returned without an error. [status] is the
/// function's status string when the body has one. `synced` and
/// `already_synced` are metadata results. [provesMedia] is always false.
class SubmitObservationAck {
  const SubmitObservationAck({
    required this.callSucceeded,
    this.status,
  });

  final bool callSucceeded;
  final String? status;

  /// The RPC does not look at Storage or `media_files`.
  bool get provesMedia => false;
}

/// Reads the RPC body. A missing status still counts as a successful call.
/// `success: false` does not.
SubmitObservationAck parseSubmitObservationAck(Object? response) {
  final body = _ackBody(response);
  if (body == null) {
    return const SubmitObservationAck(callSucceeded: true);
  }
  if (body['success'] == false) {
    return const SubmitObservationAck(callSucceeded: false);
  }
  final status = body['status']?.toString();
  return SubmitObservationAck(
    callSucceeded: true,
    status: status == null || status.isEmpty ? null : status,
  );
}

Map<String, Object?>? _ackBody(Object? response) {
  if (response is Map) return Map<String, Object?>.from(response);
  if (response is List && response.length == 1 && response.first is Map) {
    return Map<String, Object?>.from(response.first as Map);
  }
  return null;
}

/// A successful RPC owns the metadata receipt. The client must not read
/// `sync_receipts` and must not insert another row.
bool rpcOwnsMetadataReceipt(SubmitObservationAck ack) => ack.callSucceeded;

/// Direct-insert path only. One client receipt, after media, with no prior read.
bool clientReceiptInsertWithoutRead({
  required bool rpcCallSucceeded,
  required bool observationStored,
  required bool originalConfirmed,
  required bool thumbnailStepFinished,
}) {
  if (rpcCallSucceeded) return false;
  return clientReceiptWriteAllowed(
    observationStored: observationStored,
    originalConfirmed: originalConfirmed,
    thumbnailStepFinished: thumbnailStepFinished,
  );
}

/// The client never SELECTs `agent_runs`. Anon is not granted that read.
bool clientSelectsAgentRuns() => false;

/// `synced` is the only status both SQL definitions return after the
/// observation, location, agent runs, and detections from this payload are
/// in the same transaction.
///
/// `already_synced` from the committed function returns as soon as the
/// observation or a receipt exists. It does not mean the children exist.
bool rpcTransactionStoredChildren(SubmitObservationAck ack) =>
    ack.callSucceeded && ack.status == 'synced';

/// Child ids that this call's RPC transaction stored.
///
/// Empty unless [rpcTransactionStoredChildren] is true. Sending an id is not
/// persistence.
Set<String> childIdsStoredByRpc({
  required SubmitObservationAck ack,
  required Iterable<String> submittedIds,
}) {
  if (!rpcTransactionStoredChildren(ack)) return const {};
  return {
    for (final id in submittedIds)
      if (id.isNotEmpty) id,
  };
}

/// A stored detection is the submitted one only when id, observation,
/// class, and agent run all match.
bool storedDetectionMatches({
  required Map<String, Object?> stored,
  required Map<String, Object?> submitted,
}) {
  const keys = ['id', 'observation_id', 'class_code', 'agent_run_id'];
  for (final key in keys) {
    if (stored[key]?.toString() != submitted[key]?.toString()) return false;
  }
  return submitted['id']?.toString().isNotEmpty ?? false;
}

Set<String> matchedDetectionIds({
  required Iterable<Map<String, Object?>> storedRows,
  required Iterable<Map<String, Object?>> submitted,
}) {
  final matched = <String>{};
  for (final submittedRow in submitted) {
    for (final stored in storedRows) {
      if (!storedDetectionMatches(stored: stored, submitted: submittedRow)) {
        continue;
      }
      matched.add(submittedRow['id'].toString());
      break;
    }
  }
  return matched;
}

bool sameStoredNumber(Object? stored, Object? submitted) {
  if (stored == null || submitted == null) return stored == null && submitted == null;
  final left = stored is num ? stored.toDouble() : double.tryParse(stored.toString());
  final right =
      submitted is num ? submitted.toDouble() : double.tryParse(submitted.toString());
  if (left == null || right == null) return stored.toString() == submitted.toString();
  return left == right;
}

bool storedLocationMatches({
  required Map<String, Object?> stored,
  required Map<String, Object?> submitted,
}) {
  return stored['observation_id']?.toString() ==
          submitted['observation_id']?.toString() &&
      sameStoredNumber(stored['latitude'], submitted['latitude']) &&
      sameStoredNumber(stored['longitude'], submitted['longitude']);
}

/// Which child rows still need an insert.
///
/// A run is inserted when one of its detections is not already stored.
/// A run with no detections is inserted only when [insertZeroDetectionRuns]
/// is true. That is the direct-insert path. On `already_synced` it stays
/// false: inserting that run again can meet a primary-key error that does
/// not name the full identity, and that error must not block the photo retry.
class ChildRepairPlan {
  const ChildRepairPlan({
    required this.agentRunsToInsert,
    required this.detectionsToInsert,
  });

  final List<Map<String, Object?>> agentRunsToInsert;
  final List<Map<String, Object?>> detectionsToInsert;
}

ChildRepairPlan planChildRepair({
  required bool trustTransaction,
  required bool insertZeroDetectionRuns,
  required List<Map<String, Object?>> agentRuns,
  required List<Map<String, Object?>> detections,
  required Set<String> matchedDetectionIds,
}) {
  if (trustTransaction) {
    return const ChildRepairPlan(
      agentRunsToInsert: [],
      detectionsToInsert: [],
    );
  }
  final missingDetections = [
    for (final detection in detections)
      if (!matchedDetectionIds.contains(detection['id']?.toString())) detection,
  ];
  final runsNeeded = {
    for (final detection in missingDetections)
      if ((detection['agent_run_id']?.toString() ?? '').isNotEmpty)
        detection['agent_run_id'].toString(),
  };
  final runs = [
    for (final run in agentRuns)
      if (runsNeeded.contains(run['id']?.toString()) ||
          (insertZeroDetectionRuns &&
              !_runHasSubmittedDetection(run, detections)))
        run,
  ];
  return ChildRepairPlan(
    agentRunsToInsert: runs,
    detectionsToInsert: missingDetections,
  );
}

bool _runHasSubmittedDetection(
  Map<String, Object?> run,
  List<Map<String, Object?>> detections,
) {
  final runId = run['id']?.toString();
  if (runId == null || runId.isEmpty) return false;
  for (final detection in detections) {
    if (detection['agent_run_id']?.toString() == runId) return true;
  }
  return false;
}

/// A receipt or child insert conflict is the same identity only when the
/// database error is a duplicate-key error and its `Key (...)` clause names
/// every identity column with the value we sent.
///
/// A bare `23505`, HTTP 409, or a key that names only one column is not
/// enough. This repository does not define the `sync_receipts` unique
/// constraint, so a conflict that does not echo both columns stays a failure.
bool duplicateKeyMatchesIdentity({
  required Map<String, Object?> identity,
  String? code,
  String? message,
  Object? details,
}) {
  if (identity.isEmpty) return false;
  final duplicate = code == '23505' ||
      (message ?? '').toLowerCase().contains('duplicate key');
  if (!duplicate) return false;
  final text = [
    message ?? '',
    if (details is String) details else '',
  ].join('\n');
  final match = RegExp(
    r'Key \(([^)]+)\)=\((.*)\) already exists',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return false;
  final columns = match
      .group(1)!
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  final values = match
      .group(2)!
      .split(',')
      .map((part) => part.trim())
      .toList();
  if (columns.length != values.length || columns.isEmpty) return false;
  final found = <String, String>{
    for (var i = 0; i < columns.length; i++) columns[i]: values[i],
  };
  for (final entry in identity.entries) {
    final actual = found[entry.key];
    if (actual == null || actual != entry.value?.toString()) return false;
  }
  return true;
}

/// A confirmed original is not sent again. A missing original still is.
bool photoUploadRequired({
  required MediaSyncStatus mediaSyncStatus,
  required bool remoteOriginalPresent,
}) {
  if (remoteOriginalPresent) return false;
  if (mediaSyncStatus == MediaSyncStatus.uploaded) return true;
  return true;
}

/// Fully synced rows that never stored the original public URL.
bool observationNeedsRemoteUrlBackfill(Observation observation) {
  if (observation.syncStatus != SyncStatus.synced) return false;
  if (observation.mediaSyncStatus != MediaSyncStatus.uploaded) return false;
  final url = observation.remoteImageUrl?.trim();
  return url == null || url.isEmpty;
}

/// How many missing URLs one sync pass may look up.
const int remoteUrlRecoveryBatchLimit = 20;

/// Result of the same media-row match used when an original upload is confirmed.
class OriginalMediaUrlMatch {
  const OriginalMediaUrlMatch({required this.matched, this.publicUrl});

  final bool matched;

  /// Non-empty URL to store. Null when the row matched but no URL was available.
  final String? publicUrl;
}

/// Matches one original `media_files` row.
///
/// The row must use [expectedMediaId], [expectedBucket], and a storage path
/// that starts with `{observationId}/{expectedMediaId}.`. A non-empty stored
/// `public_url` wins. An empty stored URL uses [publicUrlForPath], the same
/// `getPublicUrl` fallback as upload confirmation. A blank fallback is not a URL.
OriginalMediaUrlMatch matchOriginalMediaPublicUrl({
  required String observationId,
  required String expectedMediaId,
  required String expectedBucket,
  required Iterable<Map<String, Object?>> rows,
  required String Function(String storagePath) publicUrlForPath,
}) {
  if (observationId.isEmpty ||
      expectedMediaId.isEmpty ||
      expectedBucket.isEmpty) {
    return const OriginalMediaUrlMatch(matched: false);
  }
  final prefix = '$observationId/$expectedMediaId.';
  for (final row in rows) {
    final id = row['id']?.toString();
    final bucket = row['bucket']?.toString();
    final path = row['storage_path']?.toString();
    if (id != expectedMediaId || bucket != expectedBucket) continue;
    if (path == null || !path.startsWith(prefix)) continue;
    final stored = row['public_url']?.toString().trim() ?? '';
    if (stored.isNotEmpty) {
      return OriginalMediaUrlMatch(matched: true, publicUrl: stored);
    }
    final fallback = publicUrlForPath(path).trim();
    if (fallback.isEmpty) {
      return const OriginalMediaUrlMatch(matched: true);
    }
    return OriginalMediaUrlMatch(matched: true, publicUrl: fallback);
  }
  return const OriginalMediaUrlMatch(matched: false);
}

/// 409 is success only when lookup shows this bucket and this exact object path.
bool storageConflictMatchesIntendedObject({
  required String expectedBucket,
  required String expectedPath,
  String? confirmedBucket,
  String? confirmedPath,
}) {
  if (expectedBucket.isEmpty || expectedPath.isEmpty) return false;
  if (confirmedBucket == null || confirmedPath == null) return false;
  return confirmedBucket == expectedBucket && confirmedPath == expectedPath;
}

/// Throws when the existing object is a different path or could not be identified.
Future<void> acceptSameObjectConflict({
  required String expectedBucket,
  required String expectedPath,
  required Future<ConfirmedStorageObject?> Function() confirm,
}) async {
  final confirmed = await confirm();
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
}

/// Storage listing accepts the object only when that file name appears once.
ConfirmedStorageObject? confirmedObjectFromListing({
  required String bucket,
  required String path,
  required Iterable<String> listedNames,
}) {
  final slash = path.lastIndexOf('/');
  final name = slash >= 0 ? path.substring(slash + 1) : path;
  if (name.isEmpty) return null;
  final matches = listedNames.where((item) => item == name).length;
  if (matches != 1) return null;
  return ConfirmedStorageObject(bucket: bucket, path: path);
}

enum RemoteConflictKind { storage, row }

enum RemoteConflictDecision { accept, reject }

/// Inputs are the looked-up object or the stored row.
/// An HTTP status or an error message is not an input and cannot accept the conflict.
class RemoteConflictQuery {
  const RemoteConflictQuery.storage({
    required this.expectedBucket,
    required this.expectedPath,
    this.confirmedBucket,
    this.confirmedPath,
  })  : kind = RemoteConflictKind.storage,
        childId = null,
        observationId = null,
        expectedIdentity = null,
        storedRow = null;

  const RemoteConflictQuery.row({
    this.childId,
    this.observationId,
    required this.expectedIdentity,
    this.storedRow,
  })  : kind = RemoteConflictKind.row,
        expectedBucket = null,
        expectedPath = null,
        confirmedBucket = null,
        confirmedPath = null;

  final RemoteConflictKind kind;
  final String? expectedBucket;
  final String? expectedPath;
  final String? confirmedBucket;
  final String? confirmedPath;
  final String? childId;
  final String? observationId;
  final Map<String, Object?>? expectedIdentity;
  final Map<String, Object?>? storedRow;
}

/// Columns that identify a child row. Timestamps and file sizes are not identity.
const Map<String, List<String>> rowIdentityKeys = {
  'observations': ['id', 'capture_id'],
  'locations': ['observation_id', 'latitude', 'longitude'],
  'agent_runs': ['id', 'observation_id', 'agent'],
  'detections': ['id', 'observation_id', 'class_code', 'agent_run_id'],
  'media_files': ['id', 'observation_id', 'bucket', 'storage_path', 'media_type'],
  'sync_receipts': ['observation_id', 'idempotency_key'],
};

List<String> identityColumnsForTable(String table) {
  return List<String>.from(
    rowIdentityKeys[table] ?? const ['id', 'observation_id'],
  );
}

Map<String, Object?> identityFieldsForTable(
  String table,
  Map<dynamic, dynamic> payload,
) {
  return {
    for (final key in identityColumnsForTable(table))
      if (payload.containsKey(key)) key: payload[key],
  };
}

bool sameStoredIdentityValue(Object? stored, Object? expected) {
  if (stored == null || expected == null) return stored == expected;
  if (stored is num && expected is num) {
    return (stored.toDouble() - expected.toDouble()).abs() < 1e-5;
  }
  final storedText = stored.toString();
  final expectedText = expected.toString();
  if (storedText == expectedText) return true;
  final storedNum = num.tryParse(storedText);
  final expectedNum = num.tryParse(expectedText);
  if (storedNum != null &&
      expectedNum != null &&
      !storedText.contains('-') &&
      !expectedText.contains('-')) {
    return (storedNum.toDouble() - expectedNum.toDouble()).abs() < 1e-5;
  }
  return false;
}

/// The only accept/reject decision for storage 409 and database unique conflicts.
/// Accepts a storage conflict only when the lookup is the same bucket and path.
/// Accepts a row conflict only when the child id, observation id, and readable
/// identity fields match. A missing lookup or a different payload is rejected.
/// This function does not delete remote rows.
RemoteConflictDecision decideRemoteConflict(RemoteConflictQuery query) {
  if (query.kind == RemoteConflictKind.storage) {
    final matches = storageConflictMatchesIntendedObject(
      expectedBucket: query.expectedBucket ?? '',
      expectedPath: query.expectedPath ?? '',
      confirmedBucket: query.confirmedBucket,
      confirmedPath: query.confirmedPath,
    );
    return matches
        ? RemoteConflictDecision.accept
        : RemoteConflictDecision.reject;
  }
  final stored = query.storedRow;
  if (stored == null) return RemoteConflictDecision.reject;
  final childId = query.childId;
  if (childId != null && stored['id']?.toString() != childId) {
    return RemoteConflictDecision.reject;
  }
  final observationId = query.observationId;
  if (observationId != null && stored.containsKey('observation_id')) {
    if (stored['observation_id']?.toString() != observationId) {
      return RemoteConflictDecision.reject;
    }
  }
  final expected = query.expectedIdentity ?? const <String, Object?>{};
  if (childId == null && observationId == null && expected.isEmpty) {
    return RemoteConflictDecision.reject;
  }
  for (final entry in expected.entries) {
    if (!stored.containsKey(entry.key)) return RemoteConflictDecision.reject;
    if (!sameStoredIdentityValue(stored[entry.key], entry.value)) {
      return RemoteConflictDecision.reject;
    }
  }
  return RemoteConflictDecision.accept;
}

enum QueueSyncState {
  notYetSynced,
  metadataSyncedPhotoFailed,
  laterStepIncomplete,
  fullySynced,
  manualReview,
  manualRetryInProgress,
}

QueueSyncState queueSyncState(Observation obs,
    {bool manualRetryInProgress = false}) {
  if (manualRetryInProgress ||
      (obs.syncStatus == SyncStatus.uploading &&
          (obs.syncError ?? '').startsWith('Manual retry in progress'))) {
    return QueueSyncState.manualRetryInProgress;
  }
  if (obs.syncStatus == SyncStatus.needsReview) {
    return QueueSyncState.manualReview;
  }
  if (obs.syncStatus == SyncStatus.synced &&
      obs.mediaSyncStatus == MediaSyncStatus.uploaded) {
    return QueueSyncState.fullySynced;
  }
  if (obs.mediaSyncStatus == MediaSyncStatus.originalUploaded) {
    return QueueSyncState.laterStepIncomplete;
  }
  if (obs.mediaSyncStatus == MediaSyncStatus.failed ||
      (obs.syncStatus == SyncStatus.synced &&
          obs.mediaSyncStatus != MediaSyncStatus.uploaded)) {
    return QueueSyncState.metadataSyncedPhotoFailed;
  }
  return QueueSyncState.notYetSynced;
}

String queueStatusMessage(Observation obs, {bool manualRetryInProgress = false}) {
  switch (queueSyncState(obs, manualRetryInProgress: manualRetryInProgress)) {
    case QueueSyncState.notYetSynced:
      return 'Observation not yet synced.';
    case QueueSyncState.metadataSyncedPhotoFailed:
      return 'Metadata synced, but the photo upload failed. The local photo is still on this device.';
    case QueueSyncState.laterStepIncomplete:
      return 'Original photo is stored. A later thumbnail step failed. The local photo is still on this device.';
    case QueueSyncState.fullySynced:
      return 'Fully synced, including the photo.';
    case QueueSyncState.manualRetryInProgress:
      return 'Manual retry in progress.';
    case QueueSyncState.manualReview:
      final manualFailed =
          (obs.syncError ?? '').startsWith('Manual retry failed');
      if (manualFailed) {
        return 'Manual review after retry exhaustion. The last manual retry failed. The local photo is still on this device.';
      }
      if (obs.mediaSyncStatus == MediaSyncStatus.failed) {
        return 'Manual review after retry exhaustion. Metadata synced, but the photo upload failed. The local photo is still on this device.';
      }
      return 'Manual review after retry exhaustion. The local photo is still on this device.';
  }
}

List<Map<String, dynamic>> rowsMissing(
  List<Map<String, dynamic>> rows,
  Set<String> existingIds,
) {
  return [
    for (final row in rows)
      if (!existingIds.contains(row['id']?.toString())) row,
  ];
}

/// Synced only when every required step finished.
/// A failed media upload, an auth error, or a dropped network stays unsynced.
/// Local rows are never deleted here.
bool syncMayComplete({
  required bool observationReady,
  required bool childrenReady,
  required bool mediaReady,
  required bool authOk,
  required bool networkOk,
}) {
  return observationReady && childrenReady && mediaReady && authOk && networkOk;
}

/// Strip JWT-shaped text before it is logged or stored on a sync error.
String redactSecrets(String text) {
  return text.replaceAll(
    RegExp(r'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'),
    '[redacted]',
  );
}
