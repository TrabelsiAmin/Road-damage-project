import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/observation.dart';
import '../data/local/database.dart';
import '../data/local/observation_dao.dart';
import 'sync_cancel_token.dart';

export 'sync_cancel_token.dart';

// ---------------------------------------------------------------------------
// Repository interface
// ---------------------------------------------------------------------------

abstract class ObservationRepository {
  Future<void>              save(Observation observation);
  Future<List<Observation>> list({SyncStatus? status});
  Future<void>              updateSyncStatus(String id, SyncStatus status, {String? error});
  Future<void>              updateAnnotatedPath(String id, String path);
  Future<Observation?>      findById(String id);
  Future<List<Observation>> findStuckUploading();
}

// ---------------------------------------------------------------------------
// In-memory repository — for UI development and unit/widget tests
// ---------------------------------------------------------------------------

class MemoryObservationRepository implements ObservationRepository {
  final _items = <String, Observation>{};

  @override
  Future<void> save(Observation obs) async {
    _items[obs.id] = obs;
  }

  @override
  Future<List<Observation>> list({SyncStatus? status}) async =>
      _items.values
          .where((o) => status == null || o.syncStatus == status)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> updateSyncStatus(String id, SyncStatus status, {String? error}) async {
    final obs = _items[id];
    if (obs == null) throw StateError('Observation not found: $id');
    obs.syncStatus = status;
    obs.syncError  = error;
    if (status == SyncStatus.failed) {
      obs.uploadAttempts++;
    }
  }

  @override
  Future<void> updateAnnotatedPath(String id, String path) async {
    _items[id]?.annotatedImagePath = path;
  }

  @override
  Future<Observation?> findById(String id) async => _items[id];

  @override
  Future<List<Observation>> findStuckUploading() async =>
      _items.values.where((o) => o.syncStatus == SyncStatus.uploading).toList();
}

// ---------------------------------------------------------------------------
// SQLite repository — production persistence
// ---------------------------------------------------------------------------

class SqliteObservationRepository implements ObservationRepository {
  SqliteObservationRepository({AppDatabase? db})
      : _dao = ObservationDao(db ?? AppDatabase.instance);

  final ObservationDao _dao;

  @override
  Future<void> save(Observation obs) => _dao.insert(obs);

  @override
  Future<List<Observation>> list({SyncStatus? status}) =>
      _dao.listAll(status: status);

  @override
  Future<void> updateSyncStatus(String id, SyncStatus status, {String? error}) =>
      _dao.updateSyncStatus(id, status, error: error);

  @override
  Future<void> updateAnnotatedPath(String id, String path) =>
      _dao.updateAnnotatedPath(id, path);

  @override
  Future<Observation?> findById(String id) => _dao.findById(id);

  @override
  Future<List<Observation>> findStuckUploading() => _dao.findStuckUploading();
}

// ---------------------------------------------------------------------------
// Sync client interface
// ---------------------------------------------------------------------------

abstract class ObservationSyncClient {
  Future<void> upload(
    Observation observation, {
    required String idempotencyKey,
    SyncCancelToken? cancelToken,
  });
}

// ---------------------------------------------------------------------------
// Sync result model
// ---------------------------------------------------------------------------

class SyncResult {
  final int uploadedCount;
  final int totalCount;
  final bool cancelled;
  final String message;

  const SyncResult({
    required this.uploadedCount,
    required this.totalCount,
    required this.cancelled,
    required this.message,
  });

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Sync coordinator — idempotent, retryable, cancellable, with exponential backoff
// ---------------------------------------------------------------------------

class SyncCoordinator {
  SyncCoordinator(this._repo, this._client, {this.maxRetries = 5});

  final ObservationRepository _repo;
  final ObservationSyncClient _client;
  final int maxRetries;

  bool _running = false;
  bool get isRunning => _running;

  int _uploadedCount = 0;
  int _totalCount = 0;
  int get uploadedCount => _uploadedCount;
  int get totalCount => _totalCount;

  /// Recovers any uploads that were stuck in [SyncStatus.uploading]
  /// when the app was previously killed. Call at app startup.
  Future<void> recoverStuckUploads() async {
    final stuck = await _repo.findStuckUploading();
    for (final obs in stuck) {
      debugPrint('[Sync] Recovering stuck upload: ${obs.id}');
      await _repo.updateSyncStatus(obs.id, SyncStatus.pending);
    }
  }

  /// Uploads all [SyncStatus.pending] and [SyncStatus.failed] observations with exponential backoff.
  /// Supports cooperative cancellation via [cancelToken].
  Future<SyncResult> syncPending({SyncCancelToken? cancelToken}) async {
    if (_running) {
      return SyncResult(
        uploadedCount: _uploadedCount,
        totalCount: _totalCount,
        cancelled: false,
        message: 'Sync already running',
      );
    }
    _running = true;
    _uploadedCount = 0;
    try {
      cancelToken?.throwIfCancelled();

      final pending = await _repo.list(status: SyncStatus.pending);
      final failed = await _repo.list(status: SyncStatus.failed);
      final queue = [...pending, ...failed];
      _totalCount = queue.length;

      for (final obs in queue) {
        cancelToken?.throwIfCancelled();

        // Failed rows are retried from Sync All. The attempt cap still applies
        // to rows that are still pending.
        if (obs.syncStatus == SyncStatus.pending &&
            obs.uploadAttempts >= maxRetries) {
          await _repo.updateSyncStatus(obs.id, SyncStatus.needsReview,
              error: 'Max retries ($maxRetries) exceeded');
          continue;
        }

        await _repo.updateSyncStatus(obs.id, SyncStatus.uploading);
        try {
          cancelToken?.throwIfCancelled();
          await _client.upload(obs, idempotencyKey: obs.id, cancelToken: cancelToken);
          cancelToken?.throwIfCancelled();

          // Only mark synced if all parts (metadata, image, detections, receipts) succeeded
          await _repo.updateSyncStatus(obs.id, SyncStatus.synced);
          _uploadedCount++;
        } on SyncCancelledException {
          // Keep item in pending status locally, do NOT mark synced, never delete local data
          debugPrint('[Sync] Cancelled while processing ${obs.id}, reverting to pending');
          await _repo.updateSyncStatus(obs.id, SyncStatus.pending);
          rethrow;
        } catch (e) {
          final backoff = _backoffDuration(obs.uploadAttempts);
          debugPrint('[Sync] Failed ${obs.id}: $e  (retry in ${backoff.inSeconds}s)');
          await _repo.updateSyncStatus(obs.id, SyncStatus.failed, error: e.toString());
          await Future<void>.delayed(backoff);
        }
      }

      return SyncResult(
        uploadedCount: _uploadedCount,
        totalCount: _totalCount,
        cancelled: false,
        message: 'Sync complete: $_uploadedCount of $_totalCount uploaded',
      );
    } on SyncCancelledException {
      return SyncResult(
        uploadedCount: _uploadedCount,
        totalCount: _totalCount,
        cancelled: true,
        message: 'Sync cancelled: $_uploadedCount of $_totalCount uploaded',
      );
    } finally {
      _running = false;
    }
  }

  Duration _backoffDuration(int attempt) {
    const base = 2;
    final seconds = min(base * pow(2, attempt).toInt(), 300); // max 5 min
    final jitter = Random().nextInt(seconds ~/ 2 + 1);
    return Duration(seconds: seconds + jitter);
  }
}