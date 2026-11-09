import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../models/observation.dart';
import '../../models/upcoming_anomaly.dart';
import '../../services/image_compressor.dart';
import '../../services/sync_cancel_token.dart';
import '../../services/sync_plan.dart';

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

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  SupabaseClient get _client => Supabase.instance.client;

  // Initialisation

  /// Call once at app startup before runApp.
  static Future<void> initialize() async {
    try {
      SupabaseCfg.assertPublicConfig();
      await Supabase.initialize(
        url:            SupabaseCfg.url,
        publishableKey: SupabaseCfg.anonKey,
        // Do not log HTTP traffic: it can include the anon key.
        debug: false,
      );
      _initialized = true;
      debugPrint('[SupabaseService] Initialized');
    } catch (e, st) {
      _initialized = false;
      debugPrint('[SupabaseService] Initialization failed: $e\n$st');
    }
  }

  // Image upload

  /// Uploads bytes only when storage has not already stored this exact object.
  /// A 409 is success only when [decideRemoteConflict] accepts the lookup.
  Future<void> _uploadBinaryOrSameObject({
    required String bucket,
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      await _client.storage.from(bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      if (!_isStorageConflict(e)) rethrow;
      final confirmed = await _confirmStoredObject(bucket, storagePath);
      final decision = decideRemoteConflict(RemoteConflictQuery.storage(
        expectedBucket: bucket,
        expectedPath: storagePath,
        confirmedBucket: confirmed?.bucket,
        confirmedPath: confirmed?.path,
      ));
      if (decision != RemoteConflictDecision.accept) {
        throw StateError(
          'Storage conflict is not the intended object at $bucket/$storagePath',
        );
      }
    }
  }

  Future<ConfirmedStorageObject?> _confirmStoredObject(
    String bucket,
    String path,
  ) async {
    try {
      final slash = path.lastIndexOf('/');
      final folder = slash >= 0 ? path.substring(0, slash) : '';
      final listed = await _client.storage.from(bucket).list(path: folder);
      return confirmedObjectFromListing(
        bucket: bucket,
        path: path,
        listedNames: listed.map((item) => item.name),
      );
    } catch (e) {
      debugPrint('[SupabaseService] Storage confirm failed: $e');
      return null;
    }
  }

  bool _isStorageConflict(StorageException error) {
    final message = error.message.toLowerCase();
    return error.statusCode == '409' ||
        message.contains('already exists') ||
        message.contains('duplicate');
  }

  /// Uploads a still-image capture to Supabase Storage.
  /// The image is compressed to WebP before upload to reduce storage usage.
  /// Uses this observation's stable media UUID path and plain insert (upsert: false).
  /// Returns the public URL of the stored object, or null on failure.
  Future<String?> uploadObservationImage({
    required String observationId,
    required String captureId,
    required File imageFile,
    SyncCancelToken? cancelToken,
  }) async {
    if (!_initialized) return null;
    try {
      cancelToken?.throwIfCancelled();
      // Compress to WebP — saves 40-60% storage vs original JPEG/PNG
      final compressed = await ImageCompressor.compressToWebP(imageFile);
      cancelToken?.throwIfCancelled();

      final storagePath = originalObjectPath(observationId, compressed.extension);
      await _uploadBinaryOrSameObject(
        bucket: SupabaseCfg.imagesBucket,
        storagePath: storagePath,
        bytes: compressed.bytes,
        contentType: compressed.mimeType,
      );

      cancelToken?.throwIfCancelled();

      final url = _client.storage
          .from(SupabaseCfg.imagesBucket)
          .getPublicUrl(storagePath);

      debugPrint('[SupabaseService] Image uploaded (WebP): $url '
          '(saved ${compressed.savedBytes ~/ 1024} KB)');

      await _recordMediaFile(
        mediaId: stableOriginalMediaId(observationId),
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
    if (!_initialized) return null;
    try {
      cancelToken?.throwIfCancelled();
      final compressed = await ImageCompressor.compressBytes(bytes);
      cancelToken?.throwIfCancelled();

      final storagePath = originalObjectPath(observationId, compressed.extension);
      await _uploadBinaryOrSameObject(
        bucket: SupabaseCfg.imagesBucket,
        storagePath: storagePath,
        bytes: compressed.bytes,
        contentType: compressed.mimeType,
      );

      cancelToken?.throwIfCancelled();

      final url = _client.storage
          .from(SupabaseCfg.imagesBucket)
          .getPublicUrl(storagePath);

      debugPrint('[SupabaseService] Frame image uploaded (WebP): $url');
      await _recordMediaFile(
        mediaId: stableOriginalMediaId(observationId),
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
  ///      A 409 is success only when the lookup is this bucket and this exact path.
  ///   2. Check cancellation (on cancel, just stop; orphan file with no media_files row is harmless).
  ///   3. Plain insert into `media_files` with `bucket='public-photos', media_type='thumbnail', is_demo=false`.
  ///      A unique conflict is the same row only when the stored identity matches.
  Future<String?> uploadPublicThumbnail({
    required String observationId,
    required Uint8List thumbnailBytes,
    String mimeType = 'image/webp',
    SyncCancelToken? cancelToken,
  }) async {
    if (!_initialized) {
      throw StateError('Supabase is not initialized');
    }
    cancelToken?.throwIfCancelled();
    final storagePath = publicThumbnailObjectPath(observationId);

    try {
      await _uploadBinaryOrSameObject(
        bucket: SupabaseCfg.publicPhotosBucket,
        storagePath: storagePath,
        bytes: thumbnailBytes,
        contentType: mimeType,
      );
      debugPrint('[ThumbnailUpload] Storage upload succeeded: HTTP 200/201 path=$storagePath');
    } on StorageException catch (e) {
      debugPrint('[ThumbnailUpload] Storage upload failed: HTTP ${e.statusCode} ${e.message} path=$storagePath');
      rethrow;
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

    final mediaId = stableThumbnailMediaId(observationId);
    try {
      await _insertOrMatch(SupabaseCfg.tableMediaFiles, {
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
      debugPrint('[ThumbnailUpload] media_files insert failed: HTTP ${e.code ?? "error"} ${e.message} row=$mediaId');
      rethrow;
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
    if (!_initialized) return null;
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
    if (!_initialized) {
      throw StateError('Supabase is not initialized');
    }
    final capturedAt = obs.createdAt.toUtc().toIso8601String();
    final orgId = organizationId ?? '11111111-1111-4111-8111-111111111111';

    cancelToken?.throwIfCancelled();

    // 1. Observation row. A unique conflict continues only when the stored identity matches.
    await _insertOrMatch(SupabaseCfg.tableObservations, {
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

    cancelToken?.throwIfCancelled();

    // 2. Location row. A different stored place fails this step.
    await _insertOrMatch(SupabaseCfg.tableLocations, {
      'observation_id':  obs.id,
      'latitude':        obs.latitude,
      'longitude':       obs.longitude,
      'accuracy_meters': obs.accuracyMeters,
      'captured_at':     capturedAt,
    });

    cancelToken?.throwIfCancelled();

    // 3. Agent runs + detections reuse UUID v5 ids. Existing rows are not deleted.
    for (var agentIndex = 0; agentIndex < obs.agentResults.length; agentIndex++) {
      final result = obs.agentResults[agentIndex];
      cancelToken?.throwIfCancelled();
      final agentRunId = stableAgentRunId(obs.id, agentIndex, result.agent);
      await _insertOrMatch(SupabaseCfg.tableAgentRuns, {
        'id':                   agentRunId,
        'observation_id':       obs.id,
        'agent':                result.agent,
        'error':                result.error,
        'is_mock':              result.isMock,
        'latency_ms':           result.latencyMs,
        'model_bundle_version': obs.modelBundleVersion,
      });

      if (result.detections.isNotEmpty) {
        cancelToken?.throwIfCancelled();
        final detections = [
          for (var detectionIndex = 0;
              detectionIndex < result.detections.length;
              detectionIndex++)
            {
              'id': stableDetectionId(obs.id, agentIndex, detectionIndex),
              'observation_id': obs.id,
              'agent_run_id': agentRunId,
              'media_id': null,
              'class_code': result.detections[detectionIndex].classCode,
              'confidence': result.detections[detectionIndex].confidence,
              'box_x': result.detections[detectionIndex].box.x,
              'box_y': result.detections[detectionIndex].box.y,
              'box_w': result.detections[detectionIndex].box.width,
              'box_h': result.detections[detectionIndex].box.height,
              'frame_index': result.detections[detectionIndex].frameIndex,
              'is_mock': result.isMock,
              'model_bundle_version':
                  result.detections[detectionIndex].modelBundleVersion,
              'detected_at': result.detections[detectionIndex].timestamp
                      ?.toUtc()
                      .toIso8601String() ??
                  capturedAt,
            },
        ];
        await _insertOrMatch(SupabaseCfg.tableDetections, detections);
      }
    }

    cancelToken?.throwIfCancelled();

    // 4. Upload image. A failed or unconfirmed upload does not continue.
    if (imageFile != null && await imageFile.exists()) {
      final imageUrl = await uploadObservationImage(
        observationId: obs.id,
        captureId: obs.captureId,
        imageFile: imageFile,
        cancelToken: cancelToken,
      );
      if (imageUrl == null) {
        throw StateError(
          'Image upload was not confirmed for ${obs.id}',
        );
      }
    }

    cancelToken?.throwIfCancelled();

    // 5. Sync receipt. The key is stable so a retry is the same receipt.
    await _insertOrMatch(SupabaseCfg.tableSyncReceipts, {
      'observation_id':  obs.id,
      'idempotency_key': stableSyncReceiptKey(obs.id),
      'payload_hash':    obs.id,
    });

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

  Future<Map<String, Object?>?> _readStoredIdentity(
    String table,
    Map<String, dynamic> payload,
  ) async {
    try {
      final id = payload['id']?.toString();
      final observationId = payload['observation_id']?.toString();
      final filterValue = id ?? observationId;
      if (filterValue == null) return null;
      final rows = await _client
          .from(table)
          .select(identityColumnsForTable(table).join(','))
          .eq(id != null ? 'id' : 'observation_id', filterValue)
          .limit(1);
      if (rows.isEmpty) return null;
      return Map<String, Object?>.from(rows.first);
    } catch (e) {
      debugPrint('[SupabaseService] Could not read stored $table row: $e');
      return null;
    }
  }

  Future<void> _acceptMatchingRow(
    String table,
    Map<String, dynamic> payload,
  ) async {
    final stored = await _readStoredIdentity(table, payload);
    final decision = decideRemoteConflict(RemoteConflictQuery.row(
      childId: payload['id']?.toString(),
      observationId: payload['observation_id']?.toString() ??
          (table == SupabaseCfg.tableObservations
              ? payload['id']?.toString()
              : null),
      expectedIdentity: identityFieldsForTable(table, payload),
      storedRow: stored,
    ));
    if (decision != RemoteConflictDecision.accept) {
      throw StateError(
        'Unique conflict does not match the stored $table row',
      );
    }
  }

  /// Inserts [data]. A unique conflict continues only when the stored identity matches.
  /// The remote row is not deleted.
  Future<void> _insertOrMatch(String table, dynamic data) async {
    try {
      await _client.from(table).insert(data);
    } on PostgrestException catch (e) {
      if (!_isConflict(e)) {
        debugPrint('[SupabaseService] $table insert error: ${e.code} ${e.message}');
        rethrow;
      }
      final rows = data is List ? data : [data];
      for (final row in rows) {
        if (row is! Map) {
          throw StateError(
            'Unique conflict does not match the stored $table row',
          );
        }
        await _acceptMatchingRow(table, Map<String, dynamic>.from(row));
      }
    }
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
    String? mediaId,
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
      await _insertOrMatch(SupabaseCfg.tableMediaFiles, {
        'id':              mediaId ?? _uuid.v4(),
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
      debugPrint('[SupabaseService] media_files insert warning: ${e.code} ${e.message}');
    } catch (e) {
      if (e is StateError) rethrow;
      debugPrint('[SupabaseService] media_files insert warning: $e');
    }
  }

  /// Calls PostGIS RPC get_nearby_anomalies to fetch road anomalies around the vehicle.
  Future<List<UpcomingAnomaly>> fetchNearbyAnomalies({
    required double latitude,
    required double longitude,
    double radiusMeters = 1000.0,
    int maxResults = 50,
  }) async {
    if (!_initialized) return [];
    try {
      final response = await _client.rpc(
        'get_nearby_anomalies',
        params: {
          'user_lat': latitude,
          'user_lon': longitude,
          'radius_meters': radiusMeters,
          'max_results': maxResults,
        },
      );

      if (response == null) return [];
      final List<dynamic> data = response is List ? response : [];
      return data.map((item) {
        final map = item as Map<String, dynamic>;
        return UpcomingAnomaly.fromMap(map);
      }).toList();
    } catch (e) {
      debugPrint('[SupabaseService] fetchNearbyAnomalies RPC error: $e');
      return [];
    }
  }
}
