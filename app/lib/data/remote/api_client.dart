import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/observation.dart';
import '../../services/observation_repository.dart';

class ApiClient implements ObservationSyncClient {
  ApiClient({this.baseUrl = 'http://10.0.2.2:8000/v1'}) {
    // Note: 10.0.2.2 is the Android emulator alias for localhost
    if (kIsWeb || Platform.isIOS) {
      baseUrl = 'http://127.0.0.1:8000/v1';
    }
  }

  String baseUrl;

  @override
  Future<void> upload(Observation obs, {required String idempotencyKey}) async {
    final uri = Uri.parse('$baseUrl/observations');
    
    // We send a JSON payload according to backend schema ObservationUpload
    // Note: If image upload is required, we would use MultipartRequest.
    // Our fake backend accepts JSON. Wait, in backend/schemas.py, ObservationUpload expects strings and floats.
    
    final payload = {
      'id': obs.id,
      'captureId': obs.captureId,
      'imagePath': obs.imagePath,
      'createdAt': obs.createdAt.toUtc().toIso8601String(),
      'latitude': obs.latitude,
      'longitude': obs.longitude,
      'gpsAvailable': obs.gpsAvailable,
      'sourceVideoPath': obs.sourceVideoPath,
      'frameTimestampMs': obs.frameTimestampMs,
      'accuracyMeters': obs.accuracyMeters,
      'actor': obs.actor,
      'syncStatus': 'synced',
      'modelBundleVersion': obs.modelBundleVersion,
      'deviceId': obs.deviceId,
      'imageWidth': obs.imageWidth,
      'imageHeight': obs.imageHeight,
      'priorityScore': obs.priorityScore,
      'priorityLabel': obs.priorityLabel,
      'failedAgents': obs.failedAgents,
      'agentResults': obs.agentResults.map((r) => {
        'agent': r.agent,
        'detections': r.detections.map((d) => {
          'agent': d.agent,
          'detectionId': d.stableId,
          'classId': d.classId,
          'classCode': d.classCode,
          'classLabel': d.classCode, // Could map to TariqMapConstants.labelFor(d.classCode)
          'confidence': d.confidence,
          'box': {
            'x': d.box.x,
            'y': d.box.y,
            'width': d.box.width,
            'height': d.box.height,
          },
          'frameIndex': d.frameIndex,
          'modelBundleVersion': d.modelBundleVersion,
          'timestamp': d.timestamp?.toUtc().toIso8601String(),
        }).toList(),
        'error': r.error,
        'isMock': r.isMock,
        'latencyMs': r.latencyMs,
      }).toList(),
    };

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Idempotency-Key': idempotencyKey,
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server returned ${response.statusCode}: ${response.body}');
    }
  }
}
