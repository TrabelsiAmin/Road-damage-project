import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tariqmap/data/local/database.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';
import 'package:tariqmap/services/sync_plan.dart';
import 'package:tariqmap/services/sync_policy.dart';

void main() {
  test('original media match prefers a stored public url', () {
    var fallbackCalls = 0;
    final mediaId = stableOriginalMediaId('obs-old');
    final match = matchOriginalMediaPublicUrl(
      observationId: 'obs-old',
      expectedMediaId: mediaId,
      expectedBucket: 'observation-images',
      rows: [
        {
          'id': stableOriginalMediaId('other'),
          'bucket': 'observation-images',
          'storage_path': 'other/nope.webp',
          'public_url': 'https://cdn.example/other.webp',
        },
        {
          'id': mediaId,
          'bucket': 'public-photos',
          'storage_path': 'obs-old/$mediaId.webp',
          'public_url': 'https://cdn.example/thumb.webp',
        },
        {
          'id': mediaId,
          'bucket': 'observation-images',
          'storage_path': 'obs-old/$mediaId.webp',
          'public_url': ' https://cdn.example/original.webp ',
        },
      ],
      publicUrlForPath: (path) {
        fallbackCalls++;
        return 'https://cdn.example/from-path$path';
      },
    );

    expect(match.matched, isTrue);
    expect(match.publicUrl, 'https://cdn.example/original.webp');
    expect(fallbackCalls, 0);
  });

  test('empty stored public url uses getPublicUrl and a blank fallback is not stored', () {
    final mediaId = stableOriginalMediaId('obs-old');
    final fallback = matchOriginalMediaPublicUrl(
      observationId: 'obs-old',
      expectedMediaId: mediaId,
      expectedBucket: 'observation-images',
      rows: [
        {
          'id': mediaId,
          'bucket': 'observation-images',
          'storage_path': 'obs-old/$mediaId.webp',
          'public_url': '  ',
        },
      ],
      publicUrlForPath: (_) => ' https://cdn.example/from-path.webp ',
    );
    expect(fallback.matched, isTrue);
    expect(fallback.publicUrl, 'https://cdn.example/from-path.webp');

    final empty = matchOriginalMediaPublicUrl(
      observationId: 'obs-old',
      expectedMediaId: mediaId,
      expectedBucket: 'observation-images',
      rows: [
        {
          'id': mediaId,
          'bucket': 'observation-images',
          'storage_path': 'obs-old/$mediaId.webp',
          'public_url': '',
        },
      ],
      publicUrlForPath: (_) => '   ',
    );
    expect(empty.matched, isTrue);
    expect(empty.publicUrl, isNull);

    final missing = matchOriginalMediaPublicUrl(
      observationId: 'obs-old',
      expectedMediaId: mediaId,
      expectedBucket: 'observation-images',
      rows: const [],
      publicUrlForPath: (_) => 'https://cdn.example/invented.webp',
    );
    expect(missing.matched, isFalse);
    expect(missing.publicUrl, isNull);
  });

  test('sync recovers a stored url without uploading or changing status', () async {
    final repo = MemoryObservationRepository();
    final uploads = _NoUpload();
    final lookup = _Lookup({
      'old': 'https://cdn.example/original.webp',
      'missing': null,
      'blank': '  ',
      'down': null,
      'kept': 'https://cdn.example/should-not-replace.webp',
      'pending': 'https://cdn.example/pending.webp',
      'failed': 'https://cdn.example/failed.webp',
      'review': 'https://cdn.example/review.webp',
    }, throwFor: {'down'});
    await repo.save(_obs('old', DateTime.utc(2020, 1, 1)));
    await repo.save(_obs('missing', DateTime.utc(2020, 1, 2)));
    await repo.save(_obs('blank', DateTime.utc(2020, 1, 3)));
    await repo.save(_obs('down', DateTime.utc(2020, 1, 4)));
    await repo.save(_obs(
      'kept',
      DateTime.utc(2020, 1, 5),
      remote: 'https://cdn.example/already.webp',
    ));
    await repo.save(_obs(
      'pending',
      DateTime.utc(2019, 1, 1),
      syncStatus: SyncStatus.pending,
      media: MediaSyncStatus.pending,
    ));
    await repo.save(_obs(
      'failed',
      DateTime.utc(2019, 1, 2),
      syncStatus: SyncStatus.failed,
      media: MediaSyncStatus.failed,
    ));
    await repo.save(_obs(
      'review',
      DateTime.utc(2019, 1, 3),
      syncStatus: SyncStatus.needsReview,
      media: MediaSyncStatus.failed,
    ));
    expect(
      await repo.idsMissingRemoteImageUrl(limit: 20),
      ['old', 'missing', 'blank', 'down'],
    );
    await repo.deleteById('pending');
    await repo.deleteById('failed');
    await repo.deleteById('review');

    final result = await _coordinator(repo, uploads, lookup).syncPending();

    expect(result.blocked, isFalse);
    expect(uploads.uploadCount, 0);
    expect(lookup.calls, ['old', 'missing', 'blank', 'down']);
    final old = await repo.findById('old');
    expect(old!.remoteImageUrl, 'https://cdn.example/original.webp');
    expect(old.syncStatus, SyncStatus.synced);
    expect(old.mediaSyncStatus, MediaSyncStatus.uploaded);
    expect(old.imagePath, '/tmp/missing-old.jpg');
    expect(old.detections.single.classCode, 'D00');
    expect((await repo.findById('missing'))!.remoteImageUrl, isNull);
    expect((await repo.findById('blank'))!.remoteImageUrl, isNull);
    expect((await repo.findById('down'))!.remoteImageUrl, isNull);
    expect((await repo.findById('down'))!.syncStatus, SyncStatus.synced);
    expect((await repo.findById('down'))!.mediaSyncStatus, MediaSyncStatus.uploaded);
    expect((await repo.findById('kept'))!.remoteImageUrl,
        'https://cdn.example/already.webp');
  });

  test('offline and a throwing radio skip recovery without writes', () async {
    final repo = MemoryObservationRepository();
    final uploads = _NoUpload();
    final lookup = _Lookup({'old': 'https://cdn.example/original.webp'});
    await repo.save(_obs('old', DateTime.utc(2020, 1, 1)));

    await _coordinator(
      repo,
      uploads,
      lookup,
      network: () async => SyncNetworkType.unknown,
    ).syncPending();
    expect(lookup.calls, isEmpty);
    expect((await repo.findById('old'))!.remoteImageUrl, isNull);
    expect(uploads.uploadCount, 0);

    await _coordinator(
      repo,
      uploads,
      lookup,
      network: () async => throw StateError('radio unavailable'),
    ).syncPending();
    expect(lookup.calls, isEmpty);
    expect((await repo.findById('old'))!.remoteImageUrl, isNull);
    expect((await repo.findById('old'))!.syncStatus, SyncStatus.synced);
  });

  test('mobile data can recover a url while Wi-Fi-only blocks the upload', () async {
    final repo = MemoryObservationRepository();
    final uploads = _NoUpload();
    final lookup = _Lookup({'old': 'https://cdn.example/original.webp'});
    await repo.save(_obs('old', DateTime.utc(2020, 1, 1)));
    await repo.save(_obs(
      'queue',
      DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.pending,
      media: MediaSyncStatus.pending,
    ));

    final result = await _coordinator(
      repo,
      uploads,
      lookup,
      wifiOnly: true,
      network: () async => SyncNetworkType.mobile,
    ).syncPending();

    expect(result.blocked, isTrue);
    expect(uploads.uploadCount, 0);
    expect(lookup.calls, ['old']);
    expect((await repo.findById('old'))!.remoteImageUrl,
        'https://cdn.example/original.webp');
    expect((await repo.findById('queue'))!.syncStatus, SyncStatus.pending);
  });

  test('one pass queries only the oldest bounded batch', () async {
    final repo = MemoryObservationRepository();
    final lookup = _Lookup({
      'a': 'https://cdn.example/a.webp',
      'b': 'https://cdn.example/b.webp',
      'c': 'https://cdn.example/c.webp',
    });
    await repo.save(_obs('c', DateTime.utc(2022, 1, 1)));
    await repo.save(_obs('a', DateTime.utc(2020, 1, 1)));
    await repo.save(_obs('b', DateTime.utc(2021, 1, 1)));

    await _coordinator(
      repo,
      _NoUpload(),
      lookup,
      limit: 2,
    ).syncPending();

    expect(lookup.calls, ['a', 'b']);
    expect((await repo.findById('c'))!.remoteImageUrl, isNull);
    expect((await repo.findById('a'))!.remoteImageUrl, 'https://cdn.example/a.webp');
  });

  test('sqlite selects only fully synced rows that still lack a url', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(inMemoryDatabasePath);
    await AppDatabase.createSchema(db);
    final repo = SqliteObservationRepository(db: AppDatabase.withDatabase(db));
    addTearDown(db.close);

    await repo.save(_obs('oldest', DateTime.utc(2018, 1, 1), remote: '   '));
    await repo.save(_obs('middle', DateTime.utc(2019, 1, 1)));
    await repo.save(_obs('newest', DateTime.utc(2021, 1, 1)));
    await repo.save(_obs(
      'has-url',
      DateTime.utc(2017, 1, 1),
      remote: 'https://cdn.example/already.webp',
    ));
    await repo.save(_obs(
      'pending',
      DateTime.utc(2016, 1, 1),
      syncStatus: SyncStatus.pending,
      media: MediaSyncStatus.pending,
    ));
    await repo.save(_obs(
      'failed',
      DateTime.utc(2016, 2, 1),
      syncStatus: SyncStatus.failed,
      media: MediaSyncStatus.failed,
    ));
    await repo.save(_obs(
      'review',
      DateTime.utc(2016, 3, 1),
      syncStatus: SyncStatus.needsReview,
      media: MediaSyncStatus.failed,
    ));

    expect(await repo.idsMissingRemoteImageUrl(limit: 2), ['oldest', 'middle']);
    expect(await repo.idsMissingRemoteImageUrl(limit: 20),
        ['oldest', 'middle', 'newest']);

    await repo.updateRemoteImageUrl('middle', ' https://cdn.example/middle.webp ');
    final middle = await repo.findById('middle');
    expect(middle!.remoteImageUrl, 'https://cdn.example/middle.webp');
    expect(middle.syncStatus, SyncStatus.synced);
    expect(middle.mediaSyncStatus, MediaSyncStatus.uploaded);
    expect(middle.detections.single.classCode, 'D00');
    expect(await repo.idsMissingRemoteImageUrl(limit: 20), ['oldest', 'newest']);
  });
}

