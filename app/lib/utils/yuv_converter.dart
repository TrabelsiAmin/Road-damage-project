import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Converts a YUV420 CameraImage to a package:image Image.
img.Image convertYUV420ToImage(CameraImage cameraImage) {
  final width = cameraImage.width;
  final height = cameraImage.height;

  final uvRowStride = cameraImage.planes[1].bytesPerRow;
  final uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

  final image = img.Image(width: width, height: height, numChannels: 3);

  final yPlane = cameraImage.planes[0].bytes;
  final uPlane = cameraImage.planes[1].bytes;
  final vPlane = cameraImage.planes[2].bytes;

  var p = 0;
  for (var y = 0; y < height; y++) {
    final uvRow = (y >> 1) * uvRowStride;
    var yIndex = y * cameraImage.planes[0].bytesPerRow;

    for (var x = 0; x < width; x++) {
      final uvIndex = uvRow + (x >> 1) * uvPixelStride;

      final yValue = yPlane[yIndex++];
      final uValue = uPlane[uvIndex];
      final vValue = vPlane[uvIndex];

      final r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
      final g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).clamp(0, 255).toInt();
      final b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();

      image.setPixelRgb(x, y, r, g, b);
    }
  }

  return image;
}
