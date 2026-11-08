import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/model_config.dart';
import '../../core/supabase_config.dart';
import '../../inference/preprocessing.dart';
import '../../models/observation.dart';
import '../../services/image_compressor.dart';
import '../../services/observation_repository.dart';
import '../../services/sync_plan.dart';
import '../../services/thumbnail_service.dart';

class ApiClient implements ObservationSyncClient, StoredOriginalUrlSource {
  ApiClient();

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

  static Future<Map<String, dynamic>> buildObservationPayload(
      Observation obs) async {
    final capturedAt = obs.createdAt.toUtc().toIso8601String();
    final organizationId = obs.organizationId ?? _organizationId(obs.actor);

    var imageWidth = obs.imageWidth;
    var imageHeight = obs.imageHeight;
    final imagePath = obs.annotatedImagePath ?? obs.imagePath;
    final imageFile = File(imagePath);
    if ((imageWidth == null || imageHeight == null) &&
        await imageFile.exists()) {
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

  bool _isAuthFailure(PostgrestException e) {
    final code = e.code ?? '';
    final message = e.message.toLowerCase();
    return code == '401' ||
        code == 'PGRST301' ||
        message.contains('jwt') ||
        message.contains('not authorized') ||
        message.contains('permission denied');
  }

  bool _isAuthOrNetwork(Object error) {
    if (error is PostgrestException && _isAuthFailure(error)) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('network') ||
        text.contains('timed out') ||
        text.contains('jwt') ||
        text.contains('401');
  }

  bool _isStorageConflict(StorageException error) {
    final message = error.message.toLowerCase();
    return error.statusCode == '409' ||
        message.contains('already exists') ||
        message.contains('duplicate');
  }

  List<Map<String, Object?>> _mediaRows(Object? rows) {
    final parsed = <Map<String, Object?>>[];
    for (final row in rows as List) {
      if (row is Map) parsed.add(Map<String, Object?>.from(row));
    }
    return parsed;
  }

  OriginalMediaUrlMatch _matchOriginalMedia({
    required SupabaseClient client,
    required String observationId,
    required String mediaId,
    required Object? rows,
  }) {
    return matchOriginalMediaPublicUrl(
      observationId: observationId,
      expectedMediaId: mediaId,
      expectedBucket: SupabaseCfg.imagesBucket,
      rows: _mediaRows(rows),
      publicUrlForPath: (path) =>
          client.storage.from(SupabaseCfg.imagesBucket).getPublicUrl(path),
    );
  }

  Future<({bool confirmed, String? publicUrl})> _originalObjectConfirmed(
    SupabaseClient client, {
    required String observationId,
    required String mediaId,
  }) async {
    try {
      final rows = await client
          .from(SupabaseCfg.tableMediaFiles)
          .select('id,bucket,storage_path,public_url')
          .eq('observation_id', observationId);
      final match = _matchOriginalMedia(
        client: client,
        observationId: observationId,
        mediaId: mediaId,
        rows: rows,
      );
      if (!match.matched) return (confirmed: false, publicUrl: null);
      return (confirmed: true, publicUrl: match.publicUrl);
    } catch (e) {
      debugPrint(
          '[ApiClient] Could not confirm original object: ${redactSecrets(e.toString())}');
      return (confirmed: false, publicUrl: null);
    }
  }

  /// Looks up an original URL that is already in `media_files`.
  /// Does not upload photo bytes. Network errors propagate.
  @override
  Future<String?> readStoredOriginalUrl(String observationId) async {
    final client = Supabase.instance.client;
    final mediaId = stableOriginalMediaId(observationId);
    final rows = await client
        .from(SupabaseCfg.tableMediaFiles)
        .select('id,bucket,storage_path,public_url')
        .eq('observation_id', observationId);
    final match = _matchOriginalMedia(
      client: client,
      observationId: observationId,
      mediaId: mediaId,
      rows: rows,
    );
    final url = match.publicUrl?.trim();
    if (!match.matched || url == null || url.isEmpty) return null;
    return url;
  }

  /// Lists the expected folder. A name match is not success until [decideRemoteConflict].
  Future<ConfirmedStorageObject?> _confirmStoredObject(
    String bucket,
    String path,
  ) async {
    try {
      final slash = path.lastIndexOf('/');
      final folder = slash >= 0 ? path.substring(0, slash) : '';
      final listed = await Supabase.instance.client.storage.from(bucket).list(
            path: folder,
          );
      return confirmedObjectFromListing(
        bucket: bucket,
        path: path,
        listedNames: listed.map((item) => item.name),
      );
    } catch (e) {
      debugPrint(
          '[ApiClient] Storage confirm failed: ${redactSecrets(e.toString())}');
      return null;
    }
  }

  Future<void> _acceptStorageConflict(String bucket, String path) async {
    final confirmed = await _confirmStoredObject(bucket, path);
    final decision = decideRemoteConflict(RemoteConflictQuery.storage(
      expectedBucket: bucket,
      expectedPath: path,
      confirmedBucket: confirmed?.bucket,
      confirmedPath: confirmed?.path,
    ));
    if (decision != RemoteConflictDecision.accept) {
      throw StateError(
        'Storage conflict is not the intended object at $bucket/$path',
      );
    }
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
      final rows = await Supabase.instance.client
          .from(table)
          .select(identityColumnsForTable(table).join(','))
          .eq(id != null ? 'id' : 'observation_id', filterValue)
          .limit(1);
      if (rows.isEmpty) return null;
      return Map<String, Object?>.from(rows.first);
    } catch (e) {
      debugPrint(
          '[ApiClient] Could not read stored $table row: ${redactSecrets(e.toString())}');
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
        final rows = data is List ? data : [data];
        for (final row in rows) {
          if (row is! Map) {
            throw StateError(
              'Unique conflict does not match the stored $table row',
            );
          }
          await _acceptMatchingRow(table, Map<String, dynamic>.from(row));
        }
        return;
      }
      debugPrint(
          '[$table] Insert error: ${e.code} ${redactSecrets(e.message)}');
      rethrow;
    } catch (e) {
      debugPrint('[$table] Insert failed: ${redactSecrets(e.toString())}');
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

    for (var i = 0; i < obs.agentResults.length; i++) {
      final result = obs.agentResults[i];
      // Stable ids so a retry of the same local observation conflicts
      // instead of inserting a second agent run and a second set of boxes.
      final agentRunId = stableAgentRunId(obs.id, i, result.agent);
      agentRunsPayload.add({
        "id": agentRunId,
        "observation_id": obs.id,
        "agent": result.agent,
        "error": result.error,
        "is_mock": result.isMock,
        "latency_ms": result.latencyMs,
        "model_bundle_version": obs.modelBundleVersion,
      });

      for (var j = 0; j < result.detections.length; j++) {
        final d = result.detections[j];
        detectionsPayload.add({
          "id": stableDetectionId(obs.id, i, j),
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
          "detected_at":
              (d.timestamp ?? obs.createdAt).toUtc().toIso8601String(),
        });
      }
    }

    cancelToken?.throwIfCancelled();

    // ── 1. Atomic Relational Ingestion via RPC (with direct insert fallback) ──
    // A successful RPC already wrote the metadata receipt. Status synced or
    // already_synced is not proof that the photo exists. The client does not
    // SELECT sync_receipts or agent_runs after that call: anon is not granted
    // those reads, and the RPC body does not list child ids.
    var ack = const SubmitObservationAck(callSucceeded: false);
    try {
      final rpcRes = await client.rpc('submit_observation', params: {
        'p_observation': observationPayload,
        'p_location': locationPayload,
        'p_agent_runs': agentRunsPayload,
        'p_detections': detectionsPayload,
        'p_idempotency_key': idempotencyKey,
      });
      ack = parseSubmitObservationAck(rpcRes);
      if (!ack.callSucceeded) {
        throw StateError('submit_observation rejected the metadata');
      }
      debugPrint(
          '[ApiClient] Atomic submit_observation RPC succeeded: status=${ack.status} media=${ack.provesMedia}');
    } on PostgrestException catch (e) {
      // If function is not found (PGRST202 or 404), fall back to direct inserts
      if (e.code == 'PGRST202' ||
          e.message.toLowerCase().contains('function') ||
          e.message.toLowerCase().contains('not found')) {
        debugPrint(
            '[ApiClient] RPC submit_observation not found, falling back to direct table inserts: ${e.message}');
        ack = const SubmitObservationAck(callSucceeded: false);
      } else if (_isConflict(e)) {
        // The observation row may exist while agent runs or detections do not.
        debugPrint(
            '[ApiClient] RPC conflict; missing children will be inserted');
        ack = const SubmitObservationAck(callSucceeded: false);
      } else if (_isAuthFailure(e)) {
        debugPrint('[ApiClient] RPC auth failed');
        rethrow;
      } else {
        debugPrint(
            '[ApiClient] RPC error: ${e.code} ${redactSecrets(e.message)}');
        rethrow;
      }
    } on StateError {
      rethrow;
    } catch (e) {
      debugPrint(
          '[ApiClient] submit_observation RPC failed: ${redactSecrets(e.toString())}');
      if (_isAuthOrNetwork(e)) rethrow;
      ack = const SubmitObservationAck(callSucceeded: false);
    }

    // `synced` stored this payload's children in that transaction. Any other
    // successful status, including `already_synced`, does not. The client
    // does not SELECT agent_runs. It reads detections, which anon may select,
    // and inserts only rows that are still missing.
    if (!ack.callSucceeded) {
      await _executeDirectInserts(
        client: client,
        obs: obs,
        observationPayload: observationPayload,
        locationPayload: locationPayload,
        agentRunsPayload: const [],
        detectionsPayload: const [],
        idempotencyKey: idempotencyKey,
        cancelToken: cancelToken,
      );
    } else if (!rpcTransactionStoredChildren(ack)) {
      await _ensureLocation(client, locationPayload, cancelToken);
    }
    if (!rpcTransactionStoredChildren(ack)) {
      await _repairMissingChildren(
        client: client,
        observationId: obs.id,
        agentRunsPayload: agentRunsPayload,
        detectionsPayload: detectionsPayload,
        insertZeroDetectionRuns: !ack.callSucceeded,
        cancelToken: cancelToken,
      );
    }
    final stored = await repository?.findById(obs.id);
    final mediaStatus = stored?.mediaSyncStatus ?? obs.mediaSyncStatus;
    // An existing observation row does not skip the photo. A confirmed
    // original object at its stable path does.
    final originalMediaId = stableOriginalMediaId(obs.id);
    final original = await _originalObjectConfirmed(
      client,
      observationId: obs.id,
      mediaId: originalMediaId,
    );
    final remoteOriginalPresent = original.confirmed;
    final rememberedUrl = original.publicUrl;
    if (rememberedUrl != null && rememberedUrl.isNotEmpty) {
      await repository?.updateRemoteImageUrl(obs.id, rememberedUrl);
    }
    final plan = planRemoteSync(
      observationId: obs.id,
      agents: [
        for (var i = 0; i < obs.agentResults.length; i++)
          (
            index: i,
            agent: obs.agentResults[i].agent,
            detectionCount: obs.agentResults[i].detections.length,
          ),
      ],
      mediaSyncStatus: mediaStatus,
      remoteOriginalPresent: remoteOriginalPresent,
      existingAgentRunIds: {
        for (final run in agentRunsPayload) run['id'].toString(),
      },
      existingDetectionIds: {
        for (final detection in detectionsPayload) detection['id'].toString(),
      },
    );

    // Photo confirmation below uses media_files, not the RPC status.
    // A successful RPC already holds the metadata receipt. This client does
    // not read or insert sync_receipts on that path. The direct-insert path
    // inserts one receipt only after the original and thumbnail steps, with
    // no prior read.
    var originalConfirmed = remoteOriginalPresent;
    var thumbnailFinished = !plan.uploadPhoto && !plan.retryThumbnailOnly;

    // ── 2. Original image. Skipped when that exact object is already confirmed. ─
    Uint8List? preparedOriginal;
    if (plan.uploadPhoto) {
      if (!await imageFile.exists()) {
        await repository?.updateMediaSyncStatus(obs.id, MediaSyncStatus.failed);
        throw StateError('Local image is missing; media was not uploaded');
      }
      await repository?.updateMediaSyncStatus(
          obs.id, MediaSyncStatus.uploading);
      try {
        cancelToken?.throwIfCancelled();
        final originalBytes = await imageFile.readAsBytes();
        preparedOriginal = bytesForUpload(originalBytes);
        final compressed = await ImageCompressor.compressBytes(preparedOriginal);
        cancelToken?.throwIfCancelled();

        final stableMediaUuid = plan.originalMediaId;
        final storagePath =
            originalObjectPath(obs.id, compressed.extension);

        try {
          await client.storage.from(SupabaseCfg.imagesBucket).uploadBinary(
                storagePath,
                compressed.bytes,
                fileOptions: FileOptions(
                  contentType: compressed.mimeType,
                  upsert: false,
                ),
              );
        } on StorageException catch (se) {
          if (_isStorageConflict(se)) {
            await _acceptStorageConflict(
              SupabaseCfg.imagesBucket,
              storagePath,
            );
          } else {
            rethrow;
          }
        }

        cancelToken?.throwIfCancelled();

        final publicUrl = client.storage
            .from(SupabaseCfg.imagesBucket)
            .getPublicUrl(storagePath);
        await repository?.updateRemoteImageUrl(obs.id, publicUrl);

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
        await repository?.updateMediaSyncStatus(
            obs.id, MediaSyncStatus.originalUploaded);
        originalConfirmed = true;
      } on SyncCancelledException {
        rethrow;
      } catch (e) {
        debugPrint(
            '[ApiClient] Image upload or media_files record error: ${redactSecrets(e.toString())}');
        final current = await repository?.findById(obs.id);
        if (current?.mediaSyncStatus != MediaSyncStatus.originalUploaded) {
          await repository?.updateMediaSyncStatus(
              obs.id, MediaSyncStatus.failed);
        }
        rethrow;
      }
    }

    // ── 3. Thumbnail. Reuses the stored original; does not upload it again. ─
    if (plan.uploadPhoto || plan.retryThumbnailOnly) {
      if (plan.retryThumbnailOnly) {
        final current = await repository?.findById(obs.id);
        if (current != null &&
            current.mediaSyncStatus != MediaSyncStatus.uploaded &&
            current.mediaSyncStatus != MediaSyncStatus.originalUploaded) {
          await repository?.updateMediaSyncStatus(
              obs.id, MediaSyncStatus.originalUploaded);
        }
      }
      if (!await imageFile.exists()) {
        throw StateError(
            'Local image is missing; the later thumbnail step was not completed');
      }
      try {
        cancelToken?.throwIfCancelled();
        preparedOriginal ??= bytesForUpload(await imageFile.readAsBytes());
        final shouldUpload = await ThumbnailService.shouldUploadPublicThumbnail(
          detections: obs.detections,
        );
        if (shouldUpload) {
          final thumbBytes = await ThumbnailService.createDetectionCropThumbnail(
            originalBytes: preparedOriginal,
            detections: obs.detections,
          );
          if (thumbBytes == null ||
              thumbBytes.lengthInBytes > ThumbnailService.maxFileSizeBytes) {
            throw StateError(
                'Public thumbnail could not be completed safely');
          }
          await uploadPublicThumbnail(
            observationId: obs.id,
            thumbnailBytes: thumbBytes,
            cancelToken: cancelToken,
          );
        }
        await repository?.updateMediaSyncStatus(
            obs.id, MediaSyncStatus.uploaded);
        thumbnailFinished = true;
      } on SyncCancelledException {
        rethrow;
      } catch (e) {
        debugPrint(
            '[ApiClient] Thumbnail step failed: ${redactSecrets(e.toString())}');
        final current = await repository?.findById(obs.id);
        if (current?.mediaSyncStatus != MediaSyncStatus.originalUploaded &&
            current?.mediaSyncStatus != MediaSyncStatus.uploaded) {
          await repository?.updateMediaSyncStatus(
              obs.id, MediaSyncStatus.originalUploaded);
        }
        rethrow;
      }
    }

    if (clientReceiptInsertWithoutRead(
      rpcCallSucceeded: ack.callSucceeded,
      observationStored: true,
      originalConfirmed: originalConfirmed,
      thumbnailStepFinished: thumbnailFinished,
    )) {
      cancelToken?.throwIfCancelled();
      await _insertClientReceipt(
        observationId: obs.id,
        idempotencyKey: idempotencyKey,
        cancelToken: cancelToken,
      );
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
  }

  Future<void> _ensureLocation(
    SupabaseClient client,
    Map<String, dynamic> locationPayload,
    SyncCancelToken? cancelToken,
  ) async {
    cancelToken?.throwIfCancelled();
    final observationId = locationPayload['observation_id']?.toString();
    if (observationId == null || observationId.isEmpty) return;
    final rows = await client
        .from(SupabaseCfg.tableLocations)
        .select('observation_id,latitude,longitude')
        .eq('observation_id', observationId);
    for (final row in rows as List) {
      if (row is! Map) continue;
      if (storedLocationMatches(
        stored: Map<String, Object?>.from(row),
        submitted: locationPayload,
      )) {
        return;
      }
    }
    await _insertIdentifiedRow(
      SupabaseCfg.tableLocations,
      locationPayload,
      {
        'observation_id': locationPayload['observation_id'],
        'latitude': locationPayload['latitude'],
        'longitude': locationPayload['longitude'],
      },
      cancelToken: cancelToken,
    );
  }

  Future<void> _repairMissingChildren({
    required SupabaseClient client,
    required String observationId,
    required List<Map<String, dynamic>> agentRunsPayload,
    required List<Map<String, dynamic>> detectionsPayload,
    required bool insertZeroDetectionRuns,
    SyncCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final rows = await client
        .from(SupabaseCfg.tableDetections)
        .select('id,observation_id,class_code,agent_run_id')
        .eq('observation_id', observationId);
    final stored = <Map<String, Object?>>[
      for (final row in rows as List)
        if (row is Map) Map<String, Object?>.from(row),
    ];
    final repair = planChildRepair(
      trustTransaction: false,
      insertZeroDetectionRuns: insertZeroDetectionRuns,
      agentRuns: agentRunsPayload,
      detections: detectionsPayload,
      matchedDetectionIds: matchedDetectionIds(
        storedRows: stored,
        submitted: detectionsPayload,
      ),
    );
    for (final run in repair.agentRunsToInsert) {
      cancelToken?.throwIfCancelled();
      await _insertIdentifiedRow(
        SupabaseCfg.tableAgentRuns,
        Map<String, dynamic>.from(run),
        {
          'id': run['id'],
          'observation_id': run['observation_id'],
          'agent': run['agent'],
        },
        cancelToken: cancelToken,
      );
    }
    for (final detection in repair.detectionsToInsert) {
      cancelToken?.throwIfCancelled();
      await _insertIdentifiedRow(
        SupabaseCfg.tableDetections,
        Map<String, dynamic>.from(detection),
        {
          'id': detection['id'],
          'observation_id': detection['observation_id'],
          'class_code': detection['class_code'],
          'agent_run_id': detection['agent_run_id'],
        },
        cancelToken: cancelToken,
      );
    }
  }

  /// Inserts one direct-path receipt. Does not SELECT `sync_receipts`.
  ///
  /// A duplicate-key error is success only when it names this observation id
  /// and this idempotency key. Any other database error is still a failure.
  Future<void> _insertClientReceipt({
    required String observationId,
    required String idempotencyKey,
    SyncCancelToken? cancelToken,
  }) async {
    await _insertIdentifiedRow(
      SupabaseCfg.tableSyncReceipts,
      {
        "observation_id": observationId,
        "idempotency_key": idempotencyKey,
        "payload_hash": "flutter-direct-sync",
      },
      {
        'observation_id': observationId,
        'idempotency_key': idempotencyKey,
      },
      cancelToken: cancelToken,
    );
  }

  Future<void> _insertIdentifiedRow(
    String table,
    Map<String, dynamic> row,
    Map<String, Object?> identity, {
    SyncCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    try {
      await Supabase.instance.client.from(table).insert(row);
    } on PostgrestException catch (e) {
      if (duplicateKeyMatchesIdentity(
        identity: identity,
        code: e.code,
        message: e.message,
        details: e.details,
      )) {
        return;
      }
      debugPrint(
          '[$table] Insert error: ${e.code} ${redactSecrets(e.message)}');
      rethrow;
    } catch (e) {
      debugPrint('[$table] Insert failed: ${redactSecrets(e.toString())}');
      rethrow;
    }
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
    final storagePath = publicThumbnailObjectPath(observationId);

    try {
      await client.storage.from(SupabaseCfg.publicPhotosBucket).uploadBinary(
            storagePath,
            thumbnailBytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );
      debugPrint(
          '[ThumbnailUpload] Storage upload succeeded: HTTP 200/201 path=$storagePath');
    } on StorageException catch (e) {
      if (_isStorageConflict(e)) {
        await _acceptStorageConflict(
          SupabaseCfg.publicPhotosBucket,
          storagePath,
        );
      } else {
        debugPrint(
            '[ThumbnailUpload] Storage upload failed: HTTP ${e.statusCode} ${e.message} path=$storagePath');
        rethrow;
      }
    } catch (e) {
      debugPrint(
          '[ThumbnailUpload] Storage upload failed: $e path=$storagePath');
      rethrow;
    }

    cancelToken?.throwIfCancelled();

    final publicUrl = client.storage
        .from(SupabaseCfg.publicPhotosBucket)
        .getPublicUrl(storagePath);

    final mediaId = stableThumbnailMediaId(observationId);
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
      debugPrint(
          '[ThumbnailUpload] media_files insert succeeded: HTTP 201 row=$mediaId');
    } on PostgrestException catch (e) {
      debugPrint(
          '[ThumbnailUpload] media_files insert failed: HTTP ${e.code ?? "error"} ${e.message} row=$mediaId');
      rethrow;
    } catch (e) {
      debugPrint(
          '[ThumbnailUpload] media_files insert failed: $e row=$mediaId');
      rethrow;
    }

    return publicUrl;
  }
}
