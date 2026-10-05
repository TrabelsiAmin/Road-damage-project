import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Compresses anomaly images to WebP format before uploading to Supabase.
///
/// WebP at 75% quality typically saves 40-60% vs the original JPEG/PNG
/// with no perceptible quality loss for road inspection photos.
///
/// Usage:
///   final compressed = await ImageCompressor.compressToWebP(imageFile);
///   // Upload compressed.bytes to Supabase with mimeType compressed.mimeType
class ImageCompressor {
  ImageCompressor._();

  /// Default quality for WebP compression (0–100).
  static const int defaultQuality = 75;

  /// Maximum dimension (width or height). Larger images are scaled down
  /// proportionally. Keeps enough detail for road anomaly inspection.
  static const int maxDimension = 1280;

  /// Compresses [file] to WebP and returns the result.
  /// Falls back to the original bytes if compression fails or is unsupported.
  static Future<CompressedImage> compressToWebP(
    File file, {
    int quality = defaultQuality,
    int maxDim  = maxDimension,
  }) async {
    try {
      final Uint8List? compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth:  maxDim,
        minHeight: maxDim,
        quality:   quality,
        format:    CompressFormat.webp,
        keepExif:  false,   // strip GPS/EXIF metadata — not needed in the DB
      );

      if (compressed != null && compressed.isNotEmpty) {
        final originalSize = await file.length();
        final saving = ((1 - compressed.length / originalSize) * 100).round();
        debugPrint(
          '[ImageCompressor] ${p.basename(file.path)}: '
          '${_kb(originalSize)} → ${_kb(compressed.length)} '
          '(-$saving%)');

        return CompressedImage(
          bytes:    compressed,
          mimeType: 'image/webp',
          extension: 'webp',
          originalSizeBytes:   originalSize,
          compressedSizeBytes: compressed.length,
        );
      }
    } catch (e) {
      debugPrint('[ImageCompressor] Compression failed, using original: $e');
    }

    // Fallback: return original bytes
    final bytes = await file.readAsBytes();
    return CompressedImage(
      bytes:    bytes,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      originalSizeBytes:   bytes.length,
      compressedSizeBytes: bytes.length,
    );
  }

  /// Compresses raw JPEG bytes (e.g., from a camera stream) to WebP.
  static Future<CompressedImage> compressBytes(
    Uint8List input, {
    int quality = defaultQuality,
    int maxDim  = maxDimension,
  }) async {
    try {
      final Uint8List? compressed =
          await FlutterImageCompress.compressWithList(
        input,
        minWidth:  maxDim,
        minHeight: maxDim,
        quality:   quality,
        format:    CompressFormat.webp,
        keepExif:  false,
      );
      if (compressed != null && compressed.isNotEmpty) {
        debugPrint(
          '[ImageCompressor] bytes: ${_kb(input.length)} → '
          '${_kb(compressed.length)}');
        return CompressedImage(
          bytes:    compressed,
          mimeType: 'image/webp',
          extension: 'webp',
          originalSizeBytes:   input.length,
          compressedSizeBytes: compressed.length,
        );
      }
    } catch (e) {
      debugPrint('[ImageCompressor] Byte compression failed: $e');
    }
    return CompressedImage(
      bytes:    input,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      originalSizeBytes:   input.length,
      compressedSizeBytes: input.length,
    );
  }

  /// Saves compressed bytes to a temp file and returns it.
  /// Useful when a [File] path is required downstream.
  static Future<File> compressToTempFile(
    File source, {
    int quality = defaultQuality,
  }) async {
    final result = await compressToWebP(source, quality: quality);
    final dir    = await getTemporaryDirectory();
    final name   = '${p.basenameWithoutExtension(source.path)}.webp';
    final out    = File(p.join(dir.path, name));
    await out.writeAsBytes(result.bytes);
    return out;
  }

  static String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';
}

/// Result of an image compression operation.
class CompressedImage {
  const CompressedImage({
    required this.bytes,
    required this.mimeType,
    required this.extension,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
  });

  final Uint8List bytes;
  final String    mimeType;
  final String    extension;
  final int       originalSizeBytes;
  final int       compressedSizeBytes;

  /// How much space was saved (0.0–1.0).
  double get compressionRatio =>
      originalSizeBytes > 0
          ? 1 - (compressedSizeBytes / originalSizeBytes)
          : 0;

  int get savedBytes => originalSizeBytes - compressedSizeBytes;
}
