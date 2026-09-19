import 'dart:convert';
import '../core/constants.dart';

// ---------------------------------------------------------------------------
// BoundingBox
// ---------------------------------------------------------------------------

class BoundingBox {
  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Top-left x coordinate, normalised [0..1].
  final double x;
  /// Top-left y coordinate, normalised [0..1].
  final double y;
  /// Width, normalised [0..1].
  final double width;
  /// Height, normalised [0..1].
  final double height;

  /// Converts normalised coordinates to pixel coordinates for a given display size.
  (double, double, double, double) toPixels(double imgW, double imgH) => (
    x * imgW,
    y * imgH,
    width  * imgW,
    height * imgH,
  );

  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'width': width, 'height': height};

  @override
  String toString() =>
      'BoundingBox(x:${x.toStringAsFixed(3)}, y:${y.toStringAsFixed(3)}, '
      'w:${width.toStringAsFixed(3)}, h:${height.toStringAsFixed(3)})';
}

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

class Detection {
  const Detection({
    required this.agent,
    required this.classCode,
    required this.confidence,
    required this.box,
    this.frameIndex,
    this.modelBundleVersion = TariqMapConstants.modelBundleVersion,
    this.timestamp,
  });

  final String       agent;
  final String       classCode;
  final double       confidence;
  final BoundingBox  box;

  /// Frame index within a video sequence (null for still images).
  final int?         frameIndex;

  /// Model bundle version that produced this detection.
  final String       modelBundleVersion;

  /// UTC wall-clock time of detection.
  final DateTime?    timestamp;

  String get classLabel => TariqMapConstants.labelFor(classCode);

  Map<String, dynamic> toJson() => {
    'agent':              agent,
    'classCode':          classCode,
    'classLabel':         classLabel,
    'confidence':         confidence,
    'box':                box.toJson(),
    'frameIndex':         frameIndex,
    'modelBundleVersion': modelBundleVersion,
    'timestamp':          timestamp?.toUtc().toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// AgentResult
// ---------------------------------------------------------------------------

class AgentResult {
  const AgentResult({
    required this.agent,
    required this.detections,
    this.error,
    this.isMock = false,
    this.latencyMs,
  });

  final String          agent;
  final List<Detection> detections;
  final String?         error;

  /// True when detections came from a mock runner (DEMO mode).
  final bool            isMock;

  /// Inference latency in milliseconds (null if not measured).
  final int?            latencyMs;

  bool get succeeded => error == null;

  Map<String, dynamic> toJson() => {
    'agent':      agent,
    'detections': detections.map((d) => d.toJson()).toList(),
    'error':      error,
    'isMock':     isMock,
    'latencyMs':  latencyMs,
  };
}

// ---------------------------------------------------------------------------
// SyncStatus
// ---------------------------------------------------------------------------

enum SyncStatus {
  pending,
  uploading,
  synced,
  failed,
  needsReview,
}

// ---------------------------------------------------------------------------
// Observation
// ---------------------------------------------------------------------------

class Observation {
  Observation({
    required this.id,
    required this.captureId,
    required this.imagePath,
    required this.createdAt,
    required this.latitude,
    required this.longitude,
    required this.agentResults,
    required this.actor,
    this.accuracyMeters,
    this.annotatedImagePath,
    this.syncStatus = SyncStatus.pending,
    this.syncError,
    this.uploadAttempts = 0,
    this.modelBundleVersion = TariqMapConstants.modelBundleVersion,
    this.deviceId,
    this.imageWidth,
    this.imageHeight,
  });

  final String   id;
  final String   captureId;
  final String   imagePath;
  final DateTime createdAt;
  final double   latitude;
  final double   longitude;
  final double?  accuracyMeters;
  final List<AgentResult> agentResults;
  final String   actor;

  /// Path to the annotated copy of the image (bounding boxes rendered).
  /// Null until annotation rendering completes.
  String?  annotatedImagePath;

  SyncStatus syncStatus;
  String?    syncError;
  int        uploadAttempts;
  final String  modelBundleVersion;
  final String? deviceId;
  final int?    imageWidth;
  final int?    imageHeight;

  // ── Derived ────────────────────────────────────────────────────────────────

  List<Detection> get detections =>
      agentResults.expand((r) => r.detections).toList();

  int get failedAgents =>
      agentResults.where((r) => !r.succeeded).length;

  bool get anyMock =>
      agentResults.any((r) => r.isMock);

  /// Transparent priority score [0..100].
  ///
  /// Formula: weighted average of (severity_weight × confidence) × 100.
  /// Weights are per TariqMapConstants.severityWeights.
  double get priorityScore {
    if (detections.isEmpty) return 0;
    const weights = TariqMapConstants.severityWeights;
    final score = detections.fold<double>(0, (sum, d) {
      final w = weights[d.classCode] ?? 0.5;
      return sum + w * d.confidence;
    });
    return (score / detections.length * 100).clamp(0, 100);
  }

  String get priorityLabel {
    final s = priorityScore;
    if (s >= 70) return 'CRITICAL';
    if (s >= 40) return 'HIGH';
    if (s >= 20) return 'MEDIUM';
    return 'LOW';
  }

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id':                 id,
    'captureId':          captureId,
    'imagePath':          imagePath,
    'annotatedImagePath': annotatedImagePath,
    'createdAt':          createdAt.toUtc().toIso8601String(),
    'latitude':           latitude,
    'longitude':          longitude,
    'accuracyMeters':     accuracyMeters,
    'actor':              actor,
    'syncStatus':         syncStatus.name,
    'syncError':          syncError,
    'uploadAttempts':     uploadAttempts,
    'modelBundleVersion': modelBundleVersion,
    'deviceId':           deviceId,
    'imageWidth':         imageWidth,
    'imageHeight':        imageHeight,
    'agentResults':       agentResults.map((r) => r.toJson()).toList(),
    'priorityScore':      priorityScore,
    'priorityLabel':      priorityLabel,
    'failedAgents':       failedAgents,
  };

  String encode() => jsonEncode(toJson());
}
