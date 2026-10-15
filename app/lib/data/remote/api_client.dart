import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../inference/preprocessing.dart';
import '../../models/observation.dart';
import '../../services/image_compressor.dart';
import '../../services/observation_repository.dart';
import '../../services/thumbnail_service.dart';

class ApiClient implements ObservationSyncClient {
  ApiClient();

  final _uuid = const Uuid();

  // Hardcode organizations similar to python backend for demo purposes
  static const _organizationIds = {
    "Municipality": "11111111-1111-4111-8111-111111111111",
    "Ministry of Equipment": "22222222-2222-4222-8222-222222222222",
    "Tunisia Autoroutes": "33333333-3333-4333-8333-333333333333",
  };

  static String _organizationId(String actor) {
    return _organizationIds[actor] ?? _organizationIds["Municipality"]!;
  }

  static String? _anomalyTypeFor(Observation obs) {
    if (obs.detections.isEmpty) return null;
    return obs.detections.first.classCode;
  }

  static Future<Map<String, dynamic>> buildObservationPayload(Observation obs) async {
    final capturedAt = obs.createdAt.toUtc().toIso8601String();
    final organizationId = _organizationId(obs.actor);

    var imageWidth = obs.imageWidth;
    var imageHeight = obs.imageHeight;
    final imagePath = obs.annotatedImagePath ?? obs.imagePath;
    final imageFile = File(imagePath);
    if ((imageWidth == null || imageHeight == null) && await imageFile.exists()) {
      try {
        final bytes = await imageFile.readAsBytes();
        final decoded = decodeAndOrient(bytes);
        imageWidth = decoded.width;
        imageHeight = decoded.height;
      } catch (_) {}
    }

    return {
      "id": obs.id,
      "capture_id": obs.captureId,
      "parent_observation_id": null,
      "created_by": null,
      "organization_id": organizationId,
      "device_id": null, // Task A: do not send to public-readable tables
      "source": "camera",
      "captured_at": capturedAt,
      "image_width": imageWidth,
      "image_height": imageHeight,
      "priority_score": obs.priorityScore,
      "priority_label": obs.priorityLabel,
      "anomaly_type": _anomalyTypeFor(obs),
      "model_bundle_version": obs.modelBundleVersion.isNotEmpty
          ? obs.modelBundleVersion
          : TariqMapConstants.modelBundleVersion,
      "created_at": capturedAt,
      "is_demo": false,
      "status": "unconfirmed",
    };
  }

  bool _isConflict(PostgrestException e) {
    return e.code == '23505' ||
        e.code == '409' ||
        e.message.toLowerCase().contains('duplicate key') ||
        e.message.toLowerCase().contains('unique constraint') ||
        e.message.toLowerCase().contains('already exists');
  }

