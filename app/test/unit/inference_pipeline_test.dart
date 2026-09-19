import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/inference/letterbox_math.dart';
import 'package:tariqmap/inference/yolo_decoder.dart';
import 'package:tariqmap/inference/yuv_converter.dart';
import 'package:tariqmap/services/video_sampling.dart';

void main() {
  group('LetterboxMeta', () {
    test('square image has zero padding', () {
      final m = LetterboxMeta.compute(origW: 640, origH: 640, inputSize: 640);
      expect(m.padX, 0);
      expect(m.padY, 0);
      expect(m.scale, 1.0);
    });

    test('landscape image pads top and bottom', () {
      final m = LetterboxMeta.compute(origW: 1280, origH: 720, inputSize: 640);
      expect(m.resizedWidth, 640);
      expect(m.padX, 0);
      expect(m.padY, greaterThan(0));
    });

    test('inverse letterbox recovers original-normalised box', () {
      final m = LetterboxMeta.compute(origW: 1000, origH: 500, inputSize: 640);
      // A box covering the full original image, expressed in letterbox 0-1.
      final nx = m.padX / m.inputSize;
      final ny = m.padY / m.inputSize;
      final nw = m.resizedWidth / m.inputSize;
      final nh = m.resizedHeight / m.inputSize;
      final (x, y, w, h) = m.toOriginalNorm(nx, ny, nw, nh);
      expect(x, closeTo(0.0, 1e-3));
      expect(y, closeTo(0.0, 1e-3));
      expect(w, closeTo(1.0, 1e-3));
      expect(h, closeTo(1.0, 1e-3));
    });

    test('pixel-space YOLO centre is detected and mapped', () {
      final m = LetterboxMeta.compute(origW: 640, origH: 640, inputSize: 640);
      final (x, y, w, h) = m.boxFromYolo(320, 320, 64, 64);
      expect(x, closeTo(0.45, 1e-3));
      expect(y, closeTo(0.45, 1e-3));
      expect(w, closeTo(0.10, 1e-3));
      expect(h, closeTo(0.10, 1e-3));
    });

    test('stretch-resize is NOT used — portrait gets side padding', () {
      final m = LetterboxMeta.compute(origW: 720, origH: 1280, inputSize: 640);
      expect(m.resizedHeight, 640);
      expect(m.padX, greaterThan(0));
      expect(m.padY, 0);
    });
  });

  group('decodeYoloOutput', () {
    test('channels-first [11, N] layout', () {
      final m = LetterboxMeta.compute(origW: 640, origH: 640, inputSize: 640);
      final output = List.generate(11, (_) => List<double>.filled(2, 0));
      output[0][0] = 0.5;
      output[1][0] = 0.5;
      output[2][0] = 0.2;
      output[3][0] = 0.2;
      output[4 + 3][0] = 0.9; // D40
      final dets = decodeYoloOutput(
        output: output,
        letterbox: m,
        numClasses: 7,
        confidenceThreshold: 0.35,
      );
      expect(dets, hasLength(1));
      expect(dets.first.classIndex, 3);
      expect(dets.first.score, closeTo(0.9, 1e-9));
    });

    test('below-threshold anchors are dropped', () {
      final m = LetterboxMeta.compute(origW: 640, origH: 640, inputSize: 640);
      final output = List.generate(11, (_) => List<double>.filled(1, 0.01));
      final dets = decodeYoloOutput(
        output: output,
        letterbox: m,
        numClasses: 7,
        confidenceThreshold: 0.35,
      );
      expect(dets, isEmpty);
    });
  });

  group('VideoSampling', () {
    test('includes t=0 and respects interval', () {
      final ts = VideoSampling.timestampsMs(
        durationMs: 20 * 1000,
        intervalMs: 5 * 1000,
        maxFrames: 40,
      );
      expect(ts, [0, 5000, 10000, 15000]);
    });

    test('caps and stretches interval on long videos', () {
      final ts = VideoSampling.timestampsMs(
        durationMs: 3600 * 1000,
        intervalMs: 1000,
        maxFrames: 10,
      );
      expect(ts.length, lessThanOrEqualTo(10));
      expect(ts.first, 0);
      expect(ts.last, lessThan(3600 * 1000));
    });

    test('empty duration yields no timestamps', () {
      expect(
        VideoSampling.timestampsMs(durationMs: 0, intervalMs: 1000),
        isEmpty,
      );
    });

    test('supported extensions include mp4 and mov', () {
      expect(VideoSampling.isSupportedPath('clip.MP4'), isTrue);
      expect(VideoSampling.isSupportedPath('clip.mov'), isTrue);
      expect(VideoSampling.isSupportedPath('notes.txt'), isFalse);
    });
  });

  group('YUV converter', () {
    test('rejects empty frames', () {
      expect(
        () => convertFrameToJpeg(
          const RawCameraFrame(
            width: 0,
            height: 0,
            format: 'yuv420',
            planes: [],
            bytesPerRow: [],
            bytesPerPixel: [],
          ),
        ),
        throwsStateError,
      );
    });

    test('jpeg format returns the plane bytes', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
      final out = convertFrameToJpeg(RawCameraFrame(
        width: 2,
        height: 2,
        format: 'jpeg',
        planes: [jpeg],
        bytesPerRow: [2],
        bytesPerPixel: [1],
      ));
      expect(out, jpeg);
    });

    test('yuv420 produces a JPEG of non-zero size', () {
      const w = 8;
      const h = 8;
      final y = Uint8List(w * h)..fillRange(0, w * h, 128);
      final u = Uint8List((w * h) ~/ 4)..fillRange(0, (w * h) ~/ 4, 128);
      final v = Uint8List((w * h) ~/ 4)..fillRange(0, (w * h) ~/ 4, 128);
      final out = convertFrameToJpeg(RawCameraFrame(
        width: w,
        height: h,
        format: 'yuv420',
        planes: [y, u, v],
        bytesPerRow: [w, w ~/ 2, w ~/ 2],
        bytesPerPixel: [1, 1, 1],
      ));
      expect(out.length, greaterThan(20));
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
    });
  });
}
