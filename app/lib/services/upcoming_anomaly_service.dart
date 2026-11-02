import '../models/driving_position.dart';
import '../models/upcoming_anomaly.dart';
import '../utils/geospatial_math.dart';
import 'route_matching_service.dart';

/// Evaluates nearby road anomalies relative to vehicle heading and position,
/// selecting the single most critical and relevant anomaly ahead.
class UpcomingAnomalyService {
  UpcomingAnomalyService({
    RouteMatchingService? routeMatcher,
    this.maxAlertDistanceMeters = 300.0,
    this.gpsAccuracyThresholdMeters = 50.0,
    this.passedDistanceThresholdMeters = 15.0,
  }) : _routeMatcher = routeMatcher ?? const ForwardConeRouteMatcher();

  final RouteMatchingService _routeMatcher;
  final double maxAlertDistanceMeters;
  final double gpsAccuracyThresholdMeters;
  final double passedDistanceThresholdMeters;

  final Set<String> _passedAnomalyIds = {};

  /// Marks an anomaly as passed so it will not be selected again in this session.
  void markAnomalyPassed(String id) {
    _passedAnomalyIds.add(id);
  }

  /// Clears passed anomalies history (e.g. on new trip).
  void clearPassedHistory() {
    _passedAnomalyIds.clear();
  }

  /// Evaluates candidate anomalies and selects the next relevant upcoming anomaly.
  UpcomingAnomalyResult evaluateUpcomingAnomaly({
    required DrivingPosition position,
    required List<UpcomingAnomaly> candidates,
  }) {
    // 1. Check GPS accuracy
    if (!position.isAccurate(thresholdMeters: gpsAccuracyThresholdMeters)) {
      return UpcomingAnomalyResult(
        anomaly: null,
        distanceMeters: null,
        bearingDegrees: null,
        angularDifferenceDegrees: null,
        isReliable: false,
        reason: 'Weak GPS signal (±${position.accuracyMeters.toStringAsFixed(0)}m)',
      );
    }

    if (candidates.isEmpty) {
      return UpcomingAnomalyResult.none;
    }

    // 2. Filter candidates
    final validCandidates = <_CandidateMatch>[];

    for (final anomaly in candidates) {
      // Check if already passed
      if (_passedAnomalyIds.contains(anomaly.observationId)) {
        continue;
      }

      final distance = GeospatialMath.haversineDistanceMeters(
        position.latitude,
        position.longitude,
        anomaly.latitude,
        anomaly.longitude,
      );

      // Skip if beyond max alert distance
      if (distance > maxAlertDistanceMeters) {
        continue;
      }

      // Check if passed (behind vehicle and very close or behind)
      if (position.headingDegrees != null) {
        final bearing = GeospatialMath.calculateBearing(
          position.latitude,
          position.longitude,
          anomaly.latitude,
          anomaly.longitude,
        );

        if (GeospatialMath.isBehindVehicle(position.headingDegrees!, bearing)) {
          if (distance <= passedDistanceThresholdMeters) {
            _passedAnomalyIds.add(anomaly.observationId);
          }
          continue;
        }

        // Check if on route / within forward cone
        if (!_routeMatcher.isAnomalyOnRoute(position: position, anomaly: anomaly)) {
          continue;
        }

        final angleDiff = GeospatialMath.angularDifference(position.headingDegrees!, bearing);
        final score = _routeMatcher.calculateRelevanceScore(position: position, anomaly: anomaly);

        validCandidates.add(_CandidateMatch(
          anomaly: anomaly,
          distanceMeters: distance,
          bearingDegrees: bearing,
          angularDifferenceDegrees: angleDiff,
          relevanceScore: score,
        ));
      } else {
        // Heading unavailable (e.g. vehicle stationary at start)
        if (distance <= 60.0) {
          validCandidates.add(_CandidateMatch(
            anomaly: anomaly,
            distanceMeters: distance,
            bearingDegrees: null,
            angularDifferenceDegrees: null,
            relevanceScore: 100.0 - distance,
          ));
        }
      }
    }

    if (validCandidates.isEmpty) {
      return UpcomingAnomalyResult.none;
    }

    // 3. Rank candidates:
    // Highest relevance score first. In case of ties, nearest distance first.
    validCandidates.sort((a, b) {
      final scoreCompare = b.relevanceScore.compareTo(a.relevanceScore);
      if (scoreCompare != 0) return scoreCompare;
      return a.distanceMeters.compareTo(b.distanceMeters);
    });

    final best = validCandidates.first;
    final distFormatted = best.distanceMeters < 1000
        ? '${best.distanceMeters.toStringAsFixed(0)} m'
        : '${(best.distanceMeters / 1000.0).toStringAsFixed(1)} km';

    return UpcomingAnomalyResult(
      anomaly: best.anomaly,
      distanceMeters: best.distanceMeters,
      bearingDegrees: best.bearingDegrees,
      angularDifferenceDegrees: best.angularDifferenceDegrees,
      isReliable: true,
      reason: '${best.anomaly.humanReadableType} ahead in $distFormatted',
    );
  }
}

class _CandidateMatch {
  final UpcomingAnomaly anomaly;
  final double distanceMeters;
  final double? bearingDegrees;
  final double? angularDifferenceDegrees;
  final double relevanceScore;

  _CandidateMatch({
    required this.anomaly,
    required this.distanceMeters,
    this.bearingDegrees,
    this.angularDifferenceDegrees,
    required this.relevanceScore,
  });
}