  Future<void> _safeInsert(
    String table,
    dynamic data, {
    SyncCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    try {
      await Supabase.instance.client.from(table).insert(data);
    } on PostgrestException catch (e) {
      if (_isConflict(e)) {
        debugPrint('[$table] 409/duplicate conflict treated as success');
        return;
      }
      debugPrint('[$table] Insert error: ${e.code} ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[$table] Insert failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> upload(
    Observation obs, {
    required String idempotencyKey,
    SyncCancelToken? cancelToken,
  }) async {
    final client = Supabase.instance.client;
    final capturedAt = obs.createdAt.toUtc().toIso8601String();
    final imagePath = obs.annotatedImagePath ?? obs.imagePath;
    final imageFile = File(imagePath);

    final observationPayload = await buildObservationPayload(obs);
    debugPrint('[Pipeline:SyncPayload] Preparing sync payload for ${obs.id} '
        'with ${obs.detections.length} detections, size: ${observationPayload["image_width"]}x${observationPayload["image_height"]}');

    cancelToken?.throwIfCancelled();

    // 1. Observations Table (plain insert, no device_id to public tables, 409 treated as success)
    await _safeInsert(
      SupabaseCfg.tableObservations,
      observationPayload,
      cancelToken: cancelToken,
    );

    cancelToken?.throwIfCancelled();

    // 2. Locations Table (plain insert, 409 treated as success)
    await _safeInsert(
      SupabaseCfg.tableLocations,
      {
        "observation_id": obs.id,
        "latitude": obs.latitude,
        "longitude": obs.longitude,
        "accuracy_meters": obs.accuracyMeters,
        "captured_at": capturedAt,
      },
      cancelToken: cancelToken,
    );

    // 3. Agent runs and detections (decoupled child inserts with separate error logging)
    for (final result in obs.agentResults) {
      cancelToken?.throwIfCancelled();
      final agentRunId = _uuid.v4();

      try {
        await _safeInsert(
          SupabaseCfg.tableAgentRuns,
          {
            "id": agentRunId,
            "observation_id": obs.id,
            "agent": result.agent,
            "error": result.error,
            "is_mock": result.isMock,
            "latency_ms": result.latencyMs,
            "model_bundle_version": obs.modelBundleVersion,
          },
          cancelToken: cancelToken,
        );
      } catch (e) {
        debugPrint('[ApiClient] agent_runs insert failed for ${obs.id}: $e');
        rethrow;
      }

      if (result.detections.isNotEmpty) {
        cancelToken?.throwIfCancelled();
        final detectionsData = result.detections.map((d) => {
          "id": _uuid.v4(),
          "observation_id": obs.id,
          "agent_run_id": agentRunId,
          "media_id": null,
          "class_code": d.classCode,
          "confidence": d.confidence,
          "box_x": d.box.x,
          "box_y": d.box.y,
          "box_w": d.box.width,
          "box_h": d.box.height,
          "frame_index": d.frameIndex,
          "is_mock": result.isMock,
          "model_bundle_version": d.modelBundleVersion,
          "detected_at": (d.timestamp ?? obs.createdAt).toUtc().toIso8601String(),
        }).toList();

        try {
          await _safeInsert(
            SupabaseCfg.tableDetections,
            detectionsData,
            cancelToken: cancelToken,
          );
        } catch (e) {
          debugPrint('[ApiClient] detections insert failed for ${obs.id}: $e');
          rethrow;
        }
      }
    }

    cancelToken?.throwIfCancelled();

    // 4. Image Upload to Storage (unique path, plain insert with upsert: false)
    if (await imageFile.exists()) {
      cancelToken?.throwIfCancelled();
      final compressed = await ImageCompressor.compressToWebP(imageFile);
      cancelToken?.throwIfCancelled();

      // Task D: Unique object path plus plain upload
      final storagePath = '${obs.id}/${_uuid.v4()}.${compressed.extension}';

      try {
        await client.storage
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

        final publicUrl = client.storage
            .from(SupabaseCfg.imagesBucket)
            .getPublicUrl(storagePath);

        // Record in media_files
        await _safeInsert(
          SupabaseCfg.tableMediaFiles,
          {
            "id": _uuid.v4(),
            "observation_id": obs.id,
            "bucket": SupabaseCfg.imagesBucket,
            "storage_path": storagePath,
            "public_url": publicUrl,
            "media_type": "image",
            "mime_type": compressed.mimeType,
            "file_size_bytes": compressed.compressedSizeBytes,
            "uploaded_at": DateTime.now().toUtc().toIso8601String(),
            "is_demo": false,
          },
          cancelToken: cancelToken,
        );
      } catch (e) {
        debugPrint('[ApiClient] Image upload or media_files record error: $e');
        rethrow;
      }

      // 4b. Public Blurred Thumbnail Step (Option A: Crop-and-Blur Path)
      // Only executes after the existing full-resolution sync step succeeds.
      // Skips when there are no detections or when toggle is OFF.
      cancelToken?.throwIfCancelled();
      final shouldUpload = await ThumbnailService.shouldUploadPublicThumbnail(
        detections: obs.detections,
      );
      if (shouldUpload) {
        final originalBytes = await imageFile.readAsBytes();
        final thumbBytes = await ThumbnailService.createDetectionCropThumbnail(
          originalBytes: originalBytes,
          detections: obs.detections,
        );
        if (thumbBytes != null && thumbBytes.lengthInBytes <= ThumbnailService.maxFileSizeBytes) {
          // Failure or cancellation here bubbles up to SyncCoordinator
          // ensuring a failed/cancelled upload never leaves observation marked synced.
          await uploadPublicThumbnail(
            observationId: obs.id,
            thumbnailBytes: thumbBytes,
            cancelToken: cancelToken,
          );
        }
      }
    }

    cancelToken?.throwIfCancelled();

    // 5. Sync receipts table (plain insert, 409 treated as success)
    await _safeInsert(
      SupabaseCfg.tableSyncReceipts,
      {
        "observation_id": obs.id,
        "idempotency_key": idempotencyKey,
        "payload_hash": "flutter-direct-sync",
      },
      cancelToken: cancelToken,
    );
  }

  /// Uploads a public cropped & blurred thumbnail to bucket `public-photos`.
  /// Order:
  ///   1. Plain insert (upsert: false) to storage at `<observation_id>/<uuid>.webp`.
  ///   2. Check cancellation (on cancel, just stop; orphan file with no media_files row is harmless).
  ///   3. Plain insert into `media_files` with `bucket='public-photos', media_type='thumbnail', is_demo=false`.
  /// Treats 409 conflict as success.
  Future<String?> uploadPublicThumbnail({
    required String observationId,
    required Uint8List thumbnailBytes,
    String mimeType = 'image/webp',
    SyncCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final client = Supabase.instance.client;
    final storagePath = '$observationId/${_uuid.v4()}.webp';

    // 1. Plain upload to public-photos storage (upsert: false)
    try {
      await client.storage
          .from(SupabaseCfg.publicPhotosBucket)
          .uploadBinary(
            storagePath,
            thumbnailBytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      if (e.statusCode == '409' ||
          e.message.toLowerCase().contains('already exists') ||
          e.message.toLowerCase().contains('duplicate')) {
        debugPrint('[ApiClient] public-photos 409 treated as success: $storagePath');
      } else {
        debugPrint('[ApiClient] public-photos storage upload failed: ${e.message}');
        rethrow;
      }
    } catch (e) {
      debugPrint('[ApiClient] public-photos storage upload failed: $e');
      rethrow;
    }

    // Cancellation check immediately after storage upload:
    // Phone has no delete permissions; on cancel, just stop (orphan storage object is harmless without media_files row)
    cancelToken?.throwIfCancelled();

    final publicUrl = client.storage
        .from(SupabaseCfg.publicPhotosBucket)
        .getPublicUrl(storagePath);

    // 2. Insert media_files row (plain insert, 409 treated as success)
    await _safeInsert(
      SupabaseCfg.tableMediaFiles,
      {
        "id": _uuid.v4(),
        "observation_id": observationId,
        "bucket": SupabaseCfg.publicPhotosBucket,
        "storage_path": storagePath,
        "public_url": publicUrl,
        "media_type": "thumbnail",
        "mime_type": mimeType,
        "file_size_bytes": thumbnailBytes.lengthInBytes,
        "uploaded_at": DateTime.now().toUtc().toIso8601String(),
        "is_demo": false,
      },
      cancelToken: cancelToken,
    );

    return publicUrl;
  }
}