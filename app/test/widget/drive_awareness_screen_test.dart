import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tariqmap/models/upcoming_anomaly.dart';
import 'package:tariqmap/screens/drive_awareness_screen.dart';
import 'package:tariqmap/services/drive_alert_service.dart';
import 'package:tariqmap/services/drive_anomaly_repository.dart';
import 'package:tariqmap/services/driving_location_service.dart';
import 'package:tariqmap/services/route_matching_service.dart';
import 'package:tariqmap/services/upcoming_anomaly_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DriveAwarenessScreen Widget Tests', () {
    late StreamController<Position> positionController;
    late DrivingLocationService locationService;
    late MemoryDriveAnomalyRepository anomalyRepository;
    late UpcomingAnomalyService upcomingService;
    late DriveAlertService alertService;

    setUp(() {
      SharedPreferences.setMockInitialValues({'drive_awareness_disclaimer_accepted': true});
      positionController = StreamController<Position>.broadcast();
      locationService = DrivingLocationService(mockPositionStream: positionController.stream);
      anomalyRepository = MemoryDriveAnomalyRepository();
      upcomingService = UpcomingAnomalyService(routeMatcher: const ForwardConeRouteMatcher());
      alertService = DriveAlertService(soundEnabled: false, hapticEnabled: false);
    });

    tearDown(() async {
      await locationService.dispose();
      await positionController.close();
    });

    testWidgets('renders DriveAwarenessScreen and displays Clear Road Ahead initially', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DriveAwarenessScreen(
            locationService: locationService,
            anomalyRepository: anomalyRepository,
            upcomingService: upcomingService,
            alertService: alertService,
            skipDisclaimerForTesting: true,
            skipPermissionCheckForTesting: true,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      positionController.add(Position(
        latitude: 36.8000,
        longitude: 10.1800,
        timestamp: DateTime.now(),
        accuracy: 6.0,
        altitude: 10.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 12.0,
        speedAccuracy: 0.5,
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Road Clear Ahead'), findsOneWidget);
      expect(find.text('GPS Good'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('displays Anomaly Alert card when hazard detected ahead', (tester) async {
      anomalyRepository.add(UpcomingAnomaly(
        observationId: 'ahead-pothole',
        latitude: 36.8010,
        longitude: 10.1800,
        anomalyType: 'D40',
        priorityScore: 90.0,
        priorityLabel: 'critical',
        status: 'confirmed',
        createdAt: DateTime.now(),
        reportCount: 3,
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: DriveAwarenessScreen(
            locationService: locationService,
            anomalyRepository: anomalyRepository,
            upcomingService: upcomingService,
            alertService: alertService,
            skipDisclaimerForTesting: true,
            skipPermissionCheckForTesting: true,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      positionController.add(Position(
        latitude: 36.8000,
        longitude: 10.1800,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 10.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 12.0,
        speedAccuracy: 0.5,
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('POTHOLE'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('3 reports'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows safety disclaimer dialog on first run', (tester) async {
      SharedPreferences.setMockInitialValues({'drive_awareness_disclaimer_accepted': false});

      await tester.pumpWidget(
        MaterialApp(
          home: DriveAwarenessScreen(
            locationService: locationService,
            anomalyRepository: anomalyRepository,
            upcomingService: upcomingService,
            alertService: alertService,
            skipDisclaimerForTesting: false,
            skipPermissionCheckForTesting: true,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Safety First'), findsOneWidget);
      expect(find.text('I Agree & Understand'), findsOneWidget);

      await tester.tap(find.text('I Agree & Understand'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Safety First'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
