import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// One JPEG to include in an annotated output video, with its source timestamp.
class TimedJpeg {
  const TimedJpeg({required this.file, required this.timestampMs});
  final File file;
  final int timestampMs;
}

/// Result of an FFmpeg mux attempt. [status] is OK only after ffprobe + decode.
class VideoMuxResult {
  const VideoMuxResult({
    required this.status,
    required this.decodeOk,
    this.output,
    this.ffmpegPath,
    this.codec,
    this.width,
    this.height,
    this.durationSec,
    this.sizeBytes,
    this.reason,
    this.ffprobe,
  });

  /// OK | FFMPEG_MISSING | FAILED
  final String status;
  final bool decodeOk;
  final File? output;
  final String? ffmpegPath;
  final String? codec;
  final int? width;
  final int? height;
  final double? durationSec;
  final int? sizeBytes;
  final String? reason;
  final Map<String, dynamic>? ffprobe;

  bool get ok => status == 'OK' && decodeOk && output != null;
}

/// Encodes a JPEG sequence to H.264 MP4 using the system FFmpeg CLI.
///
/// Stock Android/iOS builds do not ship FFmpeg; [isAvailable] is false there
/// and the UI must keep the contact sheet. This path is verified on Linux
/// where `ffmpeg` / `ffprobe` are installed.
class FfmpegVideoMuxer {
  FfmpegVideoMuxer({this.ffmpegPath, this.ffprobePath});

  final String? ffmpegPath;
  final String? ffprobePath;

  static const _candidates = [
    'ffmpeg',
    '/usr/bin/ffmpeg',
    '/usr/local/bin/ffmpeg',
  ];
  static const _probeCandidates = [
    'ffprobe',
    '/usr/bin/ffprobe',
    '/usr/local/bin/ffprobe',
  ];

  Future<String?> resolveFfmpeg() async {
    if (ffmpegPath != null) {
      return await _works(ffmpegPath!, const ['-version']) ? ffmpegPath : null;
    }
    for (final c in _candidates) {
      if (await _works(c, const ['-version'])) return c;
    }
    return null;
  }

  Future<String?> resolveFfprobe() async {
    if (ffprobePath != null) {
      return await _works(ffprobePath!, const ['-version']) ? ffprobePath : null;
    }
    for (final c in _probeCandidates) {
      if (await _works(c, const ['-version'])) return c;
    }
    return null;
  }

  Future<bool> isAvailable() async =>
      (await resolveFfmpeg()) != null && (await resolveFfprobe()) != null;

  /// Holds each JPEG for the gap until the next timestamp (or clip end).
  static List<double> durationsSec({
    required List<int> timestampsMs,
    required int sourceDurationMs,
    double minDuration = 0.04,
  }) {
    if (timestampsMs.isEmpty) return const [];
    final out = <double>[];
    for (var i = 0; i < timestampsMs.length; i++) {
      final t = timestampsMs[i];
      late final int next;
      if (i + 1 < timestampsMs.length) {
        next = timestampsMs[i + 1];
      } else if (sourceDurationMs > t) {
        next = sourceDurationMs;
      } else if (i > 0) {
        next = t + (t - timestampsMs[i - 1]);
      } else {
        next = t + 1000;
      }
      final d = (next - t) / 1000.0;
      out.add(d <= 0 ? minDuration : d);
    }
    return out;
  }

  Future<VideoMuxResult> mux({
    required List<TimedJpeg> frames,
    required File output,
    required int sourceDurationMs,
  }) async {
    final ffmpeg = await resolveFfmpeg();
    if (ffmpeg == null) {
      return const VideoMuxResult(
        status: 'FFMPEG_MISSING',
        decodeOk: false,
        reason: 'ffmpeg is not on PATH',
      );
    }
    if (frames.isEmpty) {
      return VideoMuxResult(
        status: 'FAILED',
        decodeOk: false,
        ffmpegPath: ffmpeg,
        reason: 'No JPEG frames to mux',
      );
    }

    final timestamps = frames.map((f) => f.timestampMs).toList();
    final durs = durationsSec(
      timestampsMs: timestamps,
      sourceDurationMs: sourceDurationMs,
    );

    await output.parent.create(recursive: true);
    final concat = File('${output.path}.concat.txt');
    final buf = StringBuffer();
    for (var i = 0; i < frames.length; i++) {
      final path = frames[i].file.absolute.path;
      if (!await frames[i].file.exists()) {
        return VideoMuxResult(
          status: 'FAILED',
          decodeOk: false,
          ffmpegPath: ffmpeg,
          reason: 'Missing frame ${frames[i].file.path}',
        );
      }
      buf.writeln("file '${_escapeConcat(path)}'");
      buf.writeln('duration ${durs[i].toStringAsFixed(4)}');
    }
    buf.writeln("file '${_escapeConcat(frames.last.file.absolute.path)}'");
    await concat.writeAsString(buf.toString());

    try {
      final mux = await Process.run(ffmpeg, [
        '-y',
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        concat.path,
        '-vf',
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-fps_mode',
        'vfr',
        '-movflags',
        '+faststart',
        output.path,
      ]);
      if (mux.exitCode != 0 || !await output.exists() || await output.length() == 0) {
        final err = (mux.stderr.toString().trim().isNotEmpty)
            ? mux.stderr.toString().trim()
            : mux.stdout.toString().trim();
        return VideoMuxResult(
          status: 'FAILED',
          decodeOk: false,
          ffmpegPath: ffmpeg,
          reason: err.isEmpty ? 'ffmpeg mux failed' : err,
        );
      }
      return verify(output, ffmpeg: ffmpeg);
    } on ProcessException catch (e) {
      return VideoMuxResult(
        status: 'FAILED',
        decodeOk: false,
        ffmpegPath: ffmpeg,
        reason: e.message,
      );
    } finally {
      try {
        if (await concat.exists()) await concat.delete();
      } catch (_) {}
    }
  }

