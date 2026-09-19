import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'video_sampling.dart';

class ExtractedFrame {
  const ExtractedFrame({
    required this.index,
    required this.timestampMs,
    required this.file,
  });

  final int index;
  final int timestampMs;
  final File file;
}

class FrameExtractionException implements Exception {
  FrameExtractionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FrameExtractionResult {
  const FrameExtractionResult({
    required this.frames,
    required this.errors,
    required this.sessionDir,
    required this.sampledTimestamps,
  });

  final List<ExtractedFrame> frames;
  final List<String> errors;
  final Directory sessionDir;
  final List<int> sampledTimestamps;
}

/// Extracts JPEG frames from a local video file.
///
/// Uses the platform thumbnail APIs (MediaMetadataRetriever / AVAssetImageGenerator)
/// via `video_thumbnail`. That is the reliable Flutter-compatible extract path.
///
/// Annotated MP4 encoding is handled separately by FfmpegVideoMuxer when
/// the FFmpeg CLI is installed. This extractor does not mux.
class VideoFrameExtractor {
  VideoFrameExtractor({this.jpegQuality = 80, this.maxFrames = 40});

  final int jpegQuality;
  final int maxFrames;

  Future<FrameExtractionResult> extract({
    required File video,
    required int intervalMs,
    required int durationMs,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!await video.exists()) {
      throw FrameExtractionException('Video file not found: ${video.path}');
    }
    if (!VideoSampling.isSupportedPath(video.path)) {
      throw FrameExtractionException(
        'Unsupported video format: ${p.extension(video.path)}. '
        'Supported: ${VideoSampling.supportedExtensions.join(', ')}',
      );
    }
    if (durationMs <= 0) {
      throw FrameExtractionException('Video has zero duration or failed to decode.');
    }

    final timestamps = VideoSampling.timestampsMs(
      durationMs: durationMs,
      intervalMs: intervalMs,
      maxFrames: maxFrames,
    );
    if (timestamps.isEmpty) {
      throw FrameExtractionException('No sample timestamps (empty video).');
    }

    final sessionDir = await _sessionDir();
    final frames = <ExtractedFrame>[];
    final errors = <String>[];

    for (var i = 0; i < timestamps.length; i++) {
      final t = timestamps[i];
      onProgress?.call(i, timestamps.length);
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: video.path,
          imageFormat: ImageFormat.JPEG,
          timeMs: t,
          quality: jpegQuality,
        );
        if (bytes == null || bytes.isEmpty) {
          errors.add('Empty frame at ${t}ms (codec or seek failure)');
          continue;
        }
        final file = File(p.join(sessionDir.path, 'frame_${i.toString().padLeft(4, '0')}_${t}ms.jpg'));
        await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
        frames.add(ExtractedFrame(index: i, timestampMs: t, file: file));
      } catch (e) {
        errors.add('Frame at ${t}ms failed: $e');
      }
    }

    if (frames.isEmpty) {
      await cleanup(sessionDir);
      throw FrameExtractionException(
        'No frames could be extracted. The codec may be unsupported '
        'or the file may be corrupted. Details: ${errors.join('; ')}',
      );
    }

    return FrameExtractionResult(
      frames: frames,
      errors: errors,
      sessionDir: sessionDir,
      sampledTimestamps: timestamps,
    );
  }

  Future<Directory> _sessionDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(
      tmp.path,
      'tariqmap_video_frames',
      DateTime.now().millisecondsSinceEpoch.toString(),
    ));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<void> cleanup(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