Observation _obs(
  String id,
  DateTime createdAt, {
  SyncStatus syncStatus = SyncStatus.synced,
  MediaSyncStatus media = MediaSyncStatus.uploaded,
  String? remote,
}) {
  return Observation(
    id: id,
    captureId: 'cap-$id',
    imagePath: '/tmp/missing-$id.jpg',
    createdAt: createdAt,
    latitude: 36.8,
    longitude: 10.1,
    actor: 'Municipality',
    syncStatus: syncStatus,
    mediaSyncStatus: media,
    remoteImageUrl: remote,
    agentResults: const [
      AgentResult(
        agent: 'road_damage',
        detections: [
          Detection(
            agent: 'road_damage',
            classCode: 'D00',
            confidence: 0.5,
            box: BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
          ),
        ],
      ),
    ],
  );
}

SyncCoordinator _coordinator(
  MemoryObservationRepository repo,
  _NoUpload uploads,
  _Lookup lookup, {
  SyncNetworkReader? network,
  bool wifiOnly = false,
  int limit = remoteUrlRecoveryBatchLimit,
}) {
  return SyncCoordinator(
    repo,
    uploads,
    readSettings: () async => SyncSettings(
      wifiOnly: wifiOnly,
      retentionDays: 0,
    ),
    readNetwork: network ?? () async => SyncNetworkType.wifi,
    readStoredOriginalUrl: lookup.call,
    remoteUrlRecoveryLimit: limit,
  );
}

class _NoUpload implements ObservationSyncClient {
  int uploadCount = 0;

  @override
  Future<void> upload(
    Observation observation, {
    required String idempotencyKey,
    SyncCancelToken? cancelToken,
    ObservationRepository? repository,
  }) async {
    uploadCount++;
    throw StateError('upload must not run');
  }
}

class _Lookup {
  _Lookup(this.urls, {this.throwFor = const {}});

  final Map<String, String?> urls;
  final Set<String> throwFor;
  final calls = <String>[];

  Future<String?> call(String id) async {
    calls.add(id);
    if (throwFor.contains(id)) throw StateError('network down');
    return urls[id];
  }
}
