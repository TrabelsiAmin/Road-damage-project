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
  test('generates public cropped and blurred thumbnail from real crack photo Czech_000010.jpg', () async {
    final imageFile = File('test/goldens/images/Czech_000010.jpg');
    expect(imageFile.existsSync(), isTrue, reason: 'Czech_000010.jpg must exist');

    final imageBytes = await imageFile.readAsBytes();
    final decodedImage = img.decodeImage(imageBytes)!;
    expect(decodedImage.width, equals(600));
    expect(decodedImage.height, equals(600));

    // Run golden tensor through RoadSenseDecoder to get exact real detections
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

    // Generate thumbnail through ThumbnailService (Option A: crop primary box + 25% margin + margin blur)
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

    // Save thumbnail to artifacts directory
    const artifactDir = r'C:\Users\USERµ\.gemini\antigravity-ide\brain\f16b4cf3-66bc-4b41-ba6a-05705de17916';
    final artifactFile = File('$artifactDir/crack_thumbnail_preview.webp');
    await artifactFile.writeAsBytes(thumbnailBytes);
    expect(artifactFile.existsSync(), isTrue);

    // Also write a PNG copy so any standard image viewer/markdown renderer can display it without WebP codec quirks
    final pngBytes = Uint8List.fromList(img.encodePng(decodedThumb));
    final artifactPngFile = File('$artifactDir/crack_thumbnail_preview.png');
    await artifactPngFile.writeAsBytes(pngBytes);

    print('=== REAL PHOTO THUMBNAIL RESULTS ===');
    print('Original Image: Czech_000010.jpg (600 x 600 px, ${(imageBytes.lengthInBytes / 1024).toStringAsFixed(1)} KB)');
    print('Primary Detection: ${detections.first.classCode} (confidence: ${(detections.first.confidence * 100).toStringAsFixed(1)}%)');
    print('Primary Box: x=${detections.first.box.x.toStringAsFixed(3)}, y=${detections.first.box.y.toStringAsFixed(3)}, w=${detections.first.box.width.toStringAsFixed(3)}, h=${detections.first.box.height.toStringAsFixed(3)}');
    print('Thumbnail Dimensions: ${decodedThumb.width} x ${decodedThumb.height} px');
    print('Thumbnail File Size: ${thumbSizeKb.toStringAsFixed(2)} KB');
    print('Saved to: ${artifactFile.path}');
    print('=====================================');
  });
}
