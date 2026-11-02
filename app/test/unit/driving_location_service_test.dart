import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tariqmap/services/driving_location_service.dart';

void main() {
  group('DrivingLocationService', () {
    test('emits processed driving positions from stream', () async {
      final controller = StreamController<Position>();
      final service = DrivingLocationService(
        mockPositionStream: controller.stream,
        minMovementSpeedMps: 1.0,
      );

      final emissions = <dynamic>[];
      service.positionStream.listen(emissions.add);

      await service.startTracking();

      // First point moving East
      controller.add(Position(
        latitude: 36.8000,
        longitude: 10.1800,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 10.0,
        altitudeAccuracy: 1.0,
        heading: 90.0,
        headingAccuracy: 5.0,
        speed: 10.0,
        speedAccuracy: 0.5,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 1);
      expect(service.currentPosition?.headingDegrees, closeTo(90.0, 0.1));
      expect(service.currentPosition?.speedKmh, closeTo(36.0, 0.1));

      // Second point stopped (speed 0) -> preserves heading 90°
      controller.add(Position(
        latitude: 36.8001,
        longitude: 10.1805,
        timestamp: DateTime.now(),
        accuracy: 4.0,
        altitude: 10.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 50.0,
        speed: 0.0,
        speedAccuracy: 0.1,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 2);
      expect(service.currentPosition?.headingDegrees, closeTo(90.0, 0.1));

      await service.dispose();
      await controller.close();
    });
  });
}
