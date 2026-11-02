import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/upcoming_anomaly.dart';
import 'package:tariqmap/services/drive_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DriveAlertService', () {
    late DriveAlertService alertService;

    setUp(() {
      alertService = DriveAlertService(
        soundEnabled: false, // Disabled sound during unit test
        hapticEnabled: false, // Disabled haptics during unit test
        warningDistanceMeters: 180.0,
        urgentDistanceMeters: 60.0,
        alertCooldown: const Duration(seconds: 30),
      );
    });

    test('triggers alert when anomaly enters warning range', () async {
      final anomaly = UpcomingAnomaly(
        observationId: 'obs-1',
        latitude: 36.8010,
        longitude: 10.1800,
        anomalyType: 'D40',
        priorityScore: 80.0,
        priorityLabel: 'high',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final result = UpcomingAnomalyResult(
        anomaly: anomaly,
        distanceMeters: 120.0,
        bearingDegrees: 0.0,
        angularDifferenceDegrees: 0.0,
        isReliable: true,
        reason: 'Pothole ahead',
      );

      final triggered = await alertService.processAlert(result);
      expect(triggered, isTrue);
    });

    test('suppresses alert when distance is outside warning range', () async {
      final anomaly = UpcomingAnomaly(
        observationId: 'obs-2',
        latitude: 36.8030,
        longitude: 10.1800,
        anomalyType: 'D40',
        priorityScore: 80.0,
        priorityLabel: 'high',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final result = UpcomingAnomalyResult(
        anomaly: anomaly,
        distanceMeters: 250.0, // > 180m
        bearingDegrees: 0.0,
        angularDifferenceDegrees: 0.0,
        isReliable: true,
        reason: 'Pothole ahead',
      );

      final triggered = await alertService.processAlert(result);
      expect(triggered, isFalse);
    });

    test('suppresses repeated alerts within cooldown window unless escalating to urgent', () async {
      final anomaly = UpcomingAnomaly(
        observationId: 'obs-3',
        latitude: 36.8010,
        longitude: 10.1800,
        anomalyType: 'D10',
        priorityScore: 50.0,
        priorityLabel: 'medium',
        status: 'confirmed',
        createdAt: DateTime.now(),
      );

      final warningResult = UpcomingAnomalyResult(
        anomaly: anomaly,
        distanceMeters: 140.0,
        bearingDegrees: 0.0,
        angularDifferenceDegrees: 0.0,
        isReliable: true,
        reason: 'Transverse crack ahead',
      );

      // First alert fires
      expect(await alertService.processAlert(warningResult), isTrue);

      // Second check at 120m (same zone, within cooldown) should be suppressed
      final secondResult = UpcomingAnomalyResult(
        anomaly: anomaly,
        distanceMeters: 120.0,
        bearingDegrees: 0.0,
        angularDifferenceDegrees: 0.0,
        isReliable: true,
        reason: 'Transverse crack ahead',
      );
      expect(await alertService.processAlert(secondResult), isFalse);

      // Escalation into urgent zone (<= 60m) triggers urgent alert!
      final urgentResult = UpcomingAnomalyResult(
        anomaly: anomaly,
        distanceMeters: 45.0,
        bearingDegrees: 0.0,
        angularDifferenceDegrees: 0.0,
        isReliable: true,
        reason: 'Transverse crack ahead',
      );
      expect(await alertService.processAlert(urgentResult), isTrue);
    });
  });
}
