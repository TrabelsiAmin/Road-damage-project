import 'dart:math' as math;
import '../models/driving_position.dart';
import '../models/upcoming_anomaly.dart';
import '../utils/geospatial_math.dart';

/// Abstraction for matching anomalies to the vehicle's driving path.
///
/// Designed to support forward-cone heuristics as the default MVP, while allowing
/// map-matching (e.g. OSRM, Valhalla, or OSM road graph) implementations to be plugged in.
abstract class RouteMatchingService {
  /// Evaluates whether the given anomaly lies on or ahead along the vehicle's path.
  bool isAnomalyOnRoute({
    required DrivingPosition position,
    required UpcomingAnomaly anomaly,
  });

  /// Computes a composite relevance score for ranking multiple candidate anomalies.
  /// Higher values indicate greater urgency and alignment with the driver's path.
  double calculateRelevanceScore({
    required DrivingPosition position,
    required UpcomingAnomaly anomaly,
  });
}

/// MVP forward-cone route matcher based on heading and angular field of view.
class ForwardConeRouteMatcher implements RouteMatchingService {
  const ForwardConeRouteMatcher({
    this.coneHalfAngleDegrees = 35.0,
    this.maxLookaheadMeters = 400.0,
    this.minLookaheadMeters = 10.0,
    this.stationaryProximityMeters = 50.0,
  });

  final double coneHalfAngleDegrees;
  final double maxLookaheadMeters;
  final double minLookaheadMeters;
  final double stationaryProximityMeters;

  @override
  bool isAnomalyOnRoute({
    required DrivingPosition position,
    required UpcomingAnomaly anomaly,
  }) {
    final distance = GeospatialMath.haversineDistanceMeters(
      position.latitude,
      position.longitude,
      anomaly.latitude,
      anomaly.longitude,
    );

    // If beyond max lookahead, ignore
    if (distance > maxLookaheadMeters) return false;

    // If vehicle has no heading (e.g. stationary startup), match by immediate proximity
    if (position.headingDegrees == null) {
      return distance <= stationaryProximityMeters;
    }

    final bearing = GeospatialMath.calculateBearing(
      position.latitude,
      position.longitude,
      anomaly.latitude,
      anomaly.longitude,
    );

    // Check if behind vehicle
    if (GeospatialMath.isBehindVehicle(position.headingDegrees!, bearing)) {
      return false;
    }

    // Check forward cone
    return GeospatialMath.isWithinForwardCone(
      position.headingDegrees!,
      bearing,
      coneHalfAngle: coneHalfAngleDegrees,
    );
  }

  @override
  double calculateRelevanceScore({
    required DrivingPosition position,
    required UpcomingAnomaly anomaly,
  }) {
    final distance = GeospatialMath.haversineDistanceMeters(
      position.latitude,
      position.longitude,
      anomaly.latitude,
      anomaly.longitude,
    );

    if (distance > maxLookaheadMeters) return 0.0;

    // Proximity factor: 1.0 at 0m down to 0.0 at maxLookaheadMeters
    final proximityWeight = (1.0 - (distance / maxLookaheadMeters)).clamp(0.0, 1.0);

    // Alignment factor: 1.0 directly ahead, 0.5 at cone boundary
    double alignmentWeight = 0.5;
    if (position.headingDegrees != null) {
      final bearing = GeospatialMath.calculateBearing(
        position.latitude,
        position.longitude,
        anomaly.latitude,
        anomaly.longitude,
      );
      final angleDiff = GeospatialMath.angularDifference(position.headingDegrees!, bearing).abs();
      alignmentWeight = (1.0 - (angleDiff / (coneHalfAngleDegrees * 1.5))).clamp(0.1, 1.0);
    }

    // Severity factor based on priorityScore (0..100) and defect type
    final severityBase = (anomaly.priorityScore / 100.0).clamp(0.1, 1.0);
    // Potholes (D40) have highest safety impact
    final defectBonus = anomaly.isPothole ? 0.25 : 0.0;
    // Multi-report confidence bonus
    final reportBonus = math.min(anomaly.reportCount * 0.05, 0.2);

    final score = (proximityWeight * 0.45) +
        (alignmentWeight * 0.25) +
        (severityBase * 0.20) +
        defectBonus +
        reportBonus;

    return score;
  }
}
