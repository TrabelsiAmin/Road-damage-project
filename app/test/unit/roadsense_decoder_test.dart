import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tariqmap/inference/preprocessing.dart';
import 'package:tariqmap/inference/roadsense_decoder.dart';
import 'package:tariqmap/models/observation.dart';

void main() {
  group('RoadSense Golden Tests', () {
    late Map<String, dynamic> goldenData;
    late List<dynamic> records;

    setUpAll(() {
      final goldenFile = File('test/goldens/roadsense_goldens.json');
      expect(goldenFile.existsSync(), isTrue, reason: 'Golden JSON file must exist');
      final jsonStr = goldenFile.readAsStringSync();
      goldenData = json.decode(jsonStr) as Map<String, dynamic>;
      records = goldenData['records'] as List<dynamic>;
      expect(records.length, equals(5));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Letterbox Preprocessing & Geometry Verification
    // ─────────────────────────────────────────────────────────────────────────
    test('Letterbox preprocessing matches golden geometry across all 5 test images', () {
      for (final rawRecord in records) {
        final record = rawRecord as Map<String, dynamic>;
        final imageName = record['imageName'] as String;
        final expectedLb = record['letterbox'] as Map<String, dynamic>;

        final imageFile = File('test/goldens/images/$imageName');
        expect(imageFile.existsSync(), isTrue, reason: 'Image $imageName must exist');

        final decoded = img.decodeImage(imageFile.readAsBytesSync())!;
        expect(decoded.width, equals(record['originalWidth']));
        expect(decoded.height, equals(record['originalHeight']));

        final lb = letterboxProcess(decoded, inputSize: 640);

        expect(lb.scale, closeTo(expectedLb['scale'] as num, 1e-6));
        expect(lb.padX, equals(expectedLb['padX']));
        expect(lb.padY, equals(expectedLb['padY']));
        expect(lb.newWidth, equals(expectedLb['newWidth']));
        expect(lb.newHeight, equals(expectedLb['newHeight']));
        expect(lb.inputSize, equals(640));
        expect(lb.image.width, equals(640));
        expect(lb.image.height, equals(640));
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. NCHW Tensor Generation & Normalization
    // ─────────────────────────────────────────────────────────────────────────
    test('imageToNchwFloat32 creates valid [1, 3, 640, 640] normalized tensor', () {
      for (final rawRecord in records) {
        final record = rawRecord as Map<String, dynamic>;
        final imageName = record['imageName'] as String;
        final expectedStats = record['tensorSample'] as Map<String, dynamic>;

        final imageFile = File('test/goldens/images/$imageName');
        final decoded = img.decodeImage(imageFile.readAsBytesSync())!;
        final lb = letterboxProcess(decoded, inputSize: 640);
        final tensor = imageToNchwFloat32(lb.image);

        // Shape: 3 * 640 * 640 = 1,228,800 elements
        expect(tensor.length, equals(3 * 640 * 640));

        // Mean value check
        var sum = 0.0;
        for (var i = 0; i < tensor.length; i++) {
          final val = tensor[i];
          expect(val, greaterThanOrEqualTo(0.0));
          expect(val, lessThanOrEqualTo(1.0));
          sum += val;
        }
        final mean = sum / tensor.length;
        expect(mean, closeTo(expectedStats['mean'] as num, 0.05),
            reason: 'Mean RGB intensity for $imageName should match within tolerance');

        // Check center pixel RGB values
        const centerOffset = 320 * 640 + 320;
        final centerR = tensor[centerOffset];
        final centerG = tensor[640 * 640 + centerOffset];
        final centerB = tensor[2 * 640 * 640 + centerOffset];
        final expectedCenter = (expectedStats['center_pixel_rgb'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList();

        expect(centerR, closeTo(expectedCenter[0], 0.05));
        expect(centerG, closeTo(expectedCenter[1], 0.05));
        expect(centerB, closeTo(expectedCenter[2], 0.05));
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Inverse Coordinate Mapping (Letterbox -> Original Normalized)
    // ─────────────────────────────────────────────────────────────────────────
    test('LetterboxResult.toOriginalNormalized maps coordinates to golden boxes', () {
      for (final rawRecord in records) {
        final record = rawRecord as Map<String, dynamic>;
        final lbData = record['letterbox'] as Map<String, dynamic>;
        final finalDets = record['finalDetections'] as List<dynamic>;

        final lb = LetterboxResult(
          image: img.Image(width: 640, height: 640),
          originalWidth: record['originalWidth'] as int,
          originalHeight: record['originalHeight'] as int,
          scale: (lbData['scale'] as num).toDouble(),
          padX: lbData['padX'] as int,
          padY: lbData['padY'] as int,
          newWidth: lbData['newWidth'] as int,
          newHeight: lbData['newHeight'] as int,
          inputSize: 640,
        );

        for (final rawDet in finalDets) {
          final det = rawDet as Map<String, dynamic>;
          final lbBox = det['letterbox_box'] as Map<String, dynamic>;
          final expectedBox = det['box'] as Map<String, dynamic>;

          final mappedBox = lb.toOriginalNormalized(
            (lbBox['cx'] as num).toDouble(),
            (lbBox['cy'] as num).toDouble(),
            (lbBox['w'] as num).toDouble(),
            (lbBox['h'] as num).toDouble(),
          );

          expect(mappedBox.x, closeTo(expectedBox['x'] as num, 1e-4),
              reason: 'mapped box x for ${det['classCode']}');
          expect(mappedBox.y, closeTo(expectedBox['y'] as num, 1e-4),
              reason: 'mapped box y for ${det['classCode']}');
          expect(mappedBox.width, closeTo(expectedBox['width'] as num, 1e-4),
              reason: 'mapped box width for ${det['classCode']}');
          expect(mappedBox.height, closeTo(expectedBox['height'] as num, 1e-4),
              reason: 'mapped box height for ${det['classCode']}');
        }
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. End-to-End Decoder Verification on Full Model Output Tensors
    // ─────────────────────────────────────────────────────────────────────────
    test('RoadSenseDecoder.decode exactly matches Python goldens on full model output tensors', () {
      for (final rawRecord in records) {
        final record = rawRecord as Map<String, dynamic>;
        final imageName = record['imageName'] as String;
        final tensorFile = record['tensorFile'] as String?;
        if (tensorFile == null) continue;

        final binFile = File('test/goldens/$tensorFile');
        expect(binFile.existsSync(), isTrue, reason: 'Tensor bin $tensorFile must exist');

        final bytes = binFile.readAsBytesSync();
        expect(bytes.length, equals(1 * 9 * 8400 * 4), reason: 'Size of [1, 9, 8400] float32');

        final float32List = Float32List.view(bytes.buffer);

        // Convert flat buffer to [1, 9, 8400] nested List
        final output = List.generate(
          1,
          (_) => List.generate(
            9,
            (c) => List.generate(
              8400,
              (a) => float32List[c * 8400 + a],
            ),
          ),
        );

        final lbData = record['letterbox'] as Map<String, dynamic>;
        final lb = LetterboxResult(
          image: img.Image(width: 640, height: 640),
          originalWidth: record['originalWidth'] as int,
          originalHeight: record['originalHeight'] as int,
          scale: (lbData['scale'] as num).toDouble(),
          padX: lbData['padX'] as int,
          padY: lbData['padY'] as int,
          newWidth: lbData['newWidth'] as int,
          newHeight: lbData['newHeight'] as int,
          inputSize: 640,
        );

        final decodedResult = RoadSenseDecoder.decode(
          output: output,
          letterbox: lb,
          iouThreshold: 0.45,
        );

        final expectedDets = record['finalDetections'] as List<dynamic>;

        // Assert detection count
        expect(decodedResult.crackDetections.length, equals(expectedDets.length),
            reason: 'Detection count for $imageName');

        // Assert each detection matches golden class, confidence, and bounding box
        for (var i = 0; i < expectedDets.length; i++) {
          final expDet = expectedDets[i] as Map<String, dynamic>;
          final actDet = decodedResult.crackDetections[i];
          final expBox = expDet['box'] as Map<String, dynamic>;

          expect(actDet.classCode, equals(expDet['classCode']));
          expect(actDet.confidence, closeTo(expDet['confidence'] as num, 1e-4));
          expect(actDet.box.x, closeTo(expBox['x'] as num, 1e-4));
          expect(actDet.box.y, closeTo(expBox['y'] as num, 1e-4));
          expect(actDet.box.width, closeTo(expBox['width'] as num, 1e-4));
          expect(actDet.box.height, closeTo(expBox['height'] as num, 1e-4));

          // Ensure D40 and Repair are never in crack detections
          expect(actDet.classCode, isNot(equals('D40')));
          expect(actDet.classCode, isNot(equals('Repair')));
        }
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Pothole / Repair Overlap Filter Verification
    // ─────────────────────────────────────────────────────────────────────────
    test('filterPotholesOverlappingRepairs drops D40 if Repair box overlaps IoU > 0.5', () {
      const pothole1 = Detection(
        agent: 'legacy',
        classCode: 'D40',
        confidence: 0.85,
        box: BoundingBox(x: 0.20, y: 0.30, width: 0.20, height: 0.20),
      );
      const pothole2 = Detection(
        agent: 'legacy',
        classCode: 'D40',
        confidence: 0.70,
        box: BoundingBox(x: 0.70, y: 0.70, width: 0.15, height: 0.15),
      );

      // Overlaps pothole1 heavily (IoU > 0.7)
      const repairOverlapping = Detection(
        agent: 'roadsense',
        classCode: 'Repair',
        confidence: 0.65,
        box: BoundingBox(x: 0.21, y: 0.31, width: 0.19, height: 0.19),
      );

      // Distant repair (IoU = 0)
      const repairDistant = Detection(
        agent: 'roadsense',
        classCode: 'Repair',
        confidence: 0.60,
        box: BoundingBox(x: 0.05, y: 0.05, width: 0.10, height: 0.10),
      );

      // Case 1: Overlapping repair suppresses pothole1, keeps pothole2
      final filtered = RoadSenseDecoder.filterPotholesOverlappingRepairs(
        [pothole1, pothole2],
        [repairOverlapping],
        iouThreshold: 0.5,
      );
      expect(filtered.length, equals(1));
      expect(filtered.first.box.x, equals(pothole2.box.x));

      // Case 2: Distant repair keeps both potholes
      final keepBoth = RoadSenseDecoder.filterPotholesOverlappingRepairs(
        [pothole1, pothole2],
        [repairDistant],
        iouThreshold: 0.5,
      );
      expect(keepBoth.length, equals(2));

      // Case 3: Empty repairs keeps all
      final emptyRepairs = RoadSenseDecoder.filterPotholesOverlappingRepairs(
        [pothole1, pothole2],
        const [],
        iouThreshold: 0.5,
      );
      expect(emptyRepairs.length, equals(2));
    });
  });
}
