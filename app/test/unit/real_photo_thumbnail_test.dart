import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tariqmap/core/constants.dart';
import 'package:tariqmap/inference/preprocessing.dart';
import 'package:tariqmap/inference/roadsense_decoder.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/thumbnail_service.dart';

void main() {
  const artifactDir = r'C:\Users\USERµ\.gemini\antigravity-ide\brain\f16b4cf3-66bc-4b41-ba6a-05705de17916';

  group('Real Photo Thumbnail Generation with Crop Geometry and Margin Blur', () {
    test('Image 1: Thin horizontal crack (Czech_000010.jpg)', () async {
      final imageFile = File('test/goldens/images/Czech_000010.jpg');
      expect(imageFile.existsSync(), isTrue);

      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes)!;
      expect(decodedImage.width, equals(600));
      expect(decodedImage.height, equals(600));

      final lb = letterboxProcess(decodedImage, inputSize: 640);
      final tensorFile = File('test/goldens/tensors/Czech_000010_output.bin');
      expect(tensorFile.existsSync(), isTrue);

      final tensorBytes = tensorFile.readAsBytesSync();
      final float32List = Float32List.view(tensorBytes.buffer);
      final modelOutput = List.generate(
        1,
        (_) => List.generate(
          9,
          (c) => List.generate(
            8400,
            (a) => float32List[c * 8400 + a],
          ),
        ),
      );

      final decodeResult = RoadSenseDecoder.decode(
        output: modelOutput,
        letterbox: lb,
        iouThreshold: 0.45,
      );
      final rawDetections = decodeResult.crackDetections;
      expect(rawDetections, isNotEmpty);

      final detections = rawDetections.map((d) => Detection(
        agent: 'road_damage',
        classCode: d.classCode,
        confidence: d.confidence,
        box: d.box,
        frameIndex: d.frameIndex,
        modelBundleVersion: TariqMapConstants.modelBundleVersion,
        timestamp: DateTime.now().toUtc(),
      )).toList();

      final primary = detections.first;
      // D10 transverse crack, width=0.171, height=0.035 (aspect ratio ~ 4.88:1)
      expect(primary.classCode, equals('D10'));
      expect(primary.box.width / primary.box.height, greaterThan(2.5));

      final thumbnailBytes = await ThumbnailService.createDetectionCropThumbnail(
        originalBytes: imageBytes,
        detections: detections,
      );

      expect(thumbnailBytes, isNotNull);
      final thumbSizeKb = thumbnailBytes!.lengthInBytes / 1024.0;
      expect(thumbSizeKb, lessThan(250.0), reason: 'Must be under 250 KB');

      final decodedThumb = img.decodeImage(thumbnailBytes)!;
      // Enforces minimum crop of at least 40% of shorter side: 600 * 0.40 = 240
      expect(decodedThumb.width, equals(240));
      expect(decodedThumb.height, equals(240));
      expect(decodedThumb.width, lessThanOrEqualTo(800));
      expect(decodedThumb.height, lessThanOrEqualTo(800));

      // Save files to artifact directory
      final fileWebp = File('$artifactDir/thumbnail_crack_thin.webp');
      await fileWebp.writeAsBytes(thumbnailBytes);
      final pngBytes = Uint8List.fromList(img.encodePng(decodedThumb));
      final filePng = File('$artifactDir/thumbnail_crack_thin.png');
      await filePng.writeAsBytes(pngBytes);

      // Also save crack_thumbnail_preview.webp / .png
      await File('$artifactDir/crack_thumbnail_preview.webp').writeAsBytes(thumbnailBytes);
      await File('$artifactDir/crack_thumbnail_preview.png').writeAsBytes(pngBytes);

      // ignore: avoid_print
      print('=== IMAGE 1: THIN HORIZONTAL CRACK ===');
      // ignore: avoid_print
      print('Source: Czech_000010.jpg (${decodedImage.width}x${decodedImage.height} px, ${(imageBytes.lengthInBytes / 1024).toStringAsFixed(1)} KB)');
      // ignore: avoid_print
      print('Detection: ${primary.classCode} (${(primary.confidence * 100).toStringAsFixed(1)}%)');
      // ignore: avoid_print
      print('Box: x=${primary.box.x.toStringAsFixed(3)}, y=${primary.box.y.toStringAsFixed(3)}, w=${primary.box.width.toStringAsFixed(3)}, h=${primary.box.height.toStringAsFixed(3)} (aspect ratio: ${(primary.box.width / primary.box.height).toStringAsFixed(2)})');
      // ignore: avoid_print
      print('Thumbnail: ${decodedThumb.width}x${decodedThumb.height} px, ${thumbSizeKb.toStringAsFixed(2)} KB');
      // ignore: avoid_print
      print('=======================================');
    });

    test('Image 2: Large pothole box (Japan_000008.jpg)', () async {
      final imageFile = File('test/goldens/images/Japan_000008.jpg');
      expect(imageFile.existsSync(), isTrue);

      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes)!;
      expect(decodedImage.width, equals(600));
      expect(decodedImage.height, equals(600));

      // Real ground-truth pothole from RDD benchmark (Japan_000008.txt: 3 0.801667 0.848333 0.236667 0.280000)
      final detections = [
        Detection(
          agent: 'pavement',
          classCode: 'D40',
          confidence: 0.88,
          box: const BoundingBox(
            x: 0.683333,
            y: 0.708333,
            width: 0.236667,
            height: 0.280000,
          ),
          modelBundleVersion: TariqMapConstants.modelBundleVersion,
          timestamp: DateTime.now().toUtc(),
        ),
      ];

      final primary = detections.first;
      expect(primary.classCode, equals('D40'));
      // Large pothole: area > 0.05
      final area = primary.box.width * primary.box.height;
      expect(area, greaterThan(0.05));

      final thumbnailBytes = await ThumbnailService.createDetectionCropThumbnail(
        originalBytes: imageBytes,
        detections: detections,
      );

      expect(thumbnailBytes, isNotNull);
      final thumbSizeKb = thumbnailBytes!.lengthInBytes / 1024.0;
      expect(thumbSizeKb, lessThan(250.0), reason: 'Must be under 250 KB');

      final decodedThumb = img.decodeImage(thumbnailBytes)!;
      expect(decodedThumb.width, lessThanOrEqualTo(800));
      expect(decodedThumb.height, lessThanOrEqualTo(800));
      // Aspect ratio <= 2.5:1
      expect(decodedThumb.width / decodedThumb.height, lessThanOrEqualTo(2.5));
      expect(decodedThumb.height / decodedThumb.width, lessThanOrEqualTo(2.5));

      // Save files to artifact directory
      final fileWebp = File('$artifactDir/thumbnail_pothole_large.webp');
      await fileWebp.writeAsBytes(thumbnailBytes);
      final pngBytes = Uint8List.fromList(img.encodePng(decodedThumb));
      final filePng = File('$artifactDir/thumbnail_pothole_large.png');
      await filePng.writeAsBytes(pngBytes);

      // ignore: avoid_print
      print('=== IMAGE 2: LARGE POTHOLE BOX ===');
      // ignore: avoid_print
      print('Source: Japan_000008.jpg (${decodedImage.width}x${decodedImage.height} px, ${(imageBytes.lengthInBytes / 1024).toStringAsFixed(1)} KB)');
      // ignore: avoid_print
      print('Detection: ${primary.classCode} (${(primary.confidence * 100).toStringAsFixed(1)}%)');
      // ignore: avoid_print
      print('Box: x=${primary.box.x.toStringAsFixed(3)}, y=${primary.box.y.toStringAsFixed(3)}, w=${primary.box.width.toStringAsFixed(3)}, h=${primary.box.height.toStringAsFixed(3)} (area: ${(area * 100).toStringAsFixed(2)}%)');
      // ignore: avoid_print
      print('Thumbnail: ${decodedThumb.width}x${decodedThumb.height} px, ${thumbSizeKb.toStringAsFixed(2)} KB');
      // ignore: avoid_print
      print('==================================');
    });

    test('Image 3: Box near image edge (China_Drone_000085.jpg)', () async {
      final imageFile = File('test/goldens/images/China_Drone_000085.jpg');
      expect(imageFile.existsSync(), isTrue);

      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes)!;
      expect(decodedImage.width, equals(512));
      expect(decodedImage.height, equals(512));

      // Golden detection from roadsense_goldens.json (China_Drone_000085: D10, x: 0.0, y: 0.0317)
      final detections = [
        Detection(
          agent: 'road_damage',
          classCode: 'D10',
          confidence: 0.627,
          box: const BoundingBox(
            x: 0.0,
            y: 0.031726,
            width: 1.0,
            height: 0.232448,
          ),
          modelBundleVersion: TariqMapConstants.modelBundleVersion,
          timestamp: DateTime.now().toUtc(),
        ),
      ];

      final primary = detections.first;
      // Edge box: x=0.0 touches left border
      expect(primary.box.x, equals(0.0));

      final thumbnailBytes = await ThumbnailService.createDetectionCropThumbnail(
        originalBytes: imageBytes,
        detections: detections,
      );

      expect(thumbnailBytes, isNotNull);
      final thumbSizeKb = thumbnailBytes!.lengthInBytes / 1024.0;
      expect(thumbSizeKb, lessThan(250.0), reason: 'Must be under 250 KB');

      final decodedThumb = img.decodeImage(thumbnailBytes)!;
      expect(decodedThumb.width, lessThanOrEqualTo(800));
      expect(decodedThumb.height, lessThanOrEqualTo(800));
      // Aspect ratio <= 2.5:1
      expect(decodedThumb.width / decodedThumb.height, lessThanOrEqualTo(2.5));
      expect(decodedThumb.height / decodedThumb.width, lessThanOrEqualTo(2.5));

      // Save files to artifact directory
      final fileWebp = File('$artifactDir/thumbnail_edge_box.webp');
      await fileWebp.writeAsBytes(thumbnailBytes);
      final pngBytes = Uint8List.fromList(img.encodePng(decodedThumb));
      final filePng = File('$artifactDir/thumbnail_edge_box.png');
      await filePng.writeAsBytes(pngBytes);

      // ignore: avoid_print
      print('=== IMAGE 3: BOX NEAR IMAGE EDGE ===');
      // ignore: avoid_print
      print('Source: China_Drone_000085.jpg (${decodedImage.width}x${decodedImage.height} px, ${(imageBytes.lengthInBytes / 1024).toStringAsFixed(1)} KB)');
      // ignore: avoid_print
      print('Detection: ${primary.classCode} (${(primary.confidence * 100).toStringAsFixed(1)}%)');
      // ignore: avoid_print
      print('Box: x=${primary.box.x.toStringAsFixed(3)}, y=${primary.box.y.toStringAsFixed(3)}, w=${primary.box.width.toStringAsFixed(3)}, h=${primary.box.height.toStringAsFixed(3)} (touches left edge x=0.0)');
      // ignore: avoid_print
      print('Thumbnail: ${decodedThumb.width}x${decodedThumb.height} px, ${thumbSizeKb.toStringAsFixed(2)} KB');
      // ignore: avoid_print
      print('====================================');
    });

    test('Requirement 3: Generates thumbnail with minimum crop when box area is below 0.5%', () async {
      final imageFile = File('test/goldens/images/Czech_000010.jpg');
      final imageBytes = await imageFile.readAsBytes();

      // Tiny box: 0.04 x 0.04 -> area = 0.0016 = 0.16% of image (< 0.5%)
      final detections = [
        Detection(
          agent: 'road_damage',
          classCode: 'D00',
          confidence: 0.90,
          box: const BoundingBox(
            x: 0.48,
            y: 0.48,
            width: 0.04,
            height: 0.04,
          ),
          modelBundleVersion: TariqMapConstants.modelBundleVersion,
          timestamp: DateTime.now().toUtc(),
        ),
      ];

      final area = detections.first.box.width * detections.first.box.height;
      expect(area, lessThan(0.005), reason: 'Box area must be below 0.5% of image');

      final thumbnailBytes = await ThumbnailService.createDetectionCropThumbnail(
        originalBytes: imageBytes,
        detections: detections,
      );

      expect(thumbnailBytes, isNotNull, reason: 'Must still generate thumbnail for box < 0.5% area');
      final decodedThumb = img.decodeImage(thumbnailBytes!)!;
      // Minimum crop is 40% of 600 = 240 px in both W and H
      expect(decodedThumb.width, equals(240));
      expect(decodedThumb.height, equals(240));
    });
  });
}
