import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';

void main() {
  // ---------------------------------------------------------------------------
  // BoundingBox.toPixels
  // ---------------------------------------------------------------------------

  group('BoundingBox.toPixels', () {
    test('full-frame box covers entire image', () {
      const box = BoundingBox(x: 0.0, y: 0.0, width: 1.0, height: 1.0);
      final (x, y, w, h) = box.toPixels(640, 480);
      expect(x, equals(0.0));
      expect(y, equals(0.0));
      expect(w, equals(640.0));
      expect(h, equals(480.0));
    });

    test('centred 50% box converts correctly', () {
      const box = BoundingBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5);
      final (x, y, w, h) = box.toPixels(1000, 1000);
      expect(x, closeTo(250.0, 1e-6));
      expect(y, closeTo(250.0, 1e-6));
      expect(w, closeTo(500.0, 1e-6));
      expect(h, closeTo(500.0, 1e-6));
    });

    test('non-square image scales each axis independently', () {
      const box = BoundingBox(x: 0.5, y: 0.5, width: 0.5, height: 0.5);
      final (x, y, w, h) = box.toPixels(1920, 1080);
      expect(x, closeTo(960.0, 1e-6));
      expect(y, closeTo(540.0, 1e-6));
      expect(w, closeTo(960.0, 1e-6));
      expect(h, closeTo(540.0, 1e-6));
    });

    test('single pixel reference maps correctly', () {
      // A box at exactly 0.5 in each dimension, sized 0.1 of 640
      const box = BoundingBox(x: 0.5, y: 0.5, width: 0.1, height: 0.1);
      final (x, y, w, h) = box.toPixels(640, 640);
      expect(x, closeTo(320.0, 1e-6));
      expect(y, closeTo(320.0, 1e-6));
      expect(w, closeTo(64.0, 1e-6));
      expect(h, closeTo(64.0, 1e-6));
    });
  });

  // ---------------------------------------------------------------------------
  // Detection model fields
  // ---------------------------------------------------------------------------

  group('Detection', () {
    test('classLabel returns canonical label from constants', () {
      const d = Detection(
        agent: 'pavement', classCode: 'D40', confidence: 0.9,
        box: BoundingBox(x: 0, y: 0, width: 0.1, height: 0.1),
      );
      expect(d.classLabel, equals('Pothole'));
    });

    test('unknown classCode has stable classLabel fallback', () {
      const d = Detection(
        agent: 'test', classCode: 'D99', confidence: 0.5,
        box: BoundingBox(x: 0, y: 0, width: 0.1, height: 0.1),
      );
      // Should not throw — returns the raw code
      expect(d.classLabel, equals('D99'));
    });
  });
}
