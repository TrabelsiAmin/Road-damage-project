import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Plane layout extracted from a [CameraImage] so conversion can run
/// without depending on the camera plugin (unit-testable).
class RawCameraFrame {
  const RawCameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final int width;
  final int height;

  /// One of: `jpeg`, `bgra8888`, `yuv420`, `nv21`.
  final String format;
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int> bytesPerPixel;
}

/// Converts a camera frame to JPEG bytes.
///
/// Android live streams are typically YUV420_888 or NV21, not JPEG.
/// iOS live streams are typically BGRA8888. JPEG is only used when the
/// plugin is configured with [ImageFormatGroup.jpeg].
///
/// [rotationDegrees] rotates the RGB image to match the upright camera
/// preview (usually the camera sensor orientation).
Uint8List convertFrameToJpeg(
  RawCameraFrame frame, {
  int quality = 85,
  int rotationDegrees = 0,
}) {
  if (frame.format == 'jpeg') {
    if (frame.planes.isEmpty) {
      throw StateError('JPEG camera frame has no plane data');
    }
    return Uint8List.fromList(frame.planes.first);
  }
  var image = convertFrameToImage(frame);
  if (rotationDegrees % 360 != 0) {
    image = img.copyRotate(image, angle: rotationDegrees);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

img.Image convertFrameToImage(RawCameraFrame frame) {
  if (frame.width <= 0 || frame.height <= 0) {
    throw StateError('Empty camera frame (${frame.width}x${frame.height})');
  }
  switch (frame.format) {
    case 'bgra8888':
      return _bgraToImage(frame);
    case 'nv21':
      return _nv21ToImage(frame);
    case 'yuv420':
      return _yuv420ToImage(frame);
    default:
      throw UnsupportedError('Unsupported camera format: ${frame.format}');
  }
}

img.Image _bgraToImage(RawCameraFrame frame) {
  final w = frame.width;
  final h = frame.height;
  final bytes = frame.planes.first;
  final stride = frame.bytesPerRow.isNotEmpty ? frame.bytesPerRow.first : w * 4;
  final out = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    final row = y * stride;
    for (var x = 0; x < w; x++) {
      final i = row + x * 4;
      if (i + 2 >= bytes.length) continue;
      // BGRA
      out.setPixelRgb(x, y, bytes[i + 2], bytes[i + 1], bytes[i]);
    }
  }
  return out;
}

img.Image _nv21ToImage(RawCameraFrame frame) {
  final w = frame.width;
  final h = frame.height;
  final yPlane = frame.planes[0];
  final uvPlane = frame.planes.length > 1 ? frame.planes[1] : Uint8List(0);
  final yStride = frame.bytesPerRow.isNotEmpty ? frame.bytesPerRow[0] : w;
  final out = img.Image(width: w, height: h, numChannels: 3);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final yp = yPlane[y * yStride + x];
      final uvIndex = (y >> 1) * w + (x & ~1);
      var u = 128;
      var v = 128;
      if (uvIndex + 1 < uvPlane.length) {
        // NV21: VU interleaved
        v = uvPlane[uvIndex];
        u = uvPlane[uvIndex + 1];
      }
      final (r, g, b) = _yuvToRgb(yp, u, v);
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

img.Image _yuv420ToImage(RawCameraFrame frame) {
  if (frame.planes.length < 3) {
    throw StateError('YUV420 frame must have 3 planes, got ${frame.planes.length}');
  }
  final w = frame.width;
  final h = frame.height;
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = frame.planes[2];
  final yStride = frame.bytesPerRow[0];
  final uStride = frame.bytesPerRow.length > 1 ? frame.bytesPerRow[1] : (w ~/ 2);
  final uPixel = frame.bytesPerPixel.length > 1 ? frame.bytesPerPixel[1] : 1;
  final vPixel = frame.bytesPerPixel.length > 2 ? frame.bytesPerPixel[2] : 1;
  final out = img.Image(width: w, height: h, numChannels: 3);

  for (var y = 0; y < h; y++) {
    final uvRow = (y ~/ 2) * uStride;
    for (var x = 0; x < w; x++) {
      final yp = yPlane[y * yStride + x];
      final uvCol = (x ~/ 2) * uPixel;
      final uIndex = uvRow + uvCol;
      final vIndex = (y ~/ 2) * (frame.bytesPerRow.length > 2 ? frame.bytesPerRow[2] : uStride) +
          (x ~/ 2) * vPixel;
      final u = uIndex < uPlane.length ? uPlane[uIndex] : 128;
      final v = vIndex < vPlane.length ? vPlane[vIndex] : 128;
      final (r, g, b) = _yuvToRgb(yp, u, v);
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

(int, int, int) _yuvToRgb(int y, int u, int v) {
  final c = y - 16;
  final d = u - 128;
  final e = v - 128;
  final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
  final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
  final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
  return (r, g, b);
}