  Future<VideoMuxResult> verify(File output, {String? ffmpeg}) async {
    final probe = await resolveFfprobe();
    final ff = ffmpeg ?? await resolveFfmpeg();
    if (probe == null) {
      return VideoMuxResult(
        status: 'FFMPEG_MISSING',
        decodeOk: false,
        ffmpegPath: ff,
        output: output,
        reason: 'ffprobe is not on PATH; cannot verify the muxed file',
      );
    }
    if (!await output.exists()) {
      return const VideoMuxResult(
        status: 'FAILED',
        decodeOk: false,
        reason: 'output file missing',
      );
    }
    final probed = await Process.run(probe, [
      '-v',
      'error',
      '-show_entries',
      'format=duration,format_name,nb_streams,size',
      '-show_entries',
      'stream=codec_name,codec_type,width,height,nb_frames,avg_frame_rate',
      '-of',
      'json',
      output.path,
    ]);
    if (probed.exitCode != 0) {
      return VideoMuxResult(
        status: 'FAILED',
        decodeOk: false,
        ffmpegPath: ff,
        output: output,
        reason: probed.stderr.toString().trim(),
      );
    }
    Map<String, dynamic> info;
    try {
      info = jsonDecode(probed.stdout.toString()) as Map<String, dynamic>;
    } catch (_) {
      return VideoMuxResult(
        status: 'FAILED',
        decodeOk: false,
        ffmpegPath: ff,
        output: output,
        reason: 'ffprobe returned non-JSON',
      );
    }
    final streams = (info['streams'] as List?) ?? const [];
    Map<String, dynamic>? video;
    for (final s in streams) {
      if (s is Map<String, dynamic> && s['codec_type'] == 'video') {
        video = s;
        break;
      }
    }
    if (video == null) {
      return VideoMuxResult(
        status: 'FAILED',
        decodeOk: false,
        ffmpegPath: ff,
        output: output,
        ffprobe: info,
        reason: 'ffprobe found no video stream',
      );
    }
    final codec = video['codec_name'] as String?;
    final allowed = {'h264', 'hevc', 'mpeg4', 'vp9', 'av1'};
    if (codec == null || !allowed.contains(codec)) {
      return VideoMuxResult(
        status: 'FAILED',
        decodeOk: false,
        ffmpegPath: ff,
        output: output,
        ffprobe: info,
        reason: 'unexpected video codec: $codec',
      );
    }

    var decodeOk = false;
    String? decodeErr;
    if (ff != null) {
      final dec = await Process.run(ff, [
        '-v',
        'error',
        '-i',
        output.path,
        '-f',
        'null',
        '-',
      ]);
      decodeErr = dec.stderr.toString().trim();
      decodeOk = dec.exitCode == 0 && decodeErr.isEmpty;
    } else {
      decodeErr = 'ffmpeg missing; skipped decode round-trip';
    }

    final durationRaw = (info['format'] as Map?)?['duration'];
    final durationSec = double.tryParse('$durationRaw');
    final size = await output.length();
    if (!decodeOk) {
      return VideoMuxResult(
        status: 'FAILED',
        decodeOk: false,
        ffmpegPath: ff,
        output: output,
        codec: codec,
        width: video['width'] as int?,
        height: video['height'] as int?,
        durationSec: durationSec,
        sizeBytes: size,
        ffprobe: info,
        reason: decodeErr ?? 'decoded with errors',
      );
    }
    if (durationSec == null || durationSec <= 0) {
      return VideoMuxResult(
        status: 'FAILED',
        decodeOk: true,
        ffmpegPath: ff,
        output: output,
        codec: codec,
        width: video['width'] as int?,
        height: video['height'] as int?,
        durationSec: durationSec,
        sizeBytes: size,
        ffprobe: info,
        reason: 'ffprobe duration is zero',
      );
    }
    return VideoMuxResult(
      status: 'OK',
      decodeOk: true,
      ffmpegPath: ff,
      output: output,
      codec: codec,
      width: video['width'] as int?,
      height: video['height'] as int?,
      durationSec: durationSec,
      sizeBytes: size,
      ffprobe: info,
    );
  }

  static String _escapeConcat(String path) => path.replaceAll("'", r"'\''");

  Future<bool> _works(String bin, List<String> args) async {
    try {
      final r = await Process.run(bin, args);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

String muxOutputName(String sourcePath, {DateTime? now}) {
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final stem = p.basenameWithoutExtension(sourcePath);
  return 'annotated_${stem}_$stamp.mp4';
}
