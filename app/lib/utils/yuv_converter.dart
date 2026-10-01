import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Persistent conversion isolate
//
// One long-lived isolate does every YUV -> tensor conversion, so there is no
// isolate spawn per frame. Camera planes go in and the finished tensor comes
// back as TransferableTypedData, which is moved between isolates instead of
// being copied again.
// ---------------------------------------------------------------------------

class YuvConverter {
  YuvConverter._();
  static final YuvConverter instance = YuvConverter._();

  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  Future<void>? _starting;
  final Map<int, Completer<Float32List>> _pending = {};
  int _nextId = 0;

  Future<void> _ensureStarted() {
    if (_toWorker != null) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final recv = ReceivePort();
    _fromWorker = recv;
    final ready = Completer<SendPort>();

    recv.listen((dynamic msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      if (msg is List && msg.length == 2) {
        final id = msg[0] as int;
        final payload = msg[1];
        final c = _pending.remove(id);
        if (c == null) return;
        if (payload is TransferableTypedData) {
          c.complete(payload.materialize().asFloat32List());
        } else {
          c.completeError(StateError('YUV conversion failed: $payload'));
        }
      }
    });

    _isolate = await Isolate.spawn(_yuvWorkerMain, recv.sendPort);
    _toWorker = await ready.future;
  }

  /// Converts a YUV420 [frame] to a [Float32List] tensor
  /// [targetSize*targetSize*3], normalised [0..1], RGB order.
  Future<Float32List> convert(CameraImage frame, int targetSize) async {
    await _ensureStarted();
    final id = _nextId++;
    final c = Completer<Float32List>();
    _pending[id] = c;

    _toWorker!.send(<dynamic>[
      id,
      TransferableTypedData.fromList([frame.planes[0].bytes]),
      TransferableTypedData.fromList([frame.planes[1].bytes]),
      TransferableTypedData.fromList([frame.planes[2].bytes]),
      frame.width,
      frame.height,
      frame.planes[0].bytesPerRow,
      frame.planes[1].bytesPerRow,
      frame.planes[1].bytesPerPixel ?? 1,
      targetSize,
    ]);
    return c.future;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _fromWorker?.close();
    _isolate = null;
    _toWorker = null;
    _fromWorker = null;
    _starting = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('Converter disposed'));
    }
    _pending.clear();
  }
}

/// Entry point of the persistent worker isolate.
void _yuvWorkerMain(SendPort initPort) {
  final port = ReceivePort();
  initPort.send(port.sendPort);
  final reply = initPort;

  port.listen((dynamic msg) {
    final m = msg as List<dynamic>;
    final id = m[0] as int;
    try {
      final p = _YuvConvertParams(
        yBytes: (m[1] as TransferableTypedData).materialize().asUint8List(),
        uBytes: (m[2] as TransferableTypedData).materialize().asUint8List(),
        vBytes: (m[3] as TransferableTypedData).materialize().asUint8List(),
        width: m[4] as int,
        height: m[5] as int,
        yRowStride: m[6] as int,
        uvRowStride: m[7] as int,
        uvPixelStride: m[8] as int,
        targetSize: m[9] as int,
      );
      final tensor = _yuvToTensorIsolate(p);
      reply.send(<dynamic>[id, TransferableTypedData.fromList([tensor])]);
    } catch (e) {
      reply.send(<dynamic>[id, e.toString()]);
    }
  });
}

/// Same signature as before, so callers do not change.
Future<Float32List> convertYUVToTensorInBackground(
        CameraImage frame, int targetSize) =>
    YuvConverter.instance.convert(frame, targetSize);

// ---------------------------------------------------------------------------
// Legacy JPEG/RGB path (unchanged)
// ---------------------------------------------------------------------------

/// All data needed to run YUV→tensor conversion off the main thread.
class _YuvConvertParams {
  const _YuvConvertParams({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.targetSize,
  });

  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final int targetSize;
}

Future<Uint8List> convertYUVToJpegInBackground(CameraImage frame) {
  final params = _YuvConvertParams(
    yBytes: frame.planes[0].bytes,
    uBytes: frame.planes[1].bytes,
    vBytes: frame.planes[2].bytes,
    width: frame.width,
    height: frame.height,
    yRowStride: frame.planes[0].bytesPerRow,
    uvRowStride: frame.planes[1].bytesPerRow,
    uvPixelStride: frame.planes[1].bytesPerPixel ?? 1,
    targetSize: 640,
  );
  return compute(_yuvToJpegIsolate, params);
}

