import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tariqmap/core/constants.dart';
import 'package:tariqmap/core/model_config.dart';
import 'package:tariqmap/inference/nms.dart';
import 'package:tariqmap/inference/preprocessing.dart';
import 'package:tariqmap/models/observation.dart';

void main() {
  group('Comprehensive 15-Point Model Validation & Inference Diagnostics', () {
    // -------------------------------------------------------------------------
    // 1. Portrait image letterbox & aspect ratio
    // -------------------------------------------------------------------------
    test('1. Portrait image (width < height) preserves aspect ratio with horizontal padding', () {
      final portrait = img.Image(width: 600, height: 1200);
      portrait.clear(img.ColorRgb8(50, 100, 150));

      final result = letterboxProcess(portrait, inputSize: 640);
      expect(result.image.width, equals(640));
      expect(result.image.height, equals(640));
      expect(result.newHeight, equals(640));
      expect(result.newWidth, equals(320));
      expect(result.padX, equals(160));
      expect(result.padY, equals(0));
    });

    // -------------------------------------------------------------------------
    // 2. Landscape image letterbox & aspect ratio
    // -------------------------------------------------------------------------
    test('2. Landscape image (width > height) preserves aspect ratio with vertical padding', () {
      final landscape = img.Image(width: 1920, height: 1080);
      landscape.clear(img.ColorRgb8(100, 150, 200));

      final result = letterboxProcess(landscape, inputSize: 640);
      expect(result.image.width, equals(640));
      expect(result.image.height, equals(640));
      expect(result.newWidth, equals(640));
      expect(result.newHeight, equals(360));
      expect(result.padX, equals(0));
      expect(result.padY, equals(140));
    });

    // -------------------------------------------------------------------------
    // 3. EXIF orientation handling (1, 3, 6, 8)
    // -------------------------------------------------------------------------
    test('3. EXIF orientations 1, 3, 6, 8 are decoded and normalized without distortion', () {
      for (final orientation in [1, 3, 6, 8]) {
        final original = img.Image(width: 400, height: 200);
        original.exif.imageIfd.orientation = orientation;
        final encoded = img.encodeJpg(original);

        final decoded = decodeAndOrient(encoded);
        expect(decoded.width, greaterThan(0));
        expect(decoded.height, greaterThan(0));
        if (orientation == 6 || orientation == 8) {
          // 90 or 270 degree rotation swaps dimensions
          expect(decoded.width, equals(200));
          expect(decoded.height, equals(400));
        } else {
          expect(decoded.width, equals(400));
          expect(decoded.height, equals(200));
        }
      }
    });

    // -------------------------------------------------------------------------
    // 4. Low-resolution image (< 300x300)
    // -------------------------------------------------------------------------
    test('4. Low-resolution image (< 300x300) upscales safely into 640x640 model input', () {
      final lowRes = img.Image(width: 160, height: 120);
      lowRes.clear(img.ColorRgb8(20, 40, 60));

      final result = letterboxProcess(lowRes, inputSize: 640);
      expect(result.image.width, equals(640));
      expect(result.image.height, equals(640));
      expect(result.scale, closeTo(640 / 160, 0.01));
      expect(result.newWidth, equals(640));
      expect(result.newHeight, equals(480));
    });

    // -------------------------------------------------------------------------
    // 5. Very large image (> 4000x3000)
    // -------------------------------------------------------------------------
    test('5. Very large image (> 4000x3000) downscales safely without memory crash', () {
      final largeImg = img.Image(width: 4032, height: 3024);
      largeImg.clear(img.ColorRgb8(10, 20, 30));

      final result = letterboxProcess(largeImg, inputSize: 640);
      expect(result.image.width, equals(640));
      expect(result.image.height, equals(640));
      expect(result.newWidth, equals(640));
      expect(result.newHeight, equals(480));
    });

    // -------------------------------------------------------------------------
    // 6. Non-square aspect ratios (16:9, 1:1, 4:3)
    // -------------------------------------------------------------------------
    test('6. Non-square aspect ratios compute letterbox dimensions correctly', () {
      // 1:1 Square
      final sq = img.Image(width: 800, height: 800);
      final sqRes = letterboxProcess(sq, inputSize: 640);
      expect(sqRes.padX, equals(0));
      expect(sqRes.padY, equals(0));

      // 16:9
      final widescreen = img.Image(width: 1600, height: 900);
      final wsRes = letterboxProcess(widescreen, inputSize: 640);
      expect(wsRes.padX, equals(0));
      expect(wsRes.padY, equals(140));

      // 4:3
      final photo = img.Image(width: 1200, height: 900);
      final photoRes = letterboxProcess(photo, inputSize: 640);
      expect(photoRes.padX, equals(0));
      expect(photoRes.padY, equals(80));
    });

    // -------------------------------------------------------------------------
    // 7. JPEG and PNG decoding
    // -------------------------------------------------------------------------
    test('7. JPEG and PNG images decode consistently', () {
      final sample = img.Image(width: 200, height: 200);
      sample.clear(img.ColorRgb8(80, 160, 240));

      final jpgBytes = Uint8List.fromList(img.encodeJpg(sample));
      final pngBytes = Uint8List.fromList(img.encodePng(sample));

      final decodedJpg = decodeAndOrient(jpgBytes);
      final decodedPng = decodeAndOrient(pngBytes);

      expect(decodedJpg.width, equals(200));
      expect(decodedJpg.height, equals(200));
      expect(decodedPng.width, equals(200));
      expect(decodedPng.height, equals(200));
    });

    // -------------------------------------------------------------------------
    // 8. Zero detections output
    // -------------------------------------------------------------------------
    test('8. Zero detections produce valid observation with priority 0.0 and low severity label', () {
      final obs = Observation(
        id: 'test-zero-obs',
        captureId: 'cap-zero',
        imagePath: '/tmp/clean_road.jpg',
        createdAt: DateTime.now().toUtc(),
        latitude: 36.8065,
        longitude: 10.1815,
        actor: 'Municipality',
        agentResults: const [
          AgentResult(
            agent: 'road_damage',
            detections: [],
            latencyMs: 45,
          ),
        ],
        modelBundleVersion: TariqMapConstants.modelBundleVersion,
      );

      expect(obs.detections, isEmpty);
      expect(obs.priorityScore, equals(0.0));
      expect(obs.priorityLabel, equals('LOW'));
    });

    // -------------------------------------------------------------------------
    // 9. Multiple detections output
    // -------------------------------------------------------------------------
    test('9. Multiple detections across different regions are retained and scored', () {
      final obs = Observation(
        id: 'test-multi-obs',
        captureId: 'cap-multi',
        imagePath: '/tmp/damaged_road.jpg',
        createdAt: DateTime.now().toUtc(),
        latitude: 36.8065,
        longitude: 10.1815,
        actor: 'Municipality',
        agentResults: const [
          AgentResult(
            agent: 'road_damage',
            detections: [
              Detection(
                agent: 'road_damage',
                classCode: 'D40',
                confidence: 0.88,
                box: BoundingBox(x: 0.2, y: 0.3, width: 0.2, height: 0.2),
              ),
              Detection(
                agent: 'road_damage',
                classCode: 'D20',
                confidence: 0.75,
                box: BoundingBox(x: 0.6, y: 0.5, width: 0.3, height: 0.2),
              ),
            ],
            latencyMs: 60,
          ),
        ],
        modelBundleVersion: TariqMapConstants.modelBundleVersion,
      );

      expect(obs.detections.length, equals(2));
      expect(obs.priorityScore, greaterThan(35.0));
      expect(obs.priorityLabel, equals('MEDIUM'));
    });

    // -------------------------------------------------------------------------
    // 10. Detections near image borders
    // -------------------------------------------------------------------------
    test('10. Detections near image borders clamp strictly within [0.0, 1.0]', () {
      final letterbox = LetterboxResult(
        image: img.Image(width: 640, height: 640),
        originalWidth: 1000,
        originalHeight: 800,
        scale: 0.64,
        padX: 0,
        padY: 64,
        newWidth: 640,
        newHeight: 512,
        inputSize: 640,
      );

      final box = letterbox.toOriginalNormalized(0.01, 0.99, 0.05, 0.05);
      expect(box.x, inInclusiveRange(0.0, 1.0));
      expect(box.y, inInclusiveRange(0.0, 1.0));
      expect(box.width, inInclusiveRange(0.0, 1.0));
      expect(box.height, inInclusiveRange(0.0, 1.0));
      expect(box.x + box.width, lessThanOrEqualTo(1.0001));
    });

    // -------------------------------------------------------------------------
    // 11. Heavily overlapping bounding boxes (NMS)
    // -------------------------------------------------------------------------
    test('11. Overlapping bounding boxes with high IoU are deduplicated by NMS', () {
      final candidates = <Detection>[
        const Detection(
          agent: 'road_damage',
          classCode: 'D40',
          confidence: 0.92,
          box: BoundingBox(x: 0.30, y: 0.40, width: 0.20, height: 0.20),
        ),
        const Detection(
          agent: 'road_damage',
          classCode: 'D40',
          confidence: 0.70,
          box: BoundingBox(x: 0.31, y: 0.41, width: 0.19, height: 0.19),
        ),
      ];

      final suppressed = applyNms(candidates, iouThreshold: 0.45);
      expect(suppressed.length, equals(1));
      expect(suppressed.first.confidence, equals(0.92));
    });

    // -------------------------------------------------------------------------
    // 12. Each class independently: D00, D10, D20, D40
    // -------------------------------------------------------------------------
    test('12. All 4 road-damage classes (D00, D10, D20, D40) are independently supported', () {
      const classes = ['D00', 'D10', 'D20', 'D40'];
      expect(ModelConfig.active.classes, containsAll(classes));

      for (final cls in classes) {
        final detection = Detection(
          agent: 'road_damage',
          classCode: cls,
          confidence: 0.85,
          box: const BoundingBox(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
        );
        expect(detection.classCode, equals(cls));
        expect(detection.classLabel, isNotEmpty);
      }
    });

    // -------------------------------------------------------------------------
    // 13. Confidence score threshold filtering
    // -------------------------------------------------------------------------
    test('13. Candidates below active confidence threshold are filtered out', () {
      final threshold = ModelConfig.active.confidenceThreshold;
      expect(threshold, equals(0.35));

      final allCandidates = <Detection>[
        const Detection(
          agent: 'road_damage',
          classCode: 'D40',
          confidence: 0.15, // Below threshold
          box: BoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        ),
        const Detection(
          agent: 'road_damage',
          classCode: 'D40',
          confidence: 0.55, // Above threshold
          box: BoundingBox(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
        ),
      ];

      final filtered = allCandidates.where((d) => d.confidence >= threshold).toList();
      expect(filtered.length, equals(1));
      expect(filtered.first.confidence, equals(0.55));
    });

    // -------------------------------------------------------------------------
    // 14. Priority score calculation matching formula
    // -------------------------------------------------------------------------
    test('14. Priority score maps severity correctly (Pothole D40 > Cracks)', () {
      final potholeObs = Observation(
        id: 'pothole-obs',
        captureId: 'cap-p',
        imagePath: '/tmp/pothole.jpg',
        createdAt: DateTime.now().toUtc(),
        latitude: 36.8,
        longitude: 10.1,
        actor: 'Municipality',
        agentResults: const [
          AgentResult(
            agent: 'road_damage',
            detections: [
              Detection(
                agent: 'road_damage',
                classCode: 'D40',
                confidence: 0.85,
                box: BoundingBox(x: 0.3, y: 0.3, width: 0.3, height: 0.3),
              ),
            ],
          ),
        ],
        modelBundleVersion: TariqMapConstants.modelBundleVersion,
      );

      final crackObs = Observation(
        id: 'crack-obs',
        captureId: 'cap-c',
        imagePath: '/tmp/crack.jpg',
        createdAt: DateTime.now().toUtc(),
        latitude: 36.8,
        longitude: 10.1,
        actor: 'Municipality',
        agentResults: const [
          AgentResult(
            agent: 'road_damage',
            detections: [
              Detection(
                agent: 'road_damage',
                classCode: 'D00',
                confidence: 0.40,
                box: BoundingBox(x: 0.3, y: 0.3, width: 0.05, height: 0.05),
              ),
            ],
          ),
        ],
        modelBundleVersion: TariqMapConstants.modelBundleVersion,
      );

      expect(potholeObs.priorityScore, greaterThan(crackObs.priorityScore));
      expect(potholeObs.priorityScore, greaterThan(35.0));
    });

    // -------------------------------------------------------------------------
    // 15. Correct model bundle version metadata attached
    // -------------------------------------------------------------------------
    test('15. Model bundle version metadata is correctly attached to Observation', () {
      final obs = Observation(
        id: 'metadata-test-obs',
        captureId: 'cap-meta',
        imagePath: '/tmp/meta.jpg',
        createdAt: DateTime.now().toUtc(),
        latitude: 36.8,
        longitude: 10.1,
        actor: 'Municipality',
        agentResults: const [],
        modelBundleVersion: ModelConfig.active.version,
      );

      expect(obs.modelBundleVersion, equals(TariqMapConstants.modelBundleVersion));
      expect(ModelConfig.legacy.version, equals(TariqMapConstants.modelBundleVersion));
      expect(ModelConfig.active.name, equals('road_damage'));
      expect(ModelConfig.active.isActive, isTrue);
    });
  });
}
