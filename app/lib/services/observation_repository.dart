import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/observation.dart';
import '../data/local/database.dart';
import '../data/local/observation_dao.dart';

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
// In-memory repository — for UI development and widget tests
// ---------------------------------------------------------------------------

class MemoryObservationRepository implements ObservationRepository {
  final _items = <String, Observation>{};

  @override
  Future<void> save(Observation obs) async => _items[obs.id] = obs;

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
    if (status == SyncStatus.failed || status == SyncStatus.uploading) {
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
  Future<void> upload(Observation observation, {required String idempotencyKey});
}

// ---------------------------------------------------------------------------
// Sync coordinator — idempotent, retryable, with exponential backoff
// ---------------------------------------------------------------------------

class SyncCoordinator {
  SyncCoordinator(this._repo, this._client, {this.maxRetries = 5});

  final ObservationRepository _repo;
  final ObservationSyncClient _client;
  final int maxRetries;

  bool _running = false;

  /// Recovers any uploads that were stuck in [SyncStatus.uploading]
  /// when the app was previously killed.  Call at app startup.
  Future<void> recoverStuckUploads() async {
    final stuck = await _repo.findStuckUploading();
    for (final obs in stuck) {
      debugPrint('[Sync] Recovering stuck upload: ${obs.id}');
      await _repo.updateSyncStatus(obs.id, SyncStatus.pending);
    }
  }

  /// Uploads all [SyncStatus.pending] observations with exponential backoff.
  Future<void> syncPending() async {
    if (_running) return;
    _running = true;
    try {
      final pending = await _repo.list(status: SyncStatus.pending);
      for (final obs in pending) {
        if (obs.uploadAttempts >= maxRetries) {
          await _repo.updateSyncStatus(obs.id, SyncStatus.needsReview,
              error: 'Max retries ($maxRetries) exceeded');
          continue;
        }
        await _repo.updateSyncStatus(obs.id, SyncStatus.uploading);
        try {
          await _client.upload(obs, idempotencyKey: obs.id);
          await _repo.updateSyncStatus(obs.id, SyncStatus.synced);
        } catch (e) {
          final backoff = _backoffDuration(obs.uploadAttempts);
          debugPrint('[Sync] Failed ${obs.id}: $e  (retry in ${backoff.inSeconds}s)');
          await _repo.updateSyncStatus(obs.id, SyncStatus.failed, error: e.toString());
          await Future<void>.delayed(backoff);
        }
      }
    } finally {
      _running = false;
    }
  }

  Duration _backoffDuration(int attempt) {
    const maxRetries = 3;
    final base = 2;
    final seconds = min(base * pow(2, attempt).toInt(), 300); // max 5 min
    final jitter = Random().nextInt(seconds ~/ 2 + 1);
    return Duration(seconds: seconds + jitter);
  }
}
