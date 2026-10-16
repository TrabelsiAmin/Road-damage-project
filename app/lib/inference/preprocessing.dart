import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/observation.dart';

// ---------------------------------------------------------------------------
// EXIF orientation — fix rotation before drawing bounding boxes
// ---------------------------------------------------------------------------

/// Returns an [img.Image] decoded from [bytes] with EXIF orientation applied.
///
/// This must be called before rendering bounding boxes; otherwise boxes will
/// be offset relative to the display orientation.
img.Image decodeAndOrient(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw ArgumentError('Cannot decode image bytes');
  // img.bakeOrientation applies the EXIF rotation/flip and clears the tag.
  return img.bakeOrientation(decoded);
}

// ---------------------------------------------------------------------------
// Resize and Letterbox for model input
// ---------------------------------------------------------------------------

/// Carries letterboxed image and geometry mapping needed to convert
/// letterboxed bounding boxes back to original image space.
class LetterboxResult {
  const LetterboxResult({
    required this.image,
    required this.originalWidth,
    required this.originalHeight,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.newWidth,
    required this.newHeight,
    required this.inputSize,
  });

  final img.Image image;
  final int originalWidth;
  final int originalHeight;
  final double scale;
  final int padX;
  final int padY;
  final int newWidth;
  final int newHeight;
  final int inputSize;

  /// Converts normalized letterbox-space coordinates (cx, cy, w, h in [0..1]
  /// relative to [inputSize]) to normalized [0..1] coordinates on the original image.
  BoundingBox toOriginalNormalized(double cx, double cy, double w, double h) {
    final boxCxPx = cx * inputSize;
    final boxCyPx = cy * inputSize;
    final boxWPx = w * inputSize;
    final boxHPx = h * inputSize;

    final origCx = (boxCxPx - padX) / scale;
    final origCy = (boxCyPx - padY) / scale;
    final origWBox = boxWPx / scale;
    final origHBox = boxHPx / scale;

    final normX = ((origCx - origWBox / 2.0) / originalWidth).clamp(0.0, 1.0);
    final normY = ((origCy - origHBox / 2.0) / originalHeight).clamp(0.0, 1.0);
    final normW = (origWBox / originalWidth).clamp(0.0, 1.0);
    final normH = (origHBox / originalHeight).clamp(0.0, 1.0);

    return BoundingBox(
      x: normX,
      y: normY,
      width: normW,
      height: normH,
    );
  }
}

/// Resizes [source] preserving aspect ratio and pads to [inputSize]×[inputSize]
/// with 114-grey (matching Ultralytics YOLO letterbox default).
LetterboxResult letterboxProcess(img.Image source, {int inputSize = 640}) {
  final origW = source.width;
  final origH = source.height;
  final scale = inputSize / (origW > origH ? origW : origH);
  final newW = (origW * scale).round();
  final newH = (origH * scale).round();

  final resized = img.copyResize(source, width: newW, height: newH,
      interpolation: img.Interpolation.linear);
  final padded = img.Image(width: inputSize, height: inputSize, numChannels: 3);
  padded.clear(img.ColorRgb8(114, 114, 114));

  final padX = (inputSize - newW) ~/ 2;
  final padY = (inputSize - newH) ~/ 2;

  img.compositeImage(padded, resized, dstX: padX, dstY: padY);

  return LetterboxResult(
    image: padded,
    originalWidth: origW,
    originalHeight: origH,
    scale: scale,
    padX: padX,
    padY: padY,
    newWidth: newW,
    newHeight: newH,
    inputSize: inputSize,
  );
}

/// Resizes [source] to [size]×[size] preserving the aspect ratio via
/// letterboxing (fills unused area with 114-grey, matching Ultralytics default).
img.Image letterboxResize(img.Image source, int size) =>
    letterboxProcess(source, inputSize: size).image;

/// Converts an [img.Image] (typically 640x640) into an NCHW [1, 3, H, W]
/// Float32List normalized to [0..1] in RGB order.
Float32List imageToNchwFloat32(img.Image image) {
  final width = image.width;
  final height = image.height;
  final planeSize = width * height;
  final flat = Float32List(3 * planeSize);
  final gOffset = planeSize;
  final bOffset = 2 * planeSize;

  var p = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      flat[p] = pixel.r / 255.0;
      flat[gOffset + p] = pixel.g / 255.0;
      flat[bOffset + p] = pixel.b / 255.0;
      p++;
    }
  }
  return flat;
}

