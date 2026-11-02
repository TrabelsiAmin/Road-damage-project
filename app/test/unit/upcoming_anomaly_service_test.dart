import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/driving_position.dart';
import 'package:tariqmap/models/upcoming_anomaly.dart';
import 'package:tariqmap/services/route_matching_service.dart';
import 'package:tariqmap/services/upcoming_anomaly_service.dart';

void main() {
  group('UpcomingAnomalyService', () {
    late UpcomingAnomalyService service;

    setUp(() {
      service = UpcomingAnomalyService(
        routeMatcher: const ForwardConeRouteMatcher(coneHalfAngleDegrees: 35.0),
        maxAlertDistanceMeters: 300.0,
        gpsAccuracyThresholdMeters: 50.0,
      );
    });

    test('selects anomaly directly ahead within forward cone', () {
      // Vehicle at (36.8000, 10.1800) moving North (heading: 0°)
      final position = DrivingPosition(
        latitude: 36.8000,
        longitude: 10.1800,
        accuracyMeters: 8.0,
        speedMetersPerSecond: 12.0,
        headingDegrees: 0.0,
        timestamp: DateTime.now(),
      );

      // Anomaly ahead at (36.8010, 10.1800) ~111m North
      final pothole = UpcomingAnomaly(
        observationId: 'pothole-1',
        latitude: 36.8010,
        longitude: 10.1800,
        anomalyType: 'D40',
        priorityScore: 85.0,
        priorityLabel: 'high',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final result = service.evaluateUpcomingAnomaly(
        position: position,
        candidates: [pothole],
      );

      expect(result.hasAnomaly, isTrue);
      expect(result.anomaly?.observationId, 'pothole-1');
      expect(result.distanceMeters, isNotNull);
      expect(result.distanceMeters!, closeTo(111.0, 15.0));
      expect(result.isReliable, isTrue);
    });

    test('ignores anomalies strictly behind the vehicle', () {
      // Vehicle moving North (heading: 0°)
      final position = DrivingPosition(
        latitude: 36.8000,
        longitude: 10.1800,
        accuracyMeters: 8.0,
        speedMetersPerSecond: 12.0,
        headingDegrees: 0.0,
        timestamp: DateTime.now(),
      );

      // Anomaly South at (36.7990, 10.1800) ~111m South (bearing: 180°)
      final behindAnomaly = UpcomingAnomaly(
        observationId: 'behind-1',
        latitude: 36.7990,
        longitude: 10.1800,
        anomalyType: 'D00',
        priorityScore: 40.0,
        priorityLabel: 'low',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final result = service.evaluateUpcomingAnomaly(
        position: position,
        candidates: [behindAnomaly],
      );

      expect(result.hasAnomaly, isFalse);
    });

    test('ignores anomalies beyond max alert distance', () {
      final position = DrivingPosition(
        latitude: 36.8000,
        longitude: 10.1800,
        accuracyMeters: 5.0,
        speedMetersPerSecond: 10.0,
        headingDegrees: 0.0,
        timestamp: DateTime.now(),
      );

      // Far ahead at ~550m North
      final farAnomaly = UpcomingAnomaly(
        observationId: 'far-1',
        latitude: 36.8050,
        longitude: 10.1800,
        anomalyType: 'D40',
        priorityScore: 90.0,
        priorityLabel: 'critical',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final result = service.evaluateUpcomingAnomaly(
        position: position,
        candidates: [farAnomaly],
      );

      expect(result.hasAnomaly, isFalse);
    });

    test('ranks closer and higher severity anomalies higher', () {
      final position = DrivingPosition(
        latitude: 36.8000,
        longitude: 10.1800,
        accuracyMeters: 6.0,
        speedMetersPerSecond: 15.0,
        headingDegrees: 0.0,
        timestamp: DateTime.now(),
      );

      // Distant crack at ~220m
      final distantCrack = UpcomingAnomaly(
        observationId: 'distant-crack',
        latitude: 36.8020,
        longitude: 10.1800,
        anomalyType: 'D00',
        priorityScore: 30.0,
        priorityLabel: 'low',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      // Immediate pothole at ~60m
      final closePothole = UpcomingAnomaly(
        observationId: 'close-pothole',
        latitude: 36.8005,
        longitude: 10.1800,
        anomalyType: 'D40',
        priorityScore: 95.0,
        priorityLabel: 'critical',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final result = service.evaluateUpcomingAnomaly(
        position: position,
        candidates: [distantCrack, closePothole],
      );

      expect(result.hasAnomaly, isTrue);
      expect(result.anomaly?.observationId, 'close-pothole');
    });

    test('flags result as unreliable if GPS accuracy exceeds threshold', () {
      final poorGpsPosition = DrivingPosition(
        latitude: 36.8000,
        longitude: 10.1800,
        accuracyMeters: 75.0, // Exceeds 50m threshold
        speedMetersPerSecond: 10.0,
        headingDegrees: 0.0,
        timestamp: DateTime.now(),
      );

      final pothole = UpcomingAnomaly(
        observationId: 'pothole-1',
        latitude: 36.8005,
        longitude: 10.1800,
        anomalyType: 'D40',
        priorityScore: 80.0,
        priorityLabel: 'high',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final result = service.evaluateUpcomingAnomaly(
        position: poorGpsPosition,
        candidates: [pothole],
      );

      expect(result.isReliable, isFalse);
      expect(result.hasAnomaly, isFalse);
      expect(result.reason, contains('Weak GPS signal'));
    });

    test('passed anomaly is ignored once marked as passed', () {
      final position = DrivingPosition(
        latitude: 36.8000,
        longitude: 10.1800,
        accuracyMeters: 5.0,
        speedMetersPerSecond: 10.0,
        headingDegrees: 0.0,
        timestamp: DateTime.now(),
      );

      final anomaly = UpcomingAnomaly(
        observationId: 'passed-me',
        latitude: 36.8005,
        longitude: 10.1800,
        anomalyType: 'D40',
        priorityScore: 70.0,
        priorityLabel: 'high',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      service.markAnomalyPassed('passed-me');

      final result = service.evaluateUpcomingAnomaly(
        position: position,
        candidates: [anomaly],
      );

      expect(result.hasAnomaly, isFalse);
    });
  });
}
