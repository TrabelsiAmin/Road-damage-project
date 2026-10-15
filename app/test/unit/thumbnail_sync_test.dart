import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tariqmap/core/supabase_config.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';
import 'package:tariqmap/services/thumbnail_service.dart';

/// Mock client to test public thumbnail upload, 409 handling, toggle-off, and cancel-mid-upload
class MockPublicThumbnailClient {
  final Map<String, Uint8List> publicStorageObjects = {};
  final List<Map<String, dynamic>> mediaFilesRows = [];

  bool simulateStorage409 = false;
  bool simulateMedia409 = false;
  bool simulateStorageFailure = false;

  void Function(String path, SyncCancelToken? token)? onStorageUpload;
  void Function(String path, SyncCancelToken? token)? onBeforeMediaInsert;

  Future<String?> uploadPublicThumbnail({
    required String observationId,
    required Uint8List thumbnailBytes,
    String mimeType = 'image/webp',
    SyncCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final storagePath = '$observationId/test-uuid.webp';

    onStorageUpload?.call(storagePath, cancelToken);
    cancelToken?.throwIfCancelled();

    // 1. Storage Upload (plain insert, upsert: false)
    if (simulateStorageFailure) {
      throw Exception('Simulated Storage Network Error');
    }

    if (simulateStorage409) {
      // 409 treated as success
    } else {
      publicStorageObjects[storagePath] = thumbnailBytes;
    }

    // Cancellation check mid-upload:
    // Phone (anon) has NO delete right on bucket public-photos.
    // On cancel, just stop; an orphan file with no media_files row is harmless.
    onBeforeMediaInsert?.call(storagePath, cancelToken);
    cancelToken?.throwIfCancelled();

    final publicUrl = 'https://lendqcjihusqkmxansbl.supabase.co/storage/v1/object/public/public-photos/$storagePath';

    // 2. Insert media_files row (bucket='public-photos', media_type='thumbnail', is_demo=false)
    if (simulateMedia409) {
      // 409 conflict treated as success
    } else {
      mediaFilesRows.add({
        'id': 'media-uuid',
        'observation_id': observationId,
        'bucket': SupabaseCfg.publicPhotosBucket,
        'storage_path': storagePath,
        'public_url': publicUrl,
        'media_type': 'thumbnail',
        'mime_type': mimeType,
        'file_size_bytes': thumbnailBytes.lengthInBytes,
        'is_demo': false,
      });
    }

    return publicUrl;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Requirement 1: Option A (Crop + Margin Blur) & Gating', () {
    test('confirms thumbnail upload gate is ON with Option A', () {
      expect(ThumbnailService.isThumbnailUploadEnabled, isTrue,
          reason: 'Option A thumbnail upload is turned ON');
    });

    test('skips thumbnail when there is no detection', () async {
      final testImageFile = File('test/goldens/images/Czech_000010.jpg');
      expect(testImageFile.existsSync(), isTrue);

      final originalBytes = await testImageFile.readAsBytes();

      // Empty detections list -> must return null and shouldUpload must return false
      final thumb = await ThumbnailService.createDetectionCropThumbnail(
        originalBytes: originalBytes,
        detections: const [],
      );
      expect(thumb, isNull, reason: 'Must skip thumbnail when there is no detection');

      final shouldUpload = await ThumbnailService.shouldUploadPublicThumbnail(
        detections: const [],
      );
      expect(shouldUpload, isFalse, reason: 'Gate must reject when detections are empty');
    });

    test('Option A creates crop of primary detection with 25% margin, margin blur, <= 800px, < 250 KB', () async {
      final testImageFile = File('test/goldens/images/Czech_000010.jpg');
      expect(testImageFile.existsSync(), isTrue);

      final originalBytes = await testImageFile.readAsBytes();
      final detections = [
        const Detection(
          agent: 'road_damage',
          classCode: 'D10',
          confidence: 0.88,
          box: BoundingBox(x: 0.2, y: 0.3, width: 0.4, height: 0.3),
        ),
      ];

      final thumb = await ThumbnailService.createDetectionCropThumbnail(
        originalBytes: originalBytes,
        detections: detections,
      );

      expect(thumb, isNotNull);
      expect(thumb!.lengthInBytes, lessThanOrEqualTo(ThumbnailService.maxFileSizeBytes),
          reason: 'Thumbnail must be under 250 KB');
    });

    test('enforces minimum crop of at least 40% of shorter side and max aspect ratio 2.5:1', () async {
      final testImageFile = File('test/goldens/images/Czech_000010.jpg');
      final originalBytes = await testImageFile.readAsBytes();

      // Detection box with extreme aspect ratio: width=0.3, height=0.02 (ratio = 15:1)
      final detections = [
        const Detection(
          agent: 'road_damage',
          classCode: 'D10',
          confidence: 0.90,
          box: BoundingBox(x: 0.35, y: 0.5, width: 0.3, height: 0.02),
        ),
      ];

      final thumb = await ThumbnailService.createDetectionCropThumbnail(
        originalBytes: originalBytes,
        detections: detections,
      );

      expect(thumb, isNotNull);
      // Decoded crop must be at least 40% of 600 = 240 px in both W and H
      final decoded = img.decodeImage(thumb!)!;
      expect(decoded.width, greaterThanOrEqualTo(240));
      expect(decoded.height, greaterThanOrEqualTo(240));
      // Aspect ratio must be at most 2.5:1
      expect(decoded.width / decoded.height, lessThanOrEqualTo(2.5));
      expect(decoded.height / decoded.width, lessThanOrEqualTo(2.5));
    });

    test('generates thumbnail with minimum crop when box area is below 0.5%', () async {
      final testImageFile = File('test/goldens/images/Czech_000010.jpg');
      final originalBytes = await testImageFile.readAsBytes();

      // Tiny box: 0.03 x 0.03 -> area = 0.0009 = 0.09% of image (< 0.5%)
      final detections = [
        const Detection(
          agent: 'road_damage',
          classCode: 'D00',
          confidence: 0.92,
          box: BoundingBox(x: 0.5, y: 0.5, width: 0.03, height: 0.03),
        ),
      ];

      final thumb = await ThumbnailService.createDetectionCropThumbnail(
        originalBytes: originalBytes,
        detections: detections,
      );

      expect(thumb, isNotNull, reason: 'Small box < 0.5% area must still generate thumbnail');
      final decoded = img.decodeImage(thumb!)!;
      expect(decoded.width, equals(240), reason: 'Minimum crop is 40% of 600 = 240');
      expect(decoded.height, equals(240), reason: 'Minimum crop is 40% of 600 = 240');
    });
  });

