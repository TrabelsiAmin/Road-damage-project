import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/widgets/observation_photo.dart';

void main() {
  test('photo source distinguishes the four states', () {
    expect(
      resolvePhotoSource(
        localFileExists: true,
        remoteImageUrl: 'https://cdn.example/a.webp',
        syncStatus: SyncStatus.pending,
        mediaSyncStatus: MediaSyncStatus.pending,
      ).kind,
      PhotoSourceKind.localAvailable,
    );
    expect(
      resolvePhotoSource(
        localFileExists: false,
        remoteImageUrl: 'https://cdn.example/a.webp',
        syncStatus: SyncStatus.synced,
        mediaSyncStatus: MediaSyncStatus.uploaded,
      ).kind,
      PhotoSourceKind.remoteAvailable,
    );
    expect(
      resolvePhotoSource(
        localFileExists: false,
        remoteImageUrl: '  ',
        syncStatus: SyncStatus.synced,
        mediaSyncStatus: MediaSyncStatus.uploaded,
      ).kind,
      PhotoSourceKind.unavailable,
    );
    for (final status in [
      SyncStatus.pending,
      SyncStatus.failed,
      SyncStatus.needsReview,
    ]) {
      expect(
        resolvePhotoSource(
          localFileExists: false,
          remoteImageUrl: 'https://cdn.example/a.webp',
          syncStatus: status,
          mediaSyncStatus: MediaSyncStatus.failed,
        ).kind,
        PhotoSourceKind.uploadIncomplete,
        reason: status.name,
      );
    }
  });
}
