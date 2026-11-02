import 'dart:math' as math;

/// Core geospatial mathematical utilities for distance, bearing, and forward cone evaluation.
class GeospatialMath {
  GeospatialMath._();

  static const double earthRadiusMeters = 6371000.0;

  static double _degreesToRadians(double degrees) => degrees * (math.pi / 180.0);
  static double _radiansToDegrees(double radians) => radians * (180.0 / math.pi);

  /// Calculates the great-circle distance between two points in meters using the Haversine formula.
  static double haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final phi1 = _degreesToRadians(lat1);
    final phi2 = _degreesToRadians(lat2);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(phi1) * math.cos(phi2) * math.sin(dLon / 2) * math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Calculates the initial bearing (forward azimuth) from point 1 to point 2 in degrees [0, 360).
  static double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = _degreesToRadians(lat1);
    final phi2 = _degreesToRadians(lat2);
    final deltaLambda = _degreesToRadians(lon2 - lon1);

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);

    final theta = math.atan2(y, x);
    final bearing = (_radiansToDegrees(theta) + 360.0) % 360.0;
    return bearing;
  }

  /// Calculates the signed minimum angular difference between vehicle heading and target bearing in degrees [-180, 180].
  ///
  /// Positive values mean the target is to the vehicle's right; negative values mean to the left.
  static double angularDifference(double heading, double bearing) {
    double diff = (bearing - heading) % 360.0;
    if (diff > 180.0) {
      diff -= 360.0;
    } else if (diff < -180.0) {
      diff += 360.0;
    }
    return diff;
  }

  /// Determines if an anomaly at the given bearing falls within the vehicle's forward view cone.
  ///
  /// Default [coneHalfAngle] is 35 degrees (total cone width = 70 degrees).
  static bool isWithinForwardCone(
    double heading,
    double bearing, {
    double coneHalfAngle = 35.0,
  }) {
    final diff = angularDifference(heading, bearing).abs();
    return diff <= coneHalfAngle;
  }

  /// Determines if the target at bearing is behind the vehicle (diff > [rearCutoff] degrees).
  static bool isBehindVehicle(
    double heading,
    double bearing, {
    double rearCutoff = 90.0,
  }) {
    final diff = angularDifference(heading, bearing).abs();
    return diff > rearCutoff;
  }

  /// Smooths a heading value across the 0/360 boundary using exponential smoothing.
  ///
  /// [alpha] is the smoothing factor (0.0 to 1.0). Higher alpha responds faster to changes.
  static double smoothHeading(
    double? currentHeading,
    double newHeading, {
    double alpha = 0.25,
  }) {
    if (currentHeading == null) return (newHeading % 360.0 + 360.0) % 360.0;

    final diff = angularDifference(currentHeading, newHeading);
    double smoothed = (currentHeading + alpha * diff) % 360.0;
    if (smoothed < 0) smoothed += 360.0;
    return smoothed;
  }
}
