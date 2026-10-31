import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/model_config.dart';
import '../../core/supabase_config.dart';
import '../../inference/preprocessing.dart';
import '../../models/observation.dart';
import '../../services/image_compressor.dart';
import '../../services/observation_repository.dart';
import '../../services/thumbnail_service.dart';

class ApiClient implements ObservationSyncClient {
  ApiClient();

  final _uuid = const Uuid();

  // Canonical fallback organization IDs
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
    final organizationId = obs.organizationId ?? _organizationId(obs.actor);

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
      "device_id": null, // Do not send to public-readable tables
      "source": "camera",
      "captured_at": capturedAt,
      "image_width": imageWidth,
      "image_height": imageHeight,
      "priority_score": obs.priorityScore,
      "priority_label": obs.priorityLabel,
      "anomaly_type": _anomalyTypeFor(obs),
      "model_bundle_version": obs.modelBundleVersion.isNotEmpty
          ? obs.modelBundleVersion
          : ModelConfig.active.version,
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
    ObservationRepository? repository,
  }) async {
    final client = Supabase.instance.client;
    final capturedAt = obs.createdAt.toUtc().toIso8601String();
    final imagePath = obs.annotatedImagePath ?? obs.imagePath;
    final imageFile = File(imagePath);

    final observationPayload = await buildObservationPayload(obs);
    final locationPayload = {
      "observation_id": obs.id,
      "latitude": obs.latitude,
      "longitude": obs.longitude,
      "accuracy_meters": obs.accuracyMeters,
      "captured_at": capturedAt,
    };

    final agentRunsPayload = <Map<String, dynamic>>[];
    final detectionsPayload = <Map<String, dynamic>>[];

    for (final result in obs.agentResults) {
      final agentRunId = _uuid.v4();
      agentRunsPayload.add({
        "id": agentRunId,
        "observation_id": obs.id,
        "agent": result.agent,
        "error": result.error,
        "is_mock": result.isMock,
        "latency_ms": result.latencyMs,
        "model_bundle_version": obs.modelBundleVersion,
      });

      for (final d in result.detections) {
        detectionsPayload.add({
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
        });
      }
    }

    cancelToken?.throwIfCancelled();

    // ── 1. Atomic Relational Ingestion via RPC (with direct insert fallback) ──
    bool rpcSucceeded = false;
    try {
      final rpcRes = await client.rpc('submit_observation', params: {
        'p_observation': observationPayload,
        'p_location': locationPayload,
        'p_agent_runs': agentRunsPayload,
        'p_detections': detectionsPayload,
        'p_idempotency_key': idempotencyKey,
      });
      debugPrint('[ApiClient] Atomic submit_observation RPC succeeded: $rpcRes');
      rpcSucceeded = true;
    } on PostgrestException catch (e) {
      // If function is not found (PGRST202 or 404), fall back to direct inserts
      if (e.code == 'PGRST202' ||
          e.message.toLowerCase().contains('function') ||
          e.message.toLowerCase().contains('not found')) {
        debugPrint('[ApiClient] RPC submit_observation not found, falling back to direct table inserts: ${e.message}');
      } else if (_isConflict(e)) {
        debugPrint('[ApiClient] RPC conflict/already synced treated as success');
        rpcSucceeded = true;
      } else {
        debugPrint('[ApiClient] RPC error: ${e.code} ${e.message}');
        rethrow;
      }
    } catch (e) {
      debugPrint('[ApiClient] submit_observation RPC failed with generic error: $e');
    }

    // Direct insert fallback if RPC was unavailable
    if (!rpcSucceeded) {
      await _executeDirectInserts(
        client: client,
        obs: obs,
        observationPayload: observationPayload,
        locationPayload: locationPayload,
        agentRunsPayload: agentRunsPayload,
        detectionsPayload: detectionsPayload,
        idempotencyKey: idempotencyKey,
        cancelToken: cancelToken,
      );
    }

    cancelToken?.throwIfCancelled();

    // ── 2. Media Upload (Original Image + Public Thumbnail) ───────────────────
    if (await imageFile.exists()) {
      if (obs.mediaSyncStatus != MediaSyncStatus.uploaded) {
        await repository?.updateMediaSyncStatus(obs.id, MediaSyncStatus.uploading);
        try {
          cancelToken?.throwIfCancelled();
          final compressed = await ImageCompressor.compressToWebP(imageFile);
          cancelToken?.throwIfCancelled();

          // Stable storage path based on observation UUID to prevent random orphan files on retry
          final stableMediaUuid = _uuid.v5(Namespace.url.value, '${obs.id}:original');
          final storagePath = '${obs.id}/$stableMediaUuid.${compressed.extension}';

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
          } on StorageException catch (se) {
            if (se.statusCode == '409' ||
                se.message.toLowerCase().contains('already exists') ||
                se.message.toLowerCase().contains('duplicate')) {
              debugPrint('[ApiClient] Image already in storage (HTTP 409 treated as success): $storagePath');
            } else {
              rethrow;
            }
          }

          cancelToken?.throwIfCancelled();

          final publicUrl = client.storage
              .from(SupabaseCfg.imagesBucket)
              .getPublicUrl(storagePath);

          // Record in media_files
          await _safeInsert(
            SupabaseCfg.tableMediaFiles,
            {
              "id": stableMediaUuid,
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

          // 2b. Public Blurred Thumbnail Step (Option A: Crop-and-Blur Path)
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
              await uploadPublicThumbnail(
                observationId: obs.id,
                thumbnailBytes: thumbBytes,
                cancelToken: cancelToken,
              );
            }
          }

          await repository?.updateMediaSyncStatus(obs.id, MediaSyncStatus.uploaded);
        } catch (e) {
          debugPrint('[ApiClient] Image upload or media_files record error: $e');
          await repository?.updateMediaSyncStatus(obs.id, MediaSyncStatus.failed);
          rethrow;
        }
      }
    }

    cancelToken?.throwIfCancelled();
  }

  Future<void> _executeDirectInserts({
    required SupabaseClient client,
    required Observation obs,
    required Map<String, dynamic> observationPayload,
    required Map<String, dynamic> locationPayload,
    required List<Map<String, dynamic>> agentRunsPayload,
    required List<Map<String, dynamic>> detectionsPayload,
    required String idempotencyKey,
    SyncCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    // 1. Observations Table
    await _safeInsert(
      SupabaseCfg.tableObservations,
      observationPayload,
      cancelToken: cancelToken,
    );

    cancelToken?.throwIfCancelled();

    // 2. Locations Table
    await _safeInsert(
      SupabaseCfg.tableLocations,
      locationPayload,
      cancelToken: cancelToken,
    );

    // 3. Agent runs and detections
    for (final run in agentRunsPayload) {
      cancelToken?.throwIfCancelled();
      await _safeInsert(
        SupabaseCfg.tableAgentRuns,
        run,
        cancelToken: cancelToken,
      );
    }

    if (detectionsPayload.isNotEmpty) {
      cancelToken?.throwIfCancelled();
      await _safeInsert(
        SupabaseCfg.tableDetections,
        detectionsPayload,
        cancelToken: cancelToken,
      );
    }

    cancelToken?.throwIfCancelled();

    // 4. Sync receipts table
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
  Future<String?> uploadPublicThumbnail({
    required String observationId,
    required Uint8List thumbnailBytes,
    String mimeType = 'image/webp',
    SyncCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final client = Supabase.instance.client;
    final fileUuid = _uuid.v5(Namespace.url.value, observationId);
    final storagePath = '$observationId/$fileUuid.webp';

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

    cancelToken?.throwIfCancelled();

    final publicUrl = client.storage
        .from(SupabaseCfg.publicPhotosBucket)
        .getPublicUrl(storagePath);

    final mediaId = _uuid.v5(Namespace.url.value, '$observationId:thumbnail');
    try {
      await _safeInsert(
        SupabaseCfg.tableMediaFiles,
        {
          "id": mediaId,
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
}
