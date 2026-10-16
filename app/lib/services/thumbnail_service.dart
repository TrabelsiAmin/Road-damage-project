import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/observation.dart';
import 'image_compressor.dart';

/// Service responsible for generating and gating public blurred thumbnails.
///
/// Privacy Constraints:
/// - Bucket `public-photos` is public and accessible without authentication.
/// - Unblurred full-frame photos MUST NEVER be uploaded to `public-photos`.
/// - Thumbnail = crop of the primary detection box with a 25% margin (max 800 px, WebP under 250 KB).
/// - Additionally, everything inside the crop that lies outside the detection box is heavily blurred
///   so nearby people or license plates in the margin are unreadable.
/// - When there is no detection, the thumbnail is skipped entirely.
class ThumbnailService {
  ThumbnailService._();

  /// Long side constraint for public thumbnails.
  static const int maxLongSide = 800;

  /// Max file size constraint (250 KB, well under the 300 KB bucket limit).
  static const int maxFileSizeBytes = 250 * 1024;

  /// Preferences key for the user toggle.
  static const String prefKeyShareBlurred = 'share_blurred_public_photo';

  /// Thumbnail upload is enabled using Option A (crop around detected damage + margin blur).
  static const bool isThumbnailUploadEnabled = true;

  /// Codebase audit finding:
  /// The app currently contains RoadSense ML models for road damage (D00, D10, D20, D40).
  /// It DOES NOT contain any face detection (e.g. BlazeFace) or license plate detection models.
  /// Therefore, privacy is guaranteed strictly via the crop-and-blur path (Option A).
  static const bool hasReliableFaceAndPlateBlur = false;

