import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/supabase_config.dart';
import '../../models/observation.dart';

/// Central service for all Supabase interactions from the mobile app.
///
/// Responsibilities:
///  1. Upload captured images to the [SupabaseCfg.imagesBucket] storage bucket.
///  2. Upload recorded live-session video clips to [SupabaseCfg.videosBucket].
///  3. Write observation + detection metadata rows directly to Supabase DB.
///  4. Manage live session lifecycle (create / append frame / finalize).
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
  /// Returns the public URL of the stored object, or null on failure.
  Future<String?> uploadObservationImage({
    required String observationId,
    required String captureId,
    required File imageFile,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final mimeType = lookupMimeType(imageFile.path) ?? 'image/jpeg';
      final ext = mimeType == 'image/png' ? 'png' : 'jpg';
      final storagePath = '$observationId/$captureId.$ext';

      await _client.storage
          .from(SupabaseCfg.imagesBucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      final url = _client.storage
          .from(SupabaseCfg.imagesBucket)
          .getPublicUrl(storagePath);

      debugPrint('[SupabaseService] Image uploaded: $url');
      await _recordMediaFile(
        observationId: observationId,
        bucket: SupabaseCfg.imagesBucket,
        storagePath: storagePath,
        publicUrl: url,
        mediaType: 'image',
        mimeType: mimeType,
        fileSizeBytes: bytes.length,
      );
      return url;
    } catch (e) {
      debugPrint('[SupabaseService] Image upload failed: $e');
      return null;
    }
  }

  /// Uploads raw JPEG bytes (live camera frame) without a local file.
  Future<String?> uploadObservationImageBytes({
    required String observationId,
    required String captureId,
    required Uint8List bytes,
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final storagePath = '$observationId/$captureId.jpg';
      await _client.storage
          .from(SupabaseCfg.imagesBucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
      final url = _client.storage
          .from(SupabaseCfg.imagesBucket)
          .getPublicUrl(storagePath);
      debugPrint('[SupabaseService] Frame image uploaded: $url');
      await _recordMediaFile(
        observationId: observationId,
        bucket: SupabaseCfg.imagesBucket,
        storagePath: storagePath,
        publicUrl: url,
        mediaType: 'image',
        mimeType: mimeType,
        fileSizeBytes: bytes.length,
      );
      return url;
    } catch (e) {
      debugPrint('[SupabaseService] Frame image upload failed: $e');
      return null;
    }
  }

  // Video upload

  /// Uploads a recorded live-session video to Supabase Storage.
  /// Returns the public URL of the stored video, or null on failure.
  Future<String?> uploadSessionVideo({
    required String sessionId,
    required File videoFile,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final bytes = await videoFile.readAsBytes();
      final mimeType = lookupMimeType(videoFile.path) ?? 'video/mp4';
      final fileName = videoFile.path.split(Platform.pathSeparator).last;
      final storagePath = '$sessionId/$fileName';

      await _client.storage
          .from(SupabaseCfg.videosBucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      final url = _client.storage
          .from(SupabaseCfg.videosBucket)
          .getPublicUrl(storagePath);

      debugPrint('[SupabaseService] Video uploaded: $url (${(bytes.length / 1e6).toStringAsFixed(1)} MB)');
      onProgress?.call(1.0);
      return url;
    } catch (e) {
      debugPrint('[SupabaseService] Video upload failed: $e');
      return null;
    }
  }

  // Observation sync

  /// Syncs a complete observation directly to Supabase DB.
  /// Also uploads the captured image to Storage if [imageFile] is provided.
  /// This method is idempotent (upsert on the observation row).
  Future<void> syncObservation(
    Observation obs, {
    File? imageFile,
    String? organizationId,
  }) async {
    final capturedAt = obs.createdAt.toUtc().toIso8601String();
    final orgId = organizationId ?? '11111111-1111-4111-8111-111111111111';

    // 1. Observation row
    await _client.from(SupabaseCfg.tableObservations).upsert({
      'id':                   obs.id,
      'capture_id':           obs.captureId,
      'parent_observation_id': null,
      'created_by':           null,
      'organization_id':      orgId,
      'device_id':            obs.deviceId,
      'source':               'camera',
      'captured_at':          capturedAt,
      'image_width':          obs.imageWidth,
      'image_height':         obs.imageHeight,
      'priority_score':       obs.priorityScore,
      'priority_label':       obs.priorityLabel,
      'model_bundle_version': obs.modelBundleVersion,
      'created_at':           capturedAt,
    });

    // 2. Location row
    await _client.from(SupabaseCfg.tableLocations).upsert({
      'observation_id':  obs.id,
      'latitude':        obs.latitude,
      'longitude':       obs.longitude,
      'accuracy_meters': obs.accuracyMeters,
      'captured_at':     capturedAt,
    });

    // 3. Agent runs + detections
    for (final result in obs.agentResults) {
      final agentRunId = _uuid.v4();
      await _client.from(SupabaseCfg.tableAgentRuns).insert({
        'id':                   agentRunId,
        'observation_id':       obs.id,
        'agent':                result.agent,
        'error':                result.error,
        'is_mock':              result.isMock,
        'latency_ms':           result.latencyMs,
        'model_bundle_version': obs.modelBundleVersion,
      });

      if (result.detections.isNotEmpty) {
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
        await _client.from(SupabaseCfg.tableDetections).insert(detections);
      }
    }

    // 4. Upload image to Storage (non-fatal if it fails)
    if (imageFile != null && await imageFile.exists()) {
      await uploadObservationImage(
        observationId: obs.id,
        captureId: obs.captureId,
        imageFile: imageFile,
      );
    }

    // 5. Sync receipt
    try {
      await _client.from(SupabaseCfg.tableSyncReceipts).insert({
        'observation_id':  obs.id,
        'idempotency_key': _uuid.v4(),
        'payload_hash':    obs.id,
      });
    } catch (_) {
      // Receipt may already exist — ignore.
    }

    debugPrint('[SupabaseService] Observation synced: ${obs.id}');
  }

  // Live session management

  /// Creates a new live session record and returns its ID.
  Future<String> createLiveSession({
    required double latitude,
    required double longitude,
    required String actor,
    String? deviceId,
  }) async {
    final sessionId = _uuid.v4();
    await _client.from(SupabaseCfg.tableLiveSessions).insert({
      'id':          sessionId,
      'started_at':  DateTime.now().toUtc().toIso8601String(),
      'actor':       actor,
      'device_id':   deviceId,
      'latitude':    latitude,
      'longitude':   longitude,
      'status':      'recording',
      'frame_count': 0,
      'anomaly_count': 0,
    });
    debugPrint('[SupabaseService] Live session created: $sessionId');
    return sessionId;
  }

  /// Updates session statistics.
  Future<void> updateLiveSession({
    required String sessionId,
    required int frameCount,
    required int anomalyCount,
    double? latitude,
    double? longitude,
  }) async {
    final updates = <String, dynamic>{
      'frame_count':  frameCount,
      'anomaly_count': anomalyCount,
      'updated_at':   DateTime.now().toUtc().toIso8601String(),
    };
    if (latitude != null)  updates['latitude']  = latitude;
    if (longitude != null) updates['longitude'] = longitude;
    await _client
        .from(SupabaseCfg.tableLiveSessions)
        .update(updates)
        .eq('id', sessionId);
  }

  /// Finalises a live session with the uploaded video URL.
  Future<void> finalizeLiveSession({
    required String sessionId,
    String? videoUrl,
    required int totalFrames,
    required int totalAnomalies,
    required Duration duration,
  }) async {
    await _client
        .from(SupabaseCfg.tableLiveSessions)
        .update({
          'ended_at':      DateTime.now().toUtc().toIso8601String(),
          'status':        'completed',
          'video_url':     videoUrl,
          'frame_count':   totalFrames,
          'anomaly_count': totalAnomalies,
          'duration_s':    duration.inSeconds,
        })
        .eq('id', sessionId);
    debugPrint('[SupabaseService] Session finalized: $sessionId (${duration.inSeconds}s, $totalAnomalies anomalies)');
  }

  // Private helpers

  Future<void> _recordMediaFile({
    required String? observationId,
    required String bucket,
    required String storagePath,
    required String publicUrl,
    required String mediaType,
    required String mimeType,
    required int fileSizeBytes,
  }) async {
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
      });
    } catch (e) {
      // Non-fatal
      debugPrint('[SupabaseService] media_files insert warning: $e');
    }
  }
}
