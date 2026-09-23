import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// ---------------------------------------------------------------------------
// VideoFrameExtractor
// ---------------------------------------------------------------------------

/// Extracts JPEG frames from a local video file at given timestamps.
///
/// Uses the [video_thumbnail] package which calls platform-native decoders
/// (MediaMetadataRetriever on Android, AVFoundation on iOS).  This is far
/// more reliable than trying to decode a raw MP4 with the image package.
///
/// Usage:
/// ```dart
/// final extractor = VideoFrameExtractor();
/// final tempDir = await extractor.ensureTempDir();
/// final frameFile = await extractor.extractFrame(video, timestampSec: 5, tempDir: tempDir);
/// if (frameFile != null) {
///   final results = await detectionService.detectAll(frameFile);
/// }
/// await extractor.cleanupTempDir(tempDir);
/// ```
class VideoFrameExtractor {
  bool _cancelled = false;

  /// Returns a dedicated temp directory for this extraction session.
  /// The caller is responsible for calling [cleanupTempDir] when done.
  Future<Directory> ensureTempDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/tariqmap_frames');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Deletes all files inside [tempDir] without removing the directory itself.
  Future<void> cleanupTempDir(Directory tempDir) async {
    try {
      if (!tempDir.existsSync()) return;
      for (final entity in tempDir.listSync()) {
        if (entity is File) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[VideoFrameExtractor] cleanupTempDir error: $e');
    }
  }

  /// Signal that any pending [extractFrame] calls should return null early.
  void cancel() => _cancelled = true;

  /// Resets the cancelled state (call before starting a new extraction run).
  void reset() => _cancelled = false;

  /// Extracts a JPEG frame at [timestampSec] from [videoFile].
  ///
  /// Returns the extracted [File] on success, or null if extraction fails or
  /// [cancel] was called.  The returned file lives in [tempDir] with the name
  /// `frame_<timestampSec>.jpg`.
  ///
  /// [quality] — JPEG quality 0-100, default 85 (good for model input).
  Future<File?> extractFrame(
    File videoFile, {
    required int timestampSec,
    required Directory tempDir,
    int quality = 85,
  }) async {
    if (_cancelled) return null;

    final destPath = '${tempDir.path}/frame_$timestampSec.jpg';

    try {
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoFile.path,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        timeMs: timestampSec * 1000,
        quality: quality,
        // maxWidth / maxHeight not set — use native resolution then let
        // TFLiteAgentRunner resize to 640×640 as it always does.
      );

      if (_cancelled) return null;

      if (thumbnailPath == null) {
        debugPrint('[VideoFrameExtractor] No thumbnail at ${timestampSec}s');
        return null;
      }

      // video_thumbnail writes to a temp file with its own name; rename to
      // our canonical name so we can track and clean up by timestamp.
      final src = File(thumbnailPath);
      final dest = File(destPath);
      if (src.path != dest.path && src.existsSync()) {
        src.copySync(dest.path);
        src.deleteSync();
      }

      if (dest.existsSync() && dest.lengthSync() > 0) {
        debugPrint('[VideoFrameExtractor] Frame extracted: ${timestampSec}s → ${dest.path}');
        return dest;
      }

      debugPrint('[VideoFrameExtractor] Empty frame at ${timestampSec}s');
      return null;
    } catch (e) {
      debugPrint('[VideoFrameExtractor] extractFrame error at ${timestampSec}s: $e');
      return null;
    }
  }
}
