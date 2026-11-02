import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/driving_position.dart';
import 'package:tariqmap/models/upcoming_anomaly.dart';
import 'package:tariqmap/services/route_matching_service.dart';

void main() {
  group('ForwardConeRouteMatcher', () {
    const matcher = ForwardConeRouteMatcher(
      coneHalfAngleDegrees: 35.0,
      maxLookaheadMeters: 400.0,
    );

    test('matches anomaly inside 35 degree cone', () {
      final pos = DrivingPosition(
        latitude: 36.8000,
        longitude: 10.1800,
        accuracyMeters: 5.0,
        speedMetersPerSecond: 10.0,
        headingDegrees: 90.0, // Heading East
        timestamp: DateTime.now(),
      );

      // East-Northeast at ~110m (bearing ~75°, difference ~15° <= 35°)
      final anomaly = UpcomingAnomaly(
        observationId: 'in-cone',
        latitude: 36.8003,
        longitude: 10.1812,
        anomalyType: 'D10',
        priorityScore: 50.0,
        priorityLabel: 'medium',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      expect(matcher.isAnomalyOnRoute(position: pos, anomaly: anomaly), isTrue);
    });

    test('rejects anomaly outside forward cone angle', () {
      final pos = DrivingPosition(
        latitude: 36.8000,
        longitude: 10.1800,
        accuracyMeters: 5.0,
        speedMetersPerSecond: 10.0,
        headingDegrees: 90.0, // Heading East
        timestamp: DateTime.now(),
      );

      // Bearing ~160° South-Southeast (difference ~70° > 35°)
      final anomaly = UpcomingAnomaly(
        observationId: 'out-cone',
        latitude: 36.7990,
        longitude: 10.1804,
        anomalyType: 'D10',
        priorityScore: 50.0,
        priorityLabel: 'medium',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      expect(matcher.isAnomalyOnRoute(position: pos, anomaly: anomaly), isFalse);
    });

    test('relevance score boosts potholes and closer distances', () {
      final pos = DrivingPosition(
        latitude: 36.8000,
        longitude: 10.1800,
        accuracyMeters: 5.0,
        speedMetersPerSecond: 10.0,
        headingDegrees: 0.0, // North
        timestamp: DateTime.now(),
      );

      final closePothole = UpcomingAnomaly(
        observationId: 'close-d40',
        latitude: 36.8005,
        longitude: 10.1800,
        anomalyType: 'D40',
        priorityScore: 90.0,
        priorityLabel: 'critical',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final farCrack = UpcomingAnomaly(
        observationId: 'far-d00',
        latitude: 36.8030,
        longitude: 10.1800,
        anomalyType: 'D00',
        priorityScore: 30.0,
        priorityLabel: 'low',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final scoreClose = matcher.calculateRelevanceScore(position: pos, anomaly: closePothole);
      final scoreFar = matcher.calculateRelevanceScore(position: pos, anomaly: farCrack);

      expect(scoreClose, greaterThan(scoreFar));
    });
  });
}