// ── Workers ─────────────────────────────────────────────────────────────────

Uint8List _yuvToJpegIsolate(_YuvConvertParams p) {
  final ts = p.targetSize;
  final rgb = Uint8List(ts * ts * 3);
  int idx = 0;

  final xScale = p.width / ts;
  final yScale = p.height / ts;

  for (var dy = 0; dy < ts; dy++) {
    final srcY = (dy * yScale).toInt().clamp(0, p.height - 1);
    final uvRow = (srcY >> 1) * p.uvRowStride;
    final yRow = srcY * p.yRowStride;

    for (var dx = 0; dx < ts; dx++) {
      final srcX = (dx * xScale).toInt().clamp(0, p.width - 1);
      final uvIdx = uvRow + (srcX >> 1) * p.uvPixelStride;

      final yv = p.yBytes[yRow + srcX];
      final u = p.uBytes[uvIdx];
      final v = p.vBytes[uvIdx];

      final r = (yv + 1.402 * (v - 128)).clamp(0, 255).toInt();
      final g = (yv - 0.344136 * (u - 128) - 0.714136 * (v - 128))
          .clamp(0, 255)
          .toInt();
      final b = (yv + 1.772 * (u - 128)).clamp(0, 255).toInt();

      rgb[idx++] = r;
      rgb[idx++] = g;
      rgb[idx++] = b;
    }
  }

  return _encodeJpeg(rgb, ts, ts, quality: 70);
}

/// YUV420 → Float32List tensor normalised [0..1]. Same maths as before.
Float32List _yuvToTensorIsolate(_YuvConvertParams p) {
  final ts = p.targetSize;
  final out = Float32List(ts * ts * 3);
  int idx = 0;

  final xScale = p.width / ts;
  final yScale = p.height / ts;

  for (var dy = 0; dy < ts; dy++) {
    final srcY = (dy * yScale).toInt().clamp(0, p.height - 1);
    final uvRow = (srcY >> 1) * p.uvRowStride;
    final yRow = srcY * p.yRowStride;

    for (var dx = 0; dx < ts; dx++) {
      final srcX = (dx * xScale).toInt().clamp(0, p.width - 1);
      final uvIdx = uvRow + (srcX >> 1) * p.uvPixelStride;

      final yv = p.yBytes[yRow + srcX];
      final u = p.uBytes[uvIdx];
      final v = p.vBytes[uvIdx];

      final r = (yv + 1.402 * (v - 128)).clamp(0.0, 255.0) / 255.0;
      final g = (yv - 0.344136 * (u - 128) - 0.714136 * (v - 128))
              .clamp(0.0, 255.0) /
          255.0;
      final b = (yv + 1.772 * (u - 128)).clamp(0.0, 255.0) / 255.0;

      out[idx++] = r;
      out[idx++] = g;
      out[idx++] = b;
    }
  }

  return out;
}

Uint8List _encodeJpeg(Uint8List rgb, int w, int h, {int quality = 70}) {
  try {
    return _imagePackageEncode(rgb, w, h, quality);
  } catch (_) {
    return rgb;
  }
}

/// Flat RGB with a 12-byte header: "RGB\0", width (4 bytes BE), height (4 bytes BE).
Uint8List _imagePackageEncode(Uint8List rgb, int w, int h, int quality) {
  final out = Uint8List(12 + rgb.length);
  out[0] = 0x52;
  out[1] = 0x47;
  out[2] = 0x42;
  out[3] = 0x00;
  out[4] = (w >> 24) & 0xFF;
  out[5] = (w >> 16) & 0xFF;
  out[6] = (w >> 8) & 0xFF;
  out[7] = w & 0xFF;
  out[8] = (h >> 24) & 0xFF;
  out[9] = (h >> 16) & 0xFF;
  out[10] = (h >> 8) & 0xFF;
  out[11] = h & 0xFF;
  out.setRange(12, out.length, rgb);
  return out;
}