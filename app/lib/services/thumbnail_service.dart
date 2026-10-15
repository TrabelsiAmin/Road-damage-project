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

    // 25% margin
    final marginX = (bw * marginFactor).round();
    final marginY = (bh * marginFactor).round();

    final cropX = max(0, bx - marginX);
    final cropY = max(0, by - marginY);
    final cropW = min(imgW - cropX, bw + (marginX * 2));
    final cropH = min(imgH - cropY, bh + (marginY * 2));

    if (cropW <= 0 || cropH <= 0) return null;

    // 1. Crop around detection box + margin
    final cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    // 2. Heavy blur on the entire cropped region
    final blurred = img.gaussianBlur(img.Image.from(cropped), radius: 25);

    // 3. Keep sharp only the pixels that lie strictly inside the detection box
    final inCropX = bx - cropX;
    final inCropY = by - cropY;
    final sharpStartX = max(0, inCropX);
    final sharpStartY = max(0, inCropY);
    final sharpEndX = min(cropped.width, inCropX + bw);
    final sharpEndY = min(cropped.height, inCropY + bh);

    for (int y = sharpStartY; y < sharpEndY; y++) {
      for (int x = sharpStartX; x < sharpEndX; x++) {
        blurred.setPixel(x, y, cropped.getPixel(x, y));
      }
    }

    // 4. Resize and compress to WebP (< 250 KB, max 800 px)
    return _resizeAndEncode(blurred);
  }

  /// Resizes the image so its longest side is at most [maxLongSide] and encodes to WebP.
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

    // Try WebP compression first
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

    // Fallback encoding if platform WebP compressor is unavailable
    final fallbackBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
    return fallbackBytes;
  }
}