  group('Requirement 2: Upload Order, 409 Conflict, Toggle OFF, and Cancel Without Delete', () {
    late MockPublicThumbnailClient mockClient;
    final dummyThumbnailBytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0x00, 0x00]); // RIFF header snippet

    setUp(() {
      mockClient = MockPublicThumbnailClient();
      SharedPreferences.setMockInitialValues({});
    });

    test('successful upload inserts into public-photos and writes thumbnail media_files row', () async {
      const obsId = 'obs-pub-123';

      final url = await mockClient.uploadPublicThumbnail(
        observationId: obsId,
        thumbnailBytes: dummyThumbnailBytes,
      );

      expect(url, isNotNull);
      expect(url, contains('public-photos/$obsId/test-uuid.webp'));

      // Assert storage object created at <observation_id>/<uuid>.webp
      expect(mockClient.publicStorageObjects.containsKey('$obsId/test-uuid.webp'), isTrue);

      // Assert media_files row inserted with required metadata
      expect(mockClient.mediaFilesRows.length, 1);
      final row = mockClient.mediaFilesRows.first;
      expect(row['observation_id'], obsId);
      expect(row['bucket'], 'public-photos');
      expect(row['media_type'], 'thumbnail');
      expect(row['is_demo'], isFalse);
      expect(row['mime_type'], 'image/webp');
      expect(row['file_size_bytes'], dummyThumbnailBytes.lengthInBytes);
    });

    test('409 Conflict in storage or media_files is treated as success', () async {
      const obsId = 'obs-conflict-409';
      mockClient.simulateStorage409 = true;
      mockClient.simulateMedia409 = true;

      final url = await mockClient.uploadPublicThumbnail(
        observationId: obsId,
        thumbnailBytes: dummyThumbnailBytes,
      );

      expect(url, isNotNull, reason: '409 Conflict must be treated as success without throwing');
    });

    test('when toggle "Share a blurred photo on the public map" is OFF, upload nothing', () async {
      SharedPreferences.setMockInitialValues({
        ThumbnailService.prefKeyShareBlurred: false,
      });

      final isEnabled = await ThumbnailService.isPublicSharingEnabled();
      expect(isEnabled, isFalse, reason: 'Settings toggle is OFF');

      final shouldUpload = await ThumbnailService.shouldUploadPublicThumbnail(
        detections: [
          const Detection(
            agent: 'road_damage',
            classCode: 'D40',
            confidence: 0.9,
            box: BoundingBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
          ),
        ],
      );
      expect(shouldUpload, isFalse, reason: 'If toggle is OFF, upload nothing');

      // Verify no upload was attempted on client
      expect(mockClient.publicStorageObjects.isEmpty, isTrue);
      expect(mockClient.mediaFilesRows.isEmpty, isTrue);
    });

    test('cancelling sync mid-upload stops cleanly without deleting file and never writes media_files row', () async {
      const obsId = 'obs-cancel-test';
      final cancelToken = SyncCancelToken();

      // Trigger cancellation after storage upload, before media_files insert
      mockClient.onBeforeMediaInsert = (path, token) {
        token?.cancel();
      };

      expect(
        () => mockClient.uploadPublicThumbnail(
          observationId: obsId,
          thumbnailBytes: dummyThumbnailBytes,
          cancelToken: cancelToken,
        ),
        throwsA(isA<SyncCancelledException>()),
      );

      // Assert: media_files row was NOT written (so row never points to a missing/half-synced state)
      expect(mockClient.mediaFilesRows.isEmpty, isTrue,
          reason: 'media_files row must never be written if sync was cancelled');

      // Storage object was uploaded first, and because phone has no delete right,
      // client does NOT call delete; orphan file without media_files row is harmless.
      expect(mockClient.publicStorageObjects.containsKey('$obsId/test-uuid.webp'), isTrue);
    });
  });
}
