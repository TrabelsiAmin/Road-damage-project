import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

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
// Resize for model input
// ---------------------------------------------------------------------------

/// Resizes [source] to [size]×[size] preserving the aspect ratio via
/// letterboxing (fills unused area with 114-grey, matching Ultralytics default).
img.Image letterboxResize(img.Image source, int size) {
  final scale = size / (source.width > source.height ? source.width : source.height);
  final newW = (source.width  * scale).round();
  final newH = (source.height * scale).round();

  final resized  = img.copyResize(source, width: newW, height: newH,
      interpolation: img.Interpolation.linear);
  final padded   = img.Image(width: size, height: size,
      numChannels: 3, backgroundColor: img.ColorRgb8(114, 114, 114));

  final offsetX  = (size - newW) ~/ 2;
  final offsetY  = (size - newH) ~/ 2;

  img.compositeImage(padded, resized, dstX: offsetX, dstY: offsetY);
  return padded;
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
