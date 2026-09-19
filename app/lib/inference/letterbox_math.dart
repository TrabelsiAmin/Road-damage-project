/// Pure letterbox geometry matching Ultralytics YOLO preprocessing.
///
/// Image → scale to fit [inputSize]×[inputSize] → pad with 114-grey.
/// Model boxes are in letterbox space; [toOriginalNorm] maps them back
/// to coordinates normalised against the original image.
class LetterboxMeta {
  const LetterboxMeta({
    required this.originalWidth,
    required this.originalHeight,
    required this.inputSize,
    required this.scale,
    required this.resizedWidth,
    required this.resizedHeight,
    required this.padX,
    required this.padY,
  });

  final int originalWidth;
  final int originalHeight;
  final int inputSize;
  final double scale;
  final int resizedWidth;
  final int resizedHeight;
  final int padX;
  final int padY;

  /// Computes letterbox layout for an image of [origW]×[origH].
  factory LetterboxMeta.compute({
    required int origW,
    required int origH,
    int inputSize = 640,
  }) {
    if (origW <= 0 || origH <= 0) {
      throw ArgumentError('Image dimensions must be positive');
    }
    final scale = inputSize / (origW > origH ? origW : origH);
    final newW = (origW * scale).round();
    final newH = (origH * scale).round();
    return LetterboxMeta(
      originalWidth: origW,
      originalHeight: origH,
      inputSize: inputSize,
      scale: scale,
      resizedWidth: newW,
      resizedHeight: newH,
      padX: (inputSize - newW) ~/ 2,
      padY: (inputSize - newH) ~/ 2,
    );
  }

  /// Converts a box in letterbox-normalised [0..1] space to original-image
  /// normalised [0..1] space (top-left x, y, width, height).
  (double, double, double, double) toOriginalNorm(
    double nx,
    double ny,
    double nw,
    double nh,
  ) {
    final px = nx * inputSize;
    final py = ny * inputSize;
    final pw = nw * inputSize;
    final ph = nh * inputSize;

    final ox = originalWidth == 0 ? 0.0 : (px - padX) / (originalWidth * scale);
    final oy = originalHeight == 0 ? 0.0 : (py - padY) / (originalHeight * scale);
    final ow = originalWidth == 0 ? 0.0 : pw / (originalWidth * scale);
    final oh = originalHeight == 0 ? 0.0 : ph / (originalHeight * scale);

    final x = ox.clamp(0.0, 1.0);
    final y = oy.clamp(0.0, 1.0);
    return (
      x,
      y,
      ow.clamp(0.0, 1.0 - x),
      oh.clamp(0.0, 1.0 - y),
    );
  }

  /// Converts a YOLO (cx, cy, w, h) prediction into original-image
  /// normalised boxes. If values look like pixels (`max > 1.5`) they are
  /// divided by [inputSize] first.
  (double, double, double, double) boxFromYolo(
    double cx,
    double cy,
    double bw,
    double bh,
  ) {
    final looksLikePixels = cx.abs() > 1.5 ||
        cy.abs() > 1.5 ||
        bw.abs() > 1.5 ||
        bh.abs() > 1.5;
    final ncx = looksLikePixels ? cx / inputSize : cx;
    final ncy = looksLikePixels ? cy / inputSize : cy;
    final nbw = looksLikePixels ? bw / inputSize : bw;
    final nbh = looksLikePixels ? bh / inputSize : bh;
    return toOriginalNorm(ncx - nbw / 2, ncy - nbh / 2, nbw, nbh);
  }
}
