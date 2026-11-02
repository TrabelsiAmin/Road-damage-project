import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/utils/geospatial_math.dart';

void main() {
  group('GeospatialMath', () {
    test('haversineDistanceMeters returns zero for identical coordinates', () {
      final dist = GeospatialMath.haversineDistanceMeters(36.8065, 10.1815, 36.8065, 10.1815);
      expect(dist, closeTo(0.0, 0.01));
    });

    test('haversineDistanceMeters calculates accurate distance for known points', () {
      // Tunis (36.8065, 10.1815) to Ariana (36.8665, 10.1956) is ~6.8 km
      final dist = GeospatialMath.haversineDistanceMeters(36.8065, 10.1815, 36.8665, 10.1956);
      expect(dist, greaterThan(6500.0));
      expect(dist, lessThan(7100.0));
    });

    test('calculateBearing calculates Cardinal directions correctly', () {
      // Moving directly north
      final northBearing = GeospatialMath.calculateBearing(36.0, 10.0, 37.0, 10.0);
      expect(northBearing, closeTo(0.0, 0.5));

      // Moving directly east
      final eastBearing = GeospatialMath.calculateBearing(36.0, 10.0, 36.0, 11.0);
      expect(eastBearing, closeTo(90.0, 0.5));

      // Moving directly south
      final southBearing = GeospatialMath.calculateBearing(37.0, 10.0, 36.0, 10.0);
      expect(southBearing, closeTo(180.0, 0.5));

      // Moving directly west
      final westBearing = GeospatialMath.calculateBearing(36.0, 11.0, 36.0, 10.0);
      expect(westBearing, closeTo(270.0, 0.5));
    });

    test('angularDifference handles standard and wrap-around angles across 0/360', () {
      // Heading 0 (North), Target 20 (North-East) -> +20 (right)
      expect(GeospatialMath.angularDifference(0, 20), closeTo(20.0, 0.001));

      // Heading 20, Target 0 -> -20 (left)
      expect(GeospatialMath.angularDifference(20, 0), closeTo(-20.0, 0.001));

      // Heading 355 (near North), Target 10 (across 0) -> +15 (right)
      expect(GeospatialMath.angularDifference(355, 10), closeTo(15.0, 0.001));

      // Heading 10, Target 355 -> -15 (left)
      expect(GeospatialMath.angularDifference(10, 355), closeTo(-15.0, 0.001));

      // Exactly opposite (180 degrees)
      expect(GeospatialMath.angularDifference(0, 180).abs(), closeTo(180.0, 0.001));
    });

    test('isWithinForwardCone respects cone half angle', () {
      // Heading 90 (East), Target 110 (Bearing 110) -> diff is 20, within 35
      expect(GeospatialMath.isWithinForwardCone(90, 110, coneHalfAngle: 35), isTrue);

      // Heading 90, Target 130 -> diff is 40, outside 35
      expect(GeospatialMath.isWithinForwardCone(90, 130, coneHalfAngle: 35), isFalse);

      // Wrap around: Heading 5, Target 350 -> diff is 15, within 35
      expect(GeospatialMath.isWithinForwardCone(5, 350, coneHalfAngle: 35), isTrue);
    });

    test('isBehindVehicle correctly identifies anomalies behind', () {
      // Heading 0, Target 180 -> Behind
      expect(GeospatialMath.isBehindVehicle(0, 180), isTrue);

      // Heading 0, Target 85 -> Ahead/side (diff <= 90)
      expect(GeospatialMath.isBehindVehicle(0, 85), isFalse);

      // Heading 0, Target 95 -> Behind (diff > 90)
      expect(GeospatialMath.isBehindVehicle(0, 95), isTrue);
    });

    test('smoothHeading smoothly transitions across 0/360 boundary', () {
      // Current 350, New 10 (diff is +20). With alpha=0.5, result should be 0
      final smoothed = GeospatialMath.smoothHeading(350, 10, alpha: 0.5);
      expect(smoothed, closeTo(0.0, 0.01));

      // Current null returns new
      expect(GeospatialMath.smoothHeading(null, 120), closeTo(120.0, 0.01));
    });
  });
}
