/// Represents a GPS reading during drive awareness mode.
class DrivingPosition {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double speedMetersPerSecond;
  final double? headingDegrees;
  final DateTime timestamp;

  const DrivingPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.speedMetersPerSecond,
    this.headingDegrees,
    required this.timestamp,
  });

  /// Whether the GPS signal accuracy meets acceptable driving threshold.
  bool isAccurate({double thresholdMeters = 50.0}) => accuracyMeters <= thresholdMeters;

  /// Whether the vehicle is considered moving (speed > threshold, default 1.2 m/s ≈ 4.3 km/h).
  bool isMoving({double thresholdSpeedMps = 1.2}) => speedMetersPerSecond >= thresholdSpeedMps;

  /// Speed converted to kilometers per hour.
  double get speedKmh => speedMetersPerSecond * 3.6;

  DrivingPosition copyWith({
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    double? speedMetersPerSecond,
    double? headingDegrees,
    DateTime? timestamp,
  }) {
    return DrivingPosition(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      speedMetersPerSecond: speedMetersPerSecond ?? this.speedMetersPerSecond,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': accuracyMeters,
    'speedMetersPerSecond': speedMetersPerSecond,
    'headingDegrees': headingDegrees,
    'timestamp': timestamp.toIso8601String(),
  };

  factory DrivingPosition.fromJson(Map<String, dynamic> json) => DrivingPosition(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    accuracyMeters: (json['accuracyMeters'] as num).toDouble(),
    speedMetersPerSecond: (json['speedMetersPerSecond'] as num).toDouble(),
    headingDegrees: (json['headingDegrees'] as num?)?.toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
  );

  @override
  String toString() =>
      'DrivingPosition(lat: ${latitude.toStringAsFixed(5)}, '
      'lon: ${longitude.toStringAsFixed(5)}, '
      'heading: ${headingDegrees?.toStringAsFixed(1)}°, '
      'acc: ${accuracyMeters.toStringAsFixed(1)}m, '
      'speed: ${speedKmh.toStringAsFixed(1)}km/h)';
}
