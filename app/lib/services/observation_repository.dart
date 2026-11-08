import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/observation.dart';
import '../data/local/database.dart';
import '../data/local/observation_dao.dart';
import 'sync_cancel_token.dart';
import 'sync_plan.dart';
import 'sync_policy.dart';

export 'sync_cancel_token.dart';

// ---------------------------------------------------------------------------
// Repository interface
// ---------------------------------------------------------------------------

abstract class ObservationRepository {
  Future<void> save(Observation observation);
  Future<List<Observation>> list({SyncStatus? status});
  Future<void> updateSyncStatus(String id, SyncStatus status, {String? error});
  Future<void> updateMediaSyncStatus(String id, MediaSyncStatus status);
  Future<void> updateAnnotatedPath(String id, String path);
  Future<void> updateRemoteImageUrl(String id, String url);

  /// Ids of fully synced rows whose stored original URL is null or blank.
  /// Oldest first, at most [limit]. Does not load detection rows.
  Future<List<String>> idsMissingRemoteImageUrl({int limit = 20});
  Future<Observation?> findById(String id);
  Future<void> deleteById(String id);
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
  Future<List<Observation>> list({SyncStatus? status}) async => _items.values
      .where((o) => status == null || o.syncStatus == status)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> updateSyncStatus(String id, SyncStatus status,
      {String? error}) async {
    final obs = _items[id];
    if (obs == null) throw StateError('Observation not found: $id');
    obs.syncStatus = status;
    obs.syncError = error;
    if (status == SyncStatus.failed) {
      obs.uploadAttempts++;
    }
  }

  @override
  Future<void> updateMediaSyncStatus(String id, MediaSyncStatus status) async {
    final obs = _items[id];
    if (obs == null) throw StateError('Observation not found: $id');
    obs.mediaSyncStatus = status;
  }

  @override
  Future<void> updateAnnotatedPath(String id, String path) async {
    _items[id]?.annotatedImagePath = path;
  }

  @override
  Future<void> updateRemoteImageUrl(String id, String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final obs = _items[id];
    if (obs == null) return;
    obs.remoteImageUrl = trimmed;
  }

  @override
  Future<List<String>> idsMissingRemoteImageUrl({int limit = 20}) async {
    if (limit <= 0) return const [];
    final eligible = _items.values
        .where(observationNeedsRemoteUrlBackfill)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [for (final obs in eligible.take(limit)) obs.id];
  }

  @override
  Future<Observation?> findById(String id) async => _items[id];

  @override
  Future<void> deleteById(String id) async => _items.remove(id);

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
  Future<void> updateSyncStatus(String id, SyncStatus status,
          {String? error}) =>
      _dao.updateSyncStatus(id, status, error: error);

  @override
  Future<void> updateMediaSyncStatus(String id, MediaSyncStatus status) =>
      _dao.updateMediaSyncStatus(id, status);

  @override
  Future<void> updateAnnotatedPath(String id, String path) =>
      _dao.updateAnnotatedPath(id, path);

  @override
  Future<void> updateRemoteImageUrl(String id, String url) =>
      _dao.updateRemoteImageUrl(id, url);

  @override
  Future<List<String>> idsMissingRemoteImageUrl({int limit = 20}) =>
      _dao.idsMissingRemoteImageUrl(limit: limit);

  @override
  Future<Observation?> findById(String id) => _dao.findById(id);

  @override
  Future<void> deleteById(String id) => _dao.deleteById(id);

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
    ObservationRepository? repository,
  });
}

/// Reads an original public URL that is already stored remotely.
/// Implementations must not upload photo bytes.
abstract class StoredOriginalUrlSource {
  Future<String?> readStoredOriginalUrl(String observationId);
}

typedef StoredOriginalUrlLookup = Future<String?> Function(String observationId);

// ---------------------------------------------------------------------------
// Sync result model
// ---------------------------------------------------------------------------

class SyncResult {
  final int uploadedCount;
  final int totalCount;
  final bool cancelled;
  final bool blocked;
  final String message;

  const SyncResult({
    required this.uploadedCount,
    required this.totalCount,
    required this.cancelled,
    required this.message,
    this.blocked = false,
  });

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Sync coordinator — idempotent, retryable, cancellable, with exponential backoff
// ---------------------------------------------------------------------------

class SyncCoordinator {
  SyncCoordinator(
    this._repo,
    this._client, {
    this.maxRetries = 5,
    SyncSettingsReader? readSettings,
    SyncNetworkReader? readNetwork,
    DateTime Function()? clock,
    StoredOriginalUrlLookup? readStoredOriginalUrl,
    this.remoteUrlRecoveryLimit = remoteUrlRecoveryBatchLimit,
  })  : _readSettings = readSettings ?? readStoredSyncSettings,
        _readNetwork = readNetwork ?? readDeviceSyncNetwork,
        _clock = clock ?? DateTime.now,
        _readStoredOriginalUrl = readStoredOriginalUrl;