  /// Checks if the user has enabled public thumbnail sharing in Settings.
  /// Enabled by default.
  static Future<bool> isPublicSharingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefKeyShareBlurred) ?? true;
  }

  /// Evaluates whether a public thumbnail should be uploaded for an observation.
  /// Strictly requires:
  /// 1. User toggle is ON in settings.
  /// 2. Gate is enabled.
  /// 3. Observation has at least one detection (skips when no detection).
  static Future<bool> shouldUploadPublicThumbnail({
    required List<Detection> detections,
  }) async {
    final enabled = await isPublicSharingEnabled();
    if (!enabled) {
      debugPrint('[ThumbnailService] Public thumbnail upload disabled by user setting.');
      return false;
    }
    if (!isThumbnailUploadEnabled) {
      debugPrint('[ThumbnailService] Public thumbnail upload gate is OFF.');
      return false;
    }
    if (detections.isEmpty) {
      debugPrint('[ThumbnailService] Observation has 0 detections. Skipping thumbnail.');
      return false;
    }
    return true;
  }

  /// Option A (Crop around primary detection + Margin Blur):
  /// 1. Crops around the primary detection box with a 25% margin.
  /// 2. Blurs everything inside the crop that lies outside the detection box (heavy blur)
  ///    so nearby people or plates in the margin are not readable.
  /// 3. Resizes to max 800 px on the long side and encodes to WebP (< 250 KB).
  /// 4. Skips and returns null when there is no detection.
  static Future<Uint8List?> createDetectionCropThumbnail({
    required Uint8List originalBytes,
    required List<Detection> detections,
    double marginFactor = 0.25,
  }) async {
    // Skip the thumbnail when there is no detection
    if (detections.isEmpty) {
      debugPrint('[ThumbnailService] No detections. Skipping thumbnail.');
      return null;
    }

    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) return null;

    final imgW = decoded.width;
    final imgH = decoded.height;

    // Identify primary detection (highest confidence)
    final sorted = [...detections]..sort((a, b) => b.confidence.compareTo(a.confidence));
    final best = sorted.first;

    final bx = (best.box.x * imgW).round();
    final by = (best.box.y * imgH).round();
    final bw = (best.box.width * imgW).round();
    final bh = (best.box.height * imgH).round();

    if (bw <= 0 || bh <= 0) return null;

    // 1. Target crop size with 25% margin (bw * 1.5, bh * 1.5)
    double cropW = bw * (1.0 + 2 * marginFactor);
    double cropH = bh * (1.0 + 2 * marginFactor);

    // 2. Enforce minimum crop of at least 40% of the image's shorter side in BOTH width and height
    final shorterSide = min(imgW, imgH);
    final minCrop = shorterSide * 0.40;
    if (cropW < minCrop) cropW = minCrop;
    if (cropH < minCrop) cropH = minCrop;

    // 3. Enforce maximum aspect ratio of 2.5:1 (expand the shorter dimension)
    const maxAspectRatio = 2.5;
    if (cropW / cropH > maxAspectRatio) {
      cropH = cropW / maxAspectRatio;
    } else if (cropH / cropW > maxAspectRatio) {
      cropW = cropH / maxAspectRatio;
    }

    // Never exceed the source image dimensions
    if (cropW > imgW) cropW = imgW.toDouble();
    if (cropH > imgH) cropH = imgH.toDouble();

    final finalCropW = cropW.round().clamp(1, imgW);
    final finalCropH = cropH.round().clamp(1, imgH);

    // 4. Center on the detection box and clamp to image bounds
    final boxCenterX = bx + bw / 2.0;
    final boxCenterY = by + bh / 2.0;

    double idealX = boxCenterX - finalCropW / 2.0;
    double idealY = boxCenterY - finalCropH / 2.0;

    if (idealX < 0) {
      idealX = 0;
    } else if (idealX + finalCropW > imgW) {
      idealX = (imgW - finalCropW).toDouble();
    }

    if (idealY < 0) {
      idealY = 0;
    } else if (idealY + finalCropH > imgH) {
      idealY = (imgH - finalCropH).toDouble();
    }

    final cropX = idealX.round().clamp(0, imgW - finalCropW);
    final cropY = idealY.round().clamp(0, imgH - finalCropH);

    // 5. Crop around detection box
    final cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: finalCropW,
      height: finalCropH,
    );

    // 6. Heavy blur on the entire cropped region
    final blurred = img.gaussianBlur(img.Image.from(cropped), radius: 25);

    // 7. Keep sharp the detection box, plus a small 10% feather around the box
    final inCropX = bx - cropX;
    final inCropY = by - cropY;
    final boxLeft = inCropX;
    final boxTop = inCropY;
    final boxRight = inCropX + bw;
    final boxBottom = inCropY + bh;

    final featherX = max(1, (bw * 0.10).round());
    final featherY = max(1, (bh * 0.10).round());

    final startX = max(0, boxLeft - featherX);
    final endX = min(cropped.width, boxRight + featherX);
    final startY = max(0, boxTop - featherY);
    final endY = min(cropped.height, boxBottom + featherY);

    for (int y = startY; y < endY; y++) {
      for (int x = startX; x < endX; x++) {
        int dx = 0;
        if (x < boxLeft) {
          dx = boxLeft - x;
        } else if (x >= boxRight) {
          dx = x - (boxRight - 1);
        }

        int dy = 0;
        if (y < boxTop) {
          dy = boxTop - y;
        } else if (y >= boxBottom) {
          dy = y - (boxBottom - 1);
        }

        if (dx == 0 && dy == 0) {
          // Strictly inside detection box: 100% sharp
          blurred.setPixel(x, y, cropped.getPixel(x, y));
        } else if (dx <= featherX && dy <= featherY) {
          // In 10% feather transition: blend sharp and blur smoothly
          final distNorm = max(dx / featherX, dy / featherY);
          final alpha = (1.0 - distNorm).clamp(0.0, 1.0);
          final sharp = cropped.getPixel(x, y);
          final blur = blurred.getPixel(x, y);
          final r = (sharp.r * alpha + blur.r * (1.0 - alpha)).round().clamp(0, 255);
          final g = (sharp.g * alpha + blur.g * (1.0 - alpha)).round().clamp(0, 255);
          final b = (sharp.b * alpha + blur.b * (1.0 - alpha)).round().clamp(0, 255);
          blurred.setPixelRgb(x, y, r, g, b);
        }
      }
    }

    // 8. Resize and compress to WebP (< 250 KB, max 800 px)
    return _resizeAndEncode(blurred);
  }

  /// Resizes the image so its longest side is at most [maxLongSide] and encodes to WebP.
  /// Never upscales beyond the source image dimensions.
  static Future<Uint8List> _resizeAndEncode(img.Image image) async {
    final w = image.width;
    final h = image.height;

    img.Image resized = image;
    if (w > maxLongSide || h > maxLongSide) {
      if (w >= h) {
        resized = img.copyResize(image, width: maxLongSide);
      } else {
        resized = img.copyResize(image, height: maxLongSide);
      }
    }

    // 1. Try pure Dart WebP encoder if supported by package:image
    try {
      final webpBytes = Uint8List.fromList(img.encodeWebP(resized, quality: 75));
      if (webpBytes.lengthInBytes <= maxFileSizeBytes) {
        return webpBytes;
      }
    } catch (_) {}

    // 2. Try platform WebP compression (Android native)
    try {
      final pngBytes = Uint8List.fromList(img.encodePng(resized));
      final compressed = await ImageCompressor.compressBytes(
        pngBytes,
        quality: 75,
        maxDim: maxLongSide,
      );

      if (compressed.bytes.lengthInBytes <= maxFileSizeBytes) {
        return compressed.bytes;
      }
    } catch (_) {}

    // 3. Fallback encoding (pure Dart JPEG) if platform WebP compressor is unavailable
    int q = 75;
    Uint8List fallbackBytes = Uint8List.fromList(img.encodeJpg(resized, quality: q));
    while (fallbackBytes.lengthInBytes > maxFileSizeBytes && q > 20) {
      q -= 15;
      fallbackBytes = Uint8List.fromList(img.encodeJpg(resized, quality: q));
    }
    return fallbackBytes;
  }
}
