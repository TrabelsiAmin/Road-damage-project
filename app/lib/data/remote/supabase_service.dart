import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../models/observation.dart';
import '../../services/image_compressor.dart';
import '../../services/sync_cancel_token.dart';

/// Central service for Supabase interactions from the mobile app.
///
/// Responsibilities:
///  1. Upload captured images to the [SupabaseCfg.imagesBucket] storage bucket.
///  2. Write observation + detection metadata rows directly to Supabase DB.
///
/// The app uses the Supabase anon key governed by RLS policies.
/// The service-role secret stays server-side only (backend/.env).
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static const _uuid = Uuid();

  SupabaseClient get _client => Supabase.instance.client;

  // Initialisation

  /// Call once at app startup before runApp.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url:            SupabaseCfg.url,
      publishableKey: SupabaseCfg.anonKey,
      debug: kDebugMode,
    );
    debugPrint('[SupabaseService] Initialized');
  }

  // Image upload

  /// Uploads a still-image capture to Supabase Storage.
  /// The image is compressed to WebP before upload to reduce storage usage.
  /// Uses a unique object path and plain insert (upsert: false).
  /// Returns the public URL of the stored object, or null on failure.
  Future<String?> uploadObservationImage({
    required String observationId,
    required String captureId,
    required File imageFile,
    SyncCancelToken? cancelToken,
  }) async {
    try {
      cancelToken?.throwIfCancelled();
      // Compress to WebP — saves 40-60% storage vs original JPEG/PNG
      final compressed = await ImageCompressor.compressToWebP(imageFile);
      cancelToken?.throwIfCancelled();

      // Task D: Unique object path plus plain upload (no upsert)
      final storagePath = '$observationId/${_uuid.v4()}.${compressed.extension}';

      await _client.storage
          .from(SupabaseCfg.imagesBucket)
          .uploadBinary(
            storagePath,
            compressed.bytes,
            fileOptions: FileOptions(
              contentType: compressed.mimeType,
              upsert: false,
            ),
          );

      cancelToken?.throwIfCancelled();

      final url = _client.storage
          .from(SupabaseCfg.imagesBucket)
          .getPublicUrl(storagePath);

      debugPrint('[SupabaseService] Image uploaded (WebP): $url '
          '(saved ${compressed.savedBytes ~/ 1024} KB)');

      await _recordMediaFile(
        observationId: observationId,
        bucket: SupabaseCfg.imagesBucket,
        storagePath: storagePath,
        publicUrl: url,
        mediaType: 'image',
        mimeType: compressed.mimeType,
        fileSizeBytes: compressed.compressedSizeBytes,
        cancelToken: cancelToken,
      );
      return url;
    } on SyncCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('[SupabaseService] Image upload failed: $e');
      return null;
    }
  }

  /// Uploads raw JPEG/YUV bytes (e.g. from a camera stream) to Supabase Storage.
  /// The bytes are compressed to WebP before upload.
  Future<String?> uploadObservationImageBytes({
    required String observationId,
    required String captureId,
    required Uint8List bytes,
    String mimeType = 'image/jpeg',
    SyncCancelToken? cancelToken,
  }) async {
    try {
      cancelToken?.throwIfCancelled();
      final compressed = await ImageCompressor.compressBytes(bytes);
      cancelToken?.throwIfCancelled();

      final storagePath = '$observationId/${_uuid.v4()}.${compressed.extension}';
      await _client.storage
          .from(SupabaseCfg.imagesBucket)
          .uploadBinary(
            storagePath,
            compressed.bytes,
            fileOptions: FileOptions(
              contentType: compressed.mimeType,
              upsert: false,
            ),
          );

      cancelToken?.throwIfCancelled();

      final url = _client.storage
          .from(SupabaseCfg.imagesBucket)
          .getPublicUrl(storagePath);

      debugPrint('[SupabaseService] Frame image uploaded (WebP): $url');
      await _recordMediaFile(
        observationId: observationId,
        bucket: SupabaseCfg.imagesBucket,
        storagePath: storagePath,
        publicUrl: url,
        mediaType: 'image',
        mimeType: compressed.mimeType,
        fileSizeBytes: compressed.compressedSizeBytes,
        cancelToken: cancelToken,
      );
      return url;
    } on SyncCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('[SupabaseService] Frame image upload failed: $e');
      return null;
    }
  }

  /// Uploads a public blurred thumbnail to bucket `public-photos`.
  /// Bucket path policy requires:
  ///   bucket_id = 'public-photos' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|jpg)$'
  ///
  /// Uses a deterministic object name `<observation_id>/<uuid_v5>.webp`, derived via
  /// UUID v5 from the observation ID using [Namespace.url.value].
  /// This ensures retries never create orphan files and avoids random UUID accumulation.
  ///
  /// Order:
  ///   1. Plain insert (upsert: false) to storage at `<observation_id>/<uuid_v5>.webp`.
  ///      Logs HTTP status; treats 409 conflict as success.
  ///   2. Check cancellation (on cancel, just stop; orphan file with no media_files row is harmless).
  ///   3. Plain insert into `media_files` with `bucket='public-photos', media_type='thumbnail', is_demo=false`.
  ///      Logs HTTP status; treats 409 conflict as success; does NOT swallow other errors.
  Future<String?> uploadPublicThumbnail({
    required String observationId,
    required Uint8List thumbnailBytes,
    String mimeType = 'image/webp',
    SyncCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final fileUuid = _uuid.v5(Namespace.url.value, observationId);
    final storagePath = '$observationId/$fileUuid.webp';

    try {
      await _client.storage
          .from(SupabaseCfg.publicPhotosBucket)
          .uploadBinary(
            storagePath,
            thumbnailBytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );
      debugPrint('[ThumbnailUpload] Storage upload succeeded: HTTP 200/201 path=$storagePath');
    } on StorageException catch (e) {
      if (e.statusCode == '409' ||
          e.message.toLowerCase().contains('already exists') ||
          e.message.toLowerCase().contains('duplicate')) {
        debugPrint('[ThumbnailUpload] Storage upload duplicate (treated as success): HTTP 409 path=$storagePath');
      } else {
        debugPrint('[ThumbnailUpload] Storage upload failed: HTTP ${e.statusCode} ${e.message} path=$storagePath');
        rethrow;
      }
    } catch (e) {
      debugPrint('[ThumbnailUpload] Storage upload failed: $e path=$storagePath');
      rethrow;
    }

    // Cancellation check immediately after storage upload:
    // Phone has no delete permissions; on cancel, just stop.
    cancelToken?.throwIfCancelled();

    final publicUrl = _client.storage
        .from(SupabaseCfg.publicPhotosBucket)
        .getPublicUrl(storagePath);

    final mediaId = _uuid.v5(Namespace.url.value, '$observationId:thumbnail');
    try {
      await _client.from(SupabaseCfg.tableMediaFiles).insert({
        'id': mediaId,
        'observation_id': observationId,
        'bucket': SupabaseCfg.publicPhotosBucket,
        'storage_path': storagePath,
        'public_url': publicUrl,
        'media_type': 'thumbnail',
        'mime_type': mimeType,
        'file_size_bytes': thumbnailBytes.lengthInBytes,
        'uploaded_at': DateTime.now().toUtc().toIso8601String(),
        'is_demo': false,
      });
      debugPrint('[ThumbnailUpload] media_files insert succeeded: HTTP 201 row=$mediaId');
    } on PostgrestException catch (e) {
      if (_isConflict(e)) {
        debugPrint('[ThumbnailUpload] media_files duplicate (treated as success): HTTP 409 code=${e.code} row=$mediaId');
      } else {
        debugPrint('[ThumbnailUpload] media_files insert failed: HTTP ${e.code ?? "error"} ${e.message} row=$mediaId');
        rethrow;
      }
    } catch (e) {
      debugPrint('[ThumbnailUpload] media_files insert failed: $e row=$mediaId');
      rethrow;
    }

    return publicUrl;
  }

  // Observation sync

  /// Loads the most recent image for an observation as decoded bytes.
  Future<Uint8List?> downloadObservationImage({
    required String observationId,
  }) async {
    try {
      final rows = await _client
          .from(SupabaseCfg.tableMediaFiles)
          .select('bucket, storage_path, public_url')
          .eq('observation_id', observationId)
          .order('uploaded_at', ascending: false)
          .limit(1);

      if (rows.isEmpty) return null;
      final row = rows.first;
      final bucket = row['bucket'] as String?;
      final storagePath = row['storage_path'] as String?;
      if (bucket == null || storagePath == null) return null;

      try {
        return await _client.storage.from(bucket).download(storagePath);
      } catch (storageError) {
        debugPrint('[SupabaseService] Storage download failed: $storageError');
      }

      final publicUrl = row['public_url'] as String?;
      if (publicUrl == null || publicUrl.isEmpty) return null;
      final response = await http.get(Uri.parse(publicUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[SupabaseService] Image URL returned ${response.statusCode}');
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('[SupabaseService] Observation image lookup failed: $e');
      return null;
    }
  }

  /// Syncs a complete observation directly to Supabase DB.
  /// Also uploads the captured image to Storage if [imageFile] is provided.
  /// Uses plain inserts and treats 409 conflict as success (Task D).
  Future<void> syncObservation(
    Observation obs, {
    File? imageFile,
    String? organizationId,
    SyncCancelToken? cancelToken,
  }) async {
    final capturedAt = obs.createdAt.toUtc().toIso8601String();
    final orgId = organizationId ?? '11111111-1111-4111-8111-111111111111';

    cancelToken?.throwIfCancelled();

    // 1. Observation row (plain insert, no device_id to public tables, 409 as success)
    try {
      await _client.from(SupabaseCfg.tableObservations).insert({
        'id':                    obs.id,
        'capture_id':            obs.captureId,
        'parent_observation_id': null,
        'created_by':            null,
        'organization_id':       orgId,
        'device_id':             null, // Task A: do not send to public-readable tables
        'source':                'camera',
        'captured_at':           capturedAt,
        'image_width':           obs.imageWidth,
        'image_height':          obs.imageHeight,
        'priority_score':        obs.priorityScore,
        'priority_label':        obs.priorityLabel,
        'anomaly_type':          _anomalyTypeFor(obs),
        'model_bundle_version':  obs.modelBundleVersion,
        'created_at':            capturedAt,
        'is_demo':               false,
        'status':                'unconfirmed',
      });
    } on PostgrestException catch (e) {
      if (!_isConflict(e)) {
        debugPrint('[SupabaseService] observations insert error: ${e.code} ${e.message}');
        rethrow;
      }
    }

    cancelToken?.throwIfCancelled();

    // 2. Location row (plain insert, 409 as success)
    try {
      await _client.from(SupabaseCfg.tableLocations).insert({
        'observation_id':  obs.id,
        'latitude':        obs.latitude,
        'longitude':       obs.longitude,
        'accuracy_meters': obs.accuracyMeters,
        'captured_at':     capturedAt,
      });
    } on PostgrestException catch (e) {
      if (!_isConflict(e)) {
        debugPrint('[SupabaseService] locations insert error: ${e.code} ${e.message}');
        rethrow;
      }
    }

    cancelToken?.throwIfCancelled();

    // 3. Agent runs + detections (decoupled child inserts with separate logging)
    for (final result in obs.agentResults) {
      cancelToken?.throwIfCancelled();
      final agentRunId = _uuid.v4();
      try {
        await _client.from(SupabaseCfg.tableAgentRuns).insert({
          'id':                   agentRunId,
          'observation_id':       obs.id,
          'agent':                result.agent,
          'error':                result.error,
          'is_mock':              result.isMock,
          'latency_ms':           result.latencyMs,
          'model_bundle_version': obs.modelBundleVersion,
        });
      } on PostgrestException catch (e) {
        if (!_isConflict(e)) {
          debugPrint('[SupabaseService] agent_runs insert error: ${e.code} ${e.message}');
          rethrow;
        }
      }

      if (result.detections.isNotEmpty) {
        cancelToken?.throwIfCancelled();
        final detections = result.detections.map((d) => {
          'id':                   _uuid.v4(),
          'observation_id':       obs.id,
          'agent_run_id':         agentRunId,
          'media_id':             null,
          'class_code':           d.classCode,
          'confidence':           d.confidence,
          'box_x':                d.box.x,
          'box_y':                d.box.y,
          'box_w':                d.box.width,
          'box_h':                d.box.height,
          'frame_index':          d.frameIndex,
          'is_mock':              result.isMock,
          'model_bundle_version': d.modelBundleVersion,
          'detected_at':          d.timestamp?.toUtc().toIso8601String() ?? capturedAt,
        }).toList();

        try {
          await _client.from(SupabaseCfg.tableDetections).insert(detections);
        } on PostgrestException catch (e) {
          if (!_isConflict(e)) {
            debugPrint('[SupabaseService] detections insert error: ${e.code} ${e.message}');
            rethrow;
          }
        }
      }
    }

    cancelToken?.throwIfCancelled();

    // 4. Upload image to Storage (plain upload, unique path)
    if (imageFile != null && await imageFile.exists()) {
      await uploadObservationImage(
        observationId: obs.id,
        captureId: obs.captureId,
        imageFile: imageFile,
        cancelToken: cancelToken,
      );
    }

    cancelToken?.throwIfCancelled();

    // 5. Sync receipt (plain insert, 409 as success)
    try {
      await _client.from(SupabaseCfg.tableSyncReceipts).insert({
        'observation_id':  obs.id,
        'idempotency_key': _uuid.v4(),
        'payload_hash':    obs.id,
      });
    } on PostgrestException catch (e) {
      if (!_isConflict(e)) {
        debugPrint('[SupabaseService] sync_receipts insert error: ${e.code} ${e.message}');
        rethrow;
      }
    }

    debugPrint('[SupabaseService] Observation synced: ${obs.id}');
  }

  // Private helpers

  bool _isConflict(PostgrestException e) {
    return e.code == '23505' ||
        e.code == '409' ||
        e.message.toLowerCase().contains('duplicate key') ||
        e.message.toLowerCase().contains('unique constraint') ||
        e.message.toLowerCase().contains('already exists');
  }

  String? _anomalyTypeFor(Observation obs) {
    final detections = [...obs.detections]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    for (final detection in detections) {
      if (TariqMapConstants.allCodes.contains(detection.classCode)) {
        return detection.classCode;
      }
    }
    return null;
  }

  Future<void> _recordMediaFile({
    required String? observationId,
    required String bucket,
    required String storagePath,
    required String publicUrl,
    required String mediaType,
    required String mimeType,
    required int fileSizeBytes,
    SyncCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    try {
      await _client.from(SupabaseCfg.tableMediaFiles).insert({
        'id':              _uuid.v4(),
        'observation_id':  observationId,
        'bucket':          bucket,
        'storage_path':    storagePath,
        'public_url':      publicUrl,
        'media_type':      mediaType,
        'mime_type':       mimeType,
        'file_size_bytes': fileSizeBytes,
        'uploaded_at':     DateTime.now().toUtc().toIso8601String(),
        'is_demo':         false,
      });
    } on PostgrestException catch (e) {
      if (!_isConflict(e)) {
        debugPrint('[SupabaseService] media_files insert warning: ${e.code} ${e.message}');
      }
    } catch (e) {
      debugPrint('[SupabaseService] media_files insert warning: $e');
    }
  }
}
