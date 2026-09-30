import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tariqmap/services/video_muxer.dart';

void main() {
  group('FfmpegVideoMuxer.durationsSec', () {
    test('uses timestamp deltas and the source tail', () {
      final d = FfmpegVideoMuxer.durationsSec(
        timestampsMs: [0, 500, 1000],
        sourceDurationMs: 1500,
      );
      expect(d, [0.5, 0.5, 0.5]);
    });

    test('empty timestamps', () {
      expect(
        FfmpegVideoMuxer.durationsSec(timestampsMs: [], sourceDurationMs: 1000),
        isEmpty,
      );
    });
  });

  group('FfmpegVideoMuxer availability', () {
    test('invalid binary is reported missing, not OK', () async {
      final muxer = FfmpegVideoMuxer(
        ffmpegPath: '/no/such/ffmpeg',
        ffprobePath: '/no/such/ffprobe',
      );
      expect(await muxer.isAvailable(), isFalse);
      final result = await muxer.mux(
        frames: const [],
        output: File('/tmp/no.mp4'),
        sourceDurationMs: 1000,
      );
      expect(result.status, 'FFMPEG_MISSING');
      expect(result.decodeOk, isFalse);
      expect(result.ok, isFalse);
    });
  });

  group('FfmpegVideoMuxer round-trip', () {
    test('muxes JPEGs to a decodable H.264 MP4 when ffmpeg exists', () async {
      final muxer = FfmpegVideoMuxer();
      if (!await muxer.isAvailable()) {
        // Stock mobile CI has no ffmpeg; the missing-binary test above still runs.
        return;
      }

      final dir = await Directory.systemTemp.createTemp('tariqmap_mux_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final frames = <TimedJpeg>[];
      for (var i = 0; i < 4; i++) {
        final im = img.Image(width: 160, height: 120, numChannels: 3);
        img.fill(im, color: img.ColorRgb8(40 + i * 40, 90, 160));
        final f = File('${dir.path}/frame_$i.jpg');
        await f.writeAsBytes(img.encodeJpg(im, quality: 80));
        frames.add(TimedJpeg(file: f, timestampMs: i * 250));
      }
      final out = File('${dir.path}/annotated.mp4');
      final result = await muxer.mux(
        frames: frames,
        output: out,
        sourceDurationMs: 1000,
      );
      expect(result.status, 'OK', reason: result.reason);
      expect(result.decodeOk, isTrue);
      expect(result.codec, 'h264');
      expect(result.width, 160);
      expect(result.height, 120);
      expect(result.durationSec, greaterThan(0.3));
      expect(await out.exists(), isTrue);
      expect(await out.length(), greaterThan(500));
    });
  });
}
