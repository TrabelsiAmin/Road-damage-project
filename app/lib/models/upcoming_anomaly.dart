/// Represents a detected or reported road anomaly for drive awareness alerts.
class UpcomingAnomaly {
  final String observationId;
  final double latitude;
  final double longitude;
  final String anomalyType;
  final double priorityScore;
  final String priorityLabel;
  final String status;
  final double? accuracyMeters;
  final DateTime createdAt;
  final int reportCount;
  final DateTime? cachedAt;

  const UpcomingAnomaly({
    required this.observationId,
    required this.latitude,
    required this.longitude,
    required this.anomalyType,
    required this.priorityScore,
    required this.priorityLabel,
    required this.status,
    this.accuracyMeters,
    required this.createdAt,
    this.reportCount = 1,
    this.cachedAt,
  });

  /// Human readable label for the anomaly code.
  String get humanReadableType {
    switch (anomalyType.toUpperCase()) {
      case 'D00':
        return 'Longitudinal Crack';
      case 'D10':
        return 'Transverse Crack';
      case 'D20':
        return 'Alligator Crack';
      case 'D40':
        return 'Pothole';
      default:
        return 'Road Anomaly ($anomalyType)';
    }
  }

  /// Whether this is a pothole (D40) — typically highest urgency for drivers.
  bool get isPothole => anomalyType.toUpperCase() == 'D40';

  /// Whether this anomaly has a high or critical priority.
  bool get isHighRisk =>
      priorityLabel.toLowerCase() == 'high' ||
      priorityLabel.toLowerCase() == 'critical' ||
      priorityScore >= 70.0;

  Map<String, dynamic> toMap() => {
    'observation_id': observationId,
    'latitude': latitude,
    'longitude': longitude,
    'anomaly_type': anomalyType,
    'priority_score': priorityScore,
    'priority_label': priorityLabel,
    'status': status,
    'accuracy_meters': accuracyMeters,
    'created_at': createdAt.toIso8601String(),
    'report_count': reportCount,
    'cached_at': (cachedAt ?? DateTime.now()).toIso8601String(),
  };

  factory UpcomingAnomaly.fromMap(Map<String, dynamic> map) {
    return UpcomingAnomaly(
      observationId: map['observation_id']?.toString() ?? map['id']?.toString() ?? '',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      anomalyType: map['anomaly_type']?.toString().trim().isNotEmpty == true
          ? map['anomaly_type'].toString()
          : '',
      priorityScore: (map['priority_score'] as num?)?.toDouble() ?? 50.0,
      priorityLabel: map['priority_label']?.toString() ?? 'medium',
      status: map['status']?.toString() ?? 'pending',
      accuracyMeters: (map['accuracy_meters'] as num?)?.toDouble(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      reportCount: (map['report_count'] as num?)?.toInt() ?? 1,
      cachedAt: map['cached_at'] != null
          ? DateTime.tryParse(map['cached_at'].toString())
          : null,
    );
  }

  factory UpcomingAnomaly.fromJson(Map<String, dynamic> json) => UpcomingAnomaly.fromMap(json);
  Map<String, dynamic> toJson() => toMap();

  @override
  String toString() =>
      'UpcomingAnomaly($observationId, $anomalyType at $latitude, $longitude, '
      'priority: $priorityLabel ($priorityScore), reports: $reportCount)';
}

/// Evaluation result when selecting the upcoming anomaly ahead of the vehicle.
class UpcomingAnomalyResult {
  final UpcomingAnomaly? anomaly;
  final double? distanceMeters;
  final double? bearingDegrees;
  final double? angularDifferenceDegrees;
  final bool isReliable;
  final String reason;

  const UpcomingAnomalyResult({
    this.anomaly,
    this.distanceMeters,
    this.bearingDegrees,
    this.angularDifferenceDegrees,
    required this.isReliable,
    required this.reason,
  });

  bool get hasAnomaly => anomaly != null;

  static const UpcomingAnomalyResult none = UpcomingAnomalyResult(
    anomaly: null,
    distanceMeters: null,
    bearingDegrees: null,
    angularDifferenceDegrees: null,
    isReliable: true,
    reason: 'Clear road ahead',
  );
}
