import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../models/observation.dart';
import '../../services/observation_repository.dart';
import '../../core/supabase_config.dart';

class ApiClient implements ObservationSyncClient {
  ApiClient();

  final _uuid = const Uuid();

  // Hardcode organizations similar to python backend for demo purposes
  final _organizationIds = const {
    "Municipality": "11111111-1111-4111-8111-111111111111",
    "Ministry of Equipment": "22222222-2222-4222-8222-222222222222",
    "Tunisia Autoroutes": "33333333-3333-4333-8333-333333333333",
  };

  String _organizationId(String actor) {
    return _organizationIds[actor] ?? _organizationIds["Municipality"]!;
  }

  @override
  Future<void> upload(Observation obs, {required String idempotencyKey}) async {
    final client = Supabase.instance.client;
    final capturedAt = obs.createdAt.toUtc().toIso8601String();
    final organizationId = _organizationId(obs.actor);

    // 1. Observations Table
    await client.from(SupabaseCfg.tableObservations).upsert({
      "id": obs.id,
      "capture_id": obs.captureId,
      "parent_observation_id": null,
      "created_by": null,
      "organization_id": organizationId,
      "device_id": obs.deviceId,
      "source": "camera",
      "captured_at": capturedAt,
      "image_width": obs.imageWidth,
      "image_height": obs.imageHeight,
      "priority_score": obs.priorityScore,
      "priority_label": obs.priorityLabel,
      "model_bundle_version": obs.modelBundleVersion,
      "created_at": capturedAt,
    });

    // 2. Locations Table
    await client.from(SupabaseCfg.tableLocations).upsert({
      "observation_id": obs.id,
      "latitude": obs.latitude,
      "longitude": obs.longitude,
      "accuracy_meters": obs.accuracyMeters,
      "captured_at": capturedAt,
    });

    // 3. Agent Runs & Detections
    for (final result in obs.agentResults) {
      final agentRunId = _uuid.v4();
      
      await client.from(SupabaseCfg.tableAgentRuns).upsert({
        "id": agentRunId,
        "observation_id": obs.id,
        "agent": result.agent,
        "error": result.error,
        "is_mock": result.isMock,
        "latency_ms": result.latencyMs,
        "model_bundle_version": obs.modelBundleVersion,
      });

      if (result.detections.isNotEmpty) {
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
          "model_bundle_version": d.modelBundleVersion ?? obs.modelBundleVersion,
          "detected_at": (d.timestamp ?? obs.createdAt).toUtc().toIso8601String(),
        }).toList();

        await client.from(SupabaseCfg.tableDetections).upsert(detectionsData);
      }
    }

    // 4. Sync Receipts for idempotency tracking
    await client.from(SupabaseCfg.tableSyncReceipts).upsert({
      "observation_id": obs.id,
      "idempotency_key": idempotencyKey,
      "payload_hash": "flutter-direct-sync",
    });
  }
}