// ---------------------------------------------------------------------------
// Build input tensor
// ---------------------------------------------------------------------------

/// Converts an [img.Image] to a [1, H, W, 3] float32 tensor normalised to
/// [0..1] in RGB order.  Returns a nested List matching TFLite input shape.
List<List<List<List<double>>>> imageToFloat32Tensor(img.Image image) {
  final w = image.width;
  final h = image.height;
  return [
    List.generate(h, (y) =>
      List.generate(w, (x) {
        final px = image.getPixel(x, y);
        return [
          px.rNormalized.toDouble(),
          px.gNormalized.toDouble(),
          px.bNormalized.toDouble(),
        ];
      }),
    ),
  ];
}

// ---------------------------------------------------------------------------
// Full pipeline: file → oriented decoded → letterboxed → tensor
// ---------------------------------------------------------------------------

/// Pre-processing result carrying the tensor and layout metadata needed to
/// map model output coordinates back to the original image.
class PreprocessingResult {
  const PreprocessingResult({
    required this.tensor,
    required this.originalWidth,
    required this.originalHeight,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.inputSize,
  });

  final List<List<List<List<double>>>> tensor;
  final int    originalWidth;
  final int    originalHeight;
  final double scale;
  final int    padX;
  final int    padY;
  final int    inputSize;

  /// Converts normalised model-output coordinates (relative to the letterboxed
  /// input) back to coordinates normalised to the original image dimensions.
  ///
  /// [nx], [ny], [nw], [nh] are in [0..1] relative to [inputSize]×[inputSize].
  /// Returns a 4-tuple (x, y, w, h) normalised to the original image.
  (double, double, double, double) toOriginalNorm(
      double nx, double ny, double nw, double nh) {
    // Pixel coords in letterboxed input
    final px = nx * inputSize;
    final py = ny * inputSize;
    final pw = nw * inputSize;
    final ph = nh * inputSize;

    // Remove padding
    final ox = (px - padX) / (originalWidth  * scale);
    final oy = (py - padY) / (originalHeight * scale);
    final ow = pw / (originalWidth  * scale);
    final oh = ph / (originalHeight * scale);

    return (
      ox.clamp(0.0, 1.0),
      oy.clamp(0.0, 1.0),
      ow.clamp(0.0, 1.0),
      oh.clamp(0.0, 1.0),
    );
  }
}

/// Full preprocessing pipeline: decode file → orient → letterbox → tensor.
Future<PreprocessingResult> preprocessImageFile(File file, {int inputSize = 640}) async {
  final bytes = await file.readAsBytes();
  return preprocessImageBytes(bytes, inputSize: inputSize);
}

/// Full preprocessing pipeline from raw bytes.
Future<PreprocessingResult> preprocessImageBytes(
    Uint8List bytes, {int inputSize = 640}) async {
  // Run CPU-heavy work off the UI thread
  return compute(_preprocessInIsolate, _PreprocessArgs(bytes, inputSize));
}

// ── Isolate helpers ──────────────────────────────────────────────────────────

class _PreprocessArgs {
  _PreprocessArgs(this.bytes, this.inputSize);
  final Uint8List bytes;
  final int inputSize;
}

PreprocessingResult _preprocessInIsolate(_PreprocessArgs args) {
  final oriented = decodeAndOrient(args.bytes);
  final origW = oriented.width;
  final origH = oriented.height;

  final scale = args.inputSize / (origW > origH ? origW : origH);
  final newW = (origW * scale).round();
  final newH = (origH * scale).round();
  final padX = (args.inputSize - newW) ~/ 2;
  final padY = (args.inputSize - newH) ~/ 2;

  final padded = letterboxResize(oriented, args.inputSize);
  final tensor = imageToFloat32Tensor(padded);

  return PreprocessingResult(
    tensor: tensor,
    originalWidth:  origW,
    originalHeight: origH,
    scale: scale,
    padX: padX,
    padY: padY,
    inputSize: args.inputSize,
  );
}
