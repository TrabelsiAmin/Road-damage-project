import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/inference/nms.dart';
import 'package:tariqmap/models/observation.dart';

void main() {
  // ---------------------------------------------------------------------------
  // IoU tests
  // ---------------------------------------------------------------------------

  group('computeIou', () {
    test('identical boxes → iou = 1.0', () {
      const box = BoundingBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5);
      expect(computeIou(box, box), closeTo(1.0, 1e-6));
    });

    test('non-overlapping boxes → iou = 0.0', () {
      const a = BoundingBox(x: 0.0, y: 0.0, width: 0.3, height: 0.3);
      const b = BoundingBox(x: 0.7, y: 0.7, width: 0.3, height: 0.3);
      expect(computeIou(a, b), equals(0.0));
    });

    test('50% overlap → iou ≈ 1/3', () {
      const a = BoundingBox(x: 0.0, y: 0.0, width: 0.4, height: 0.4);
      const b = BoundingBox(x: 0.2, y: 0.0, width: 0.4, height: 0.4);
      // Intersection: 0.2×0.4 = 0.08, Union: 0.16+0.16-0.08 = 0.24
      expect(computeIou(a, b), closeTo(0.08 / 0.24, 1e-6));
    });

    test('adjacent boxes (touching edge) → iou = 0.0', () {
      const a = BoundingBox(x: 0.0, y: 0.0, width: 0.5, height: 0.5);
      const b = BoundingBox(x: 0.5, y: 0.0, width: 0.5, height: 0.5);
      expect(computeIou(a, b), equals(0.0));
    });

    test('one box completely inside another', () {
      const outer = BoundingBox(x: 0.0, y: 0.0, width: 0.8, height: 0.8);
      const inner = BoundingBox(x: 0.2, y: 0.2, width: 0.2, height: 0.2);
      final innerArea = 0.2 * 0.2;
      final outerArea = 0.8 * 0.8;
      final expected = innerArea / (outerArea + innerArea - innerArea);
      expect(computeIou(outer, inner), closeTo(expected, 1e-6));
    });

    test('zero-area box → iou = 0.0 (no NaN)', () {
      const a = BoundingBox(x: 0.1, y: 0.1, width: 0.0, height: 0.0);
      const b = BoundingBox(x: 0.0, y: 0.0, width: 0.5, height: 0.5);
      expect(computeIou(a, b), equals(0.0));
    });
  });

  // ---------------------------------------------------------------------------
  // NMS tests
  // ---------------------------------------------------------------------------

  group('applyNms', () {
    Detection _det(String code, double conf, double x) => Detection(
      agent: 'test',
      classCode: code,
      confidence: conf,
      box: BoundingBox(x: x, y: 0.0, width: 0.3, height: 0.3),
    );

    test('empty input → empty output', () {
      expect(applyNms([]), isEmpty);
    });

    test('single detection → kept', () {
      final d = _det('D40', 0.9, 0.0);
      expect(applyNms([d]), hasLength(1));
    });

    test('two non-overlapping boxes → both kept', () {
      final d1 = _det('D40', 0.9, 0.0);
      final d2 = _det('D40', 0.8, 0.7);
      expect(applyNms([d1, d2]), hasLength(2));
    });

    test('two heavily-overlapping boxes → only highest confidence kept', () {
      // Both at x=0.0, nearly identical boxes
      final high = Detection(
        agent: 'test', classCode: 'D40', confidence: 0.9,
        box: const BoundingBox(x: 0.0, y: 0.0, width: 0.4, height: 0.4),
      );
      final low = Detection(
        agent: 'test', classCode: 'D40', confidence: 0.5,
        box: const BoundingBox(x: 0.01, y: 0.01, width: 0.4, height: 0.4),
      );
      final result = applyNms([high, low], iouThreshold: 0.45);
      expect(result, hasLength(1));
      expect(result.first.confidence, equals(0.9));
    });

    test('confidence filter removes low-confidence boxes', () {
      final d1 = _det('D40', 0.9, 0.0);
      final d2 = _det('D40', 0.2, 0.7);
      final result = applyNms([d1, d2], minConfidence: 0.35);
      expect(result, hasLength(1));
      expect(result.first.confidence, equals(0.9));
    });

    test('output is sorted by confidence descending', () {
      final d1 = _det('D40', 0.6, 0.0);
      final d2 = _det('D40', 0.9, 0.7);
      final d3 = _det('D40', 0.75, 0.35);
      final result = applyNms([d1, d2, d3]);
      expect(result.map((d) => d.confidence).toList(),
          orderedEquals([0.9, 0.75, 0.6]));
    });
  });

  // ---------------------------------------------------------------------------
  // Class-aware NMS tests
  // ---------------------------------------------------------------------------

  group('applyClassAwareNms', () {
    test('overlapping boxes of different classes are both kept', () {
      final d1 = Detection(
        agent: 'cracks', classCode: 'D00', confidence: 0.9,
        box: const BoundingBox(x: 0.0, y: 0.0, width: 0.4, height: 0.4),
      );
      final d2 = Detection(
        agent: 'pavement', classCode: 'D40', confidence: 0.85,
        box: const BoundingBox(x: 0.01, y: 0.01, width: 0.4, height: 0.4),
      );
      final result = applyClassAwareNms([d1, d2], iouThreshold: 0.5);
      expect(result, hasLength(2));
    });

    test('same class, overlapping → only highest kept', () {
      final d1 = Detection(
        agent: 'cracks', classCode: 'D40', confidence: 0.9,
        box: const BoundingBox(x: 0.0, y: 0.0, width: 0.4, height: 0.4),
      );
      final d2 = Detection(
        agent: 'cracks', classCode: 'D40', confidence: 0.5,
        box: const BoundingBox(x: 0.01, y: 0.01, width: 0.4, height: 0.4),
      );
      final result = applyClassAwareNms([d1, d2], iouThreshold: 0.45);
      expect(result, hasLength(1));
    });
  });
}
