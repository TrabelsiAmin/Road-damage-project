import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

// ---------------------------------------------------------------------------
// VideoStitcher
// ---------------------------------------------------------------------------

/// Stitches a set of annotated JPEG frames back into an MP4 video using FFmpeg.
///
/// The output video preserves the original frame rate of the source video.
/// All frames that did NOT have detections are filled in from the original
/// (unannotated) frames to keep the video continuous.
///
/// Pipeline:
///   1. Build a concat list file (ffmpeg image2 demuxer format)
///   2. Run:  ffmpeg -f concat -safe 0 -i list.txt -c:v libx264 -pix_fmt yuv420p out.mp4
///   3. Return the output File path
class VideoStitcher {
  FFmpegSession? _activeSession;

  /// Cancel any running ffmpeg session.
  Future<void> cancel() async {
    await _activeSession?.cancel();
    _activeSession = null;
  }

  /// Stitch [frames] (ordered list of JPEG files at equal [frameInterval] second
  /// intervals) into an output MP4.
  ///
  /// [originalDurationSec] is used to calculate how many times each frame
  /// should be held to reconstruct the original video duration.
  ///
  /// [outputPath] — where the resulting MP4 is written.
  ///
  /// Returns the output [File] on success, null on failure or cancellation.
  Future<File?> stitch({
    required List<StitchFrame> frames,
    required int frameIntervalSec,
    required int originalDurationSec,
    required String outputPath,
  }) async {
    if (frames.isEmpty) return null;

    try {
      final tmpDir = await getTemporaryDirectory();
      final listFile = File('${tmpDir.path}/tariqmap_stitch_list.txt');

      // Build ffmpeg concat list
      // Each entry: "duration <D>\nfile '<path>'\n"
      // We hold each frame for frameIntervalSec seconds.
      final buf = StringBuffer();
      for (var i = 0; i < frames.length; i++) {
        final f = frames[i];
        // The last frame gets any remaining duration
        final dur = (i == frames.length - 1)
            ? (originalDurationSec - i * frameIntervalSec).clamp(1, frameIntervalSec)
            : frameIntervalSec;
        buf.write("file '${f.path.replaceAll("'", "\\'")}'\n");
        buf.write('duration $dur\n');
      }
      // ffmpeg needs a final file line (concat protocol quirk)
      buf.write("file '${frames.last.path.replaceAll("'", "\\'")}'\n");
      listFile.writeAsStringSync(buf.toString());

      // FFmpeg command:
      //  -f concat          : use concat demuxer
      //  -safe 0            : allow absolute paths
      //  -i list.txt        : input concat list
      //  -vf scale=...      : ensure even dimensions (H.264 requirement)
      //  -c:v libx264       : H.264 encode
      //  -crf 23            : quality (18=lossless, 28=low quality; 23 is good default)
      //  -preset fast       : encode speed/quality tradeoff
      //  -pix_fmt yuv420p   : maximum compatibility (required for QuickTime/iOS)
      //  -movflags +faststart: streaming-friendly (moov atom at front)
      //  -y                 : overwrite output if exists
      final cmd = [
        '-f', 'concat',
        '-safe', '0',
        '-i', listFile.path,
        '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        '-c:v', 'libx264',
        '-crf', '23',
        '-preset', 'fast',
        '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart',
        '-y',
        outputPath,
      ].join(' ');

      debugPrint('[VideoStitcher] Running: ffmpeg $cmd');

      _activeSession = await FFmpegKit.execute(cmd);
      final rc = await _activeSession!.getReturnCode();

      if (ReturnCode.isSuccess(rc)) {
        final outFile = File(outputPath);
        if (outFile.existsSync() && outFile.lengthSync() > 0) {
          debugPrint('[VideoStitcher] Done: $outputPath (${outFile.lengthSync() ~/ 1024} KB)');
          return outFile;
        }
      }

      // Log ffmpeg output on failure
      final logs = await _activeSession!.getAllLogsAsString();
      debugPrint('[VideoStitcher] FFmpeg failed (rc=$rc):\n$logs');
      return null;
    } catch (e) {
      debugPrint('[VideoStitcher] stitch() error: $e');
      return null;
    }
  }
}

/// Public data class — passed to [VideoStitcher.stitch].
class StitchFrame {
  const StitchFrame({required this.path, required this.hasDetections});
  final String path;
  final bool   hasDetections;
}

/// Public builder — creates a stitch-ready list from raw paths.
List<StitchFrame> buildStitchFrames(Map<int, String> timestampToPath) {
  final sorted = timestampToPath.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return sorted.map((e) => StitchFrame(
    path: e.value,
    hasDetections: true,
  )).toList();
}