  final ObservationRepository _repo;
  final ObservationSyncClient _client;
  final int maxRetries;
  final SyncSettingsReader _readSettings;
  final SyncNetworkReader _readNetwork;
  final DateTime Function() _clock;
  final StoredOriginalUrlLookup? _readStoredOriginalUrl;
  final int remoteUrlRecoveryLimit;

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

  /// Uploads [SyncStatus.pending] and [SyncStatus.failed] rows.
  /// [SyncStatus.needsReview] is not included. A manual retry uses [retryNeedsReview].
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
      await _applyPhotoRetention();
      cancelToken?.throwIfCancelled();
      await _recoverStoredOriginalUrls(cancelToken);

      final pending = await _repo.list(status: SyncStatus.pending);
      final failed = await _repo.list(status: SyncStatus.failed);
      final queue = [...pending, ...failed];
      _totalCount = queue.length;
      final blocked = await _wifiBlock(queue.length);
      if (blocked != null) return blocked;

      for (final obs in queue) {
        cancelToken?.throwIfCancelled();

        // Pending and failed rows share the attempt cap so a failing upload
        // cannot retry forever. The local row is kept.
        if (obs.uploadAttempts >= maxRetries) {
          await _repo.updateSyncStatus(obs.id, SyncStatus.needsReview,
              error: 'Max retries ($maxRetries) exceeded');
          continue;
        }

        await _repo.updateSyncStatus(obs.id, SyncStatus.uploading);
        try {
          cancelToken?.throwIfCancelled();
          final current = await _repo.findById(obs.id) ?? obs;
          await _client.upload(
            current,
            idempotencyKey: obs.id,
            cancelToken: cancelToken,
            repository: _repo,
          );
          cancelToken?.throwIfCancelled();

          // A returned upload is fully synced only when the photo is uploaded.
          // Metadata without the photo stays unsynced. The local file is kept.
          final after = await _repo.findById(obs.id);
          final mediaReady =
              after?.mediaSyncStatus == MediaSyncStatus.uploaded;
          if (syncMayComplete(
            observationReady: true,
            childrenReady: true,
            mediaReady: mediaReady,
            authOk: true,
            networkOk: true,
          )) {
            await _repo.updateSyncStatus(obs.id, SyncStatus.synced);
            _uploadedCount++;
          } else {
            await _markIncomplete(obs.id, after);
          }
        } on SyncCancelledException {
          // Keep item in pending status locally, do NOT mark synced, never delete local data
          debugPrint(
              '[Sync] Cancelled while processing ${obs.id}, reverting to pending');
          await _repo.updateSyncStatus(obs.id, SyncStatus.pending);
          rethrow;
        } catch (e) {
          final backoff = _backoffDuration(obs.uploadAttempts);
          debugPrint(
              '[Sync] Failed ${obs.id}: $e  (retry in ${backoff.inSeconds}s)');
          await _repo.updateSyncStatus(obs.id, SyncStatus.failed,
              error: redactSecrets(e.toString()));
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

  /// One explicit attempt for a [SyncStatus.needsReview] row.
  /// Does not change [Observation.uploadAttempts], so [syncPending] cannot loop on it.
  Future<SyncResult> retryNeedsReview(
    String observationId, {
    SyncCancelToken? cancelToken,
  }) async {
    if (_running) {
      return SyncResult(
        uploadedCount: _uploadedCount,
        totalCount: _totalCount,
        cancelled: false,
        message: 'Sync already running',
      );
    }
    final obs = await _repo.findById(observationId);
    if (obs == null || obs.syncStatus != SyncStatus.needsReview) {
      return const SyncResult(
        uploadedCount: 0,
        totalCount: 0,
        cancelled: false,
        message: 'Not awaiting manual review.',
      );
    }
    final attempts = obs.uploadAttempts;
    _running = true;
    _uploadedCount = 0;
    _totalCount = 1;
    try {
      cancelToken?.throwIfCancelled();
      final blocked = await _wifiBlock(1);
      if (blocked != null) return blocked;
      await _repo.updateSyncStatus(
        obs.id,
        SyncStatus.uploading,
        error: 'Manual retry in progress',
      );
      final current = await _repo.findById(obs.id) ?? obs;
      await _client.upload(
        current,
        idempotencyKey: obs.id,
        cancelToken: cancelToken,
        repository: _repo,
      );
      cancelToken?.throwIfCancelled();
      final after = await _repo.findById(obs.id);
      final mediaReady = after?.mediaSyncStatus == MediaSyncStatus.uploaded;
      if (syncMayComplete(
        observationReady: true,
        childrenReady: true,
        mediaReady: mediaReady,
        authOk: true,
        networkOk: true,
      )) {
        await _repo.updateSyncStatus(obs.id, SyncStatus.synced);
        _uploadedCount = 1;
        return const SyncResult(
          uploadedCount: 1,
          totalCount: 1,
          cancelled: false,
          message: 'Manual retry synced 1 of 1',
        );
      }
      await _markIncomplete(obs.id, after, manualReview: true);
      return const SyncResult(
        uploadedCount: 0,
        totalCount: 1,
        cancelled: false,
        message: 'Manual retry failed',
      );
    } on SyncCancelledException {
      await _repo.updateSyncStatus(
        obs.id,
        SyncStatus.needsReview,
        error: 'Manual retry failed: cancelled',
      );
      return SyncResult(
        uploadedCount: _uploadedCount,
        totalCount: 1,
        cancelled: true,
        message: 'Manual retry cancelled',
      );
    } catch (e) {
      await _repo.updateSyncStatus(
        obs.id,
        SyncStatus.needsReview,
        error: 'Manual retry failed: ${redactSecrets(e.toString())}',
      );
      return const SyncResult(
        uploadedCount: 0,
        totalCount: 1,
        cancelled: false,
        message: 'Manual retry failed',
      );
    } finally {
      final stored = await _repo.findById(obs.id);
      if (stored != null &&
          stored.syncStatus != SyncStatus.synced &&
          stored.uploadAttempts != attempts) {
        debugPrint(
            '[Sync] Manual retry left attempt count ${stored.uploadAttempts}; expected $attempts');
      }
      _running = false;
    }
  }

  Future<void> _markIncomplete(
    String id,
    Observation? after, {
    bool manualReview = false,
  }) async {
    final originalKept =
        after?.mediaSyncStatus == MediaSyncStatus.originalUploaded;
    if (after != null &&
        after.mediaSyncStatus != MediaSyncStatus.uploaded &&
        !originalKept) {
      await _repo.updateMediaSyncStatus(id, MediaSyncStatus.failed);
    }
    final error = originalKept
        ? 'Original photo is stored, but a later thumbnail step failed.'
        : 'Metadata synced, but the photo upload failed.';
    await _repo.updateSyncStatus(
      id,
      manualReview ? SyncStatus.needsReview : SyncStatus.failed,
      error: manualReview ? 'Manual retry failed: $error' : error,
    );
  }

  /// Fills a blank original URL from an already stored media row.
  /// Runs once per [syncPending], for a bounded batch. Does not upload bytes.
  Future<void> _recoverStoredOriginalUrls(SyncCancelToken? cancelToken) async {
    final lookup = _readStoredOriginalUrl ??
        (_client is StoredOriginalUrlSource
            ? (_client as StoredOriginalUrlSource).readStoredOriginalUrl
            : null);
    if (lookup == null) return;
    try {
      final ids = await _repo.idsMissingRemoteImageUrl(
        limit: remoteUrlRecoveryLimit,
      );
      if (ids.isEmpty) return;
      SyncNetworkType network;
      try {
        network = await _readNetwork();
      } catch (_) {
        network = SyncNetworkType.unknown;
      }
      if (!remoteUrlRecoveryMayQuery(network)) return;
      for (final id in ids) {
        cancelToken?.throwIfCancelled();
        try {
          final url = await lookup(id);
          final trimmed = url?.trim();
          if (trimmed == null || trimmed.isEmpty) continue;
          final current = await _repo.findById(id);
          if (current == null || !observationNeedsRemoteUrlBackfill(current)) {
            continue;
          }
          await _repo.updateRemoteImageUrl(id, trimmed);
        } on SyncCancelledException {
          rethrow;
        } catch (e) {
          debugPrint(
            '[Sync] Remote URL recovery skipped for $id: ${redactSecrets(e.toString())}',
          );
        }
      }
    } on SyncCancelledException {
      rethrow;
    } catch (e) {
      debugPrint(
        '[Sync] Remote URL recovery skipped: ${redactSecrets(e.toString())}',
      );
    }
  }

  /// Removes local photos that are fully synced and past the retention window.
  /// Rows that still need a retry keep their files. The database row stays.
  Future<void> applyPhotoRetention() => _applyPhotoRetention();

  Future<void> _applyPhotoRetention() async {
    try {
      final settings = await _readSettings();
      final observations = await _repo.list();
      await deleteEligibleLocalPhotos(
        observations: observations,
        retentionDays: settings.retentionDays,
        now: _clock(),
      );
    } catch (e) {
      debugPrint('[Sync] Photo retention skipped: $e');
    }
  }

  /// Null when this attempt may upload. Wi-Fi-only off does not read the network.
  Future<SyncResult?> _wifiBlock(int total) async {
    final settings = await _readSettings();
    if (!settings.wifiOnly) return null;
    SyncNetworkType network;
    try {
      network = await _readNetwork();
    } catch (_) {
      network = SyncNetworkType.unknown;
    }
    if (decideSyncTransport(wifiOnly: true, network: network) ==
        SyncTransportDecision.allowed) {
      return null;
    }
    return SyncResult(
      uploadedCount: 0,
      totalCount: total,
      cancelled: false,
      blocked: true,
      message: wifiOnlyBlockedMessage,
    );
  }

  Duration _backoffDuration(int attempt) {
    const base = 2;
    final seconds = min(base * pow(2, attempt).toInt(), 300); // max 5 min
    final jitter = Random().nextInt(seconds ~/ 2 + 1);
    return Duration(seconds: seconds + jitter);
  }
}
