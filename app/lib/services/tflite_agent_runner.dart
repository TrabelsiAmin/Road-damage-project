import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../inference/nms.dart';
import '../models/observation.dart';
import 'detection_service.dart';

// ---------------------------------------------------------------------------
// Class index → RDD damage code mapping
// RoadDamageDetection uses the four CRDDC2022 classes below.
// ---------------------------------------------------------------------------

const _classNames = <int, String>{
  0: 'D00', // Longitudinal crack
  1: 'D10', // Transverse crack
  2: 'D20', // Alligator cracking
  3: 'D40', // Pothole
};

// ---------------------------------------------------------------------------
// Per-class confidence thresholds
//
// Kept in sync with training/config/augmentation.yaml → class_confidence_thresholds.
// ---------------------------------------------------------------------------

const _classThresholds = <String, double>{
  'D00': 0.35,  // Longitudinal crack
  'D10': 0.35,  // Transverse crack
  'D20': 0.30,
  'D40': 0.40,
};

/// Returns the confidence threshold for [classCode].
/// Falls back to 0.35 for unknown codes.
double _thresholdFor(String classCode) =>
    _classThresholds[classCode] ?? 0.35;

// ---------------------------------------------------------------------------
// TFLite agent runner
// ---------------------------------------------------------------------------

/// On-device inference runner backed by a YOLOv8n/s/m TFLite model.
///
/// Expected model signature (Ultralytics YOLOv8 export):
///   Input:  [1, inputSize, inputSize, 3]  float32  — RGB normalised [0..1]
///   Output: [1, 4+numClasses, 8400]       float32  — (cx, cy, w, h, cls…)
///
/// The interpreter runs inside an [IsolateInterpreter] so inference never
/// blocks the UI thread. All runs are serialized (queued, never dropped), so
/// a capture can never get an empty result because a live frame was running.
class TFLiteAgentRunner implements DetectionAgentRunner {
  TFLiteAgentRunner({
    required this.agentName,
    required this.agentClasses,
    required String modelPath,
    this.iouThreshold = 0.45,
    this.inputSize    = 640,
  }) {
    _tryLoad(modelPath);
  }

  @override
  final String agentName;
  final List<String> agentClasses;

  /// Per-class IoU threshold for NMS.
  final double iouThreshold;

  /// Model input width and height (must match the exported TFLite).
  final int inputSize;

  Interpreter? _interpreter;
  IsolateInterpreter? _iso;
  bool _failed = false;

  // Output buffer allocated once and reused (runs are serialized).
  List<List<List<double>>>? _output;
  int _numAnchors = 0;

  // Serializes inference calls: later calls wait, none are dropped.
  Future<void> _lock = Future<void>.value();

  @override
  bool get isReady => _interpreter != null;
  bool get failed  => _failed;

  @override
  bool get isMock => false;

  void _tryLoad(String modelPath) {
    // Use up to 4 threads — capped so we don't starve the UI thread.
    final numThreads = (Platform.numberOfProcessors - 1).clamp(2, 4);

    // 1. Android: try the GPU delegate first, fall back to CPU if it fails.
    if (Platform.isAndroid) {
      try {
        final options = InterpreterOptions()
          ..threads = numThreads
          ..addDelegate(GpuDelegateV2());
        _interpreter = Interpreter.fromFile(File(modelPath), options: options);
        debugPrint('[TFLite:$agentName] Loaded with GPU delegate: $modelPath');
      } catch (e) {
        debugPrint('[TFLite:$agentName] GPU delegate failed, using CPU: $e');
        _interpreter = null;
      }
    }

    // 2. CPU path.
    if (_interpreter == null) {
      try {
        final options = InterpreterOptions()..threads = numThreads;
        _interpreter = Interpreter.fromFile(File(modelPath), options: options);
        debugPrint('[TFLite:$agentName] Loaded on CPU: $modelPath (threads=$numThreads)');
      } catch (e) {
        debugPrint('[TFLite:$agentName] Load failed: $e');
        _failed = true;
        return;
      }
    }

    // 3. Allocate the reusable output buffer once.
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final numClasses = _classNames.length;
    if (outputShape.length != 3 ||
        outputShape[0] != 1 ||
        outputShape[1] != 4 + numClasses) {
      debugPrint('[TFLite:$agentName] Unexpected output shape: $outputShape');
      _failed = true;
      return;
    }
    _numAnchors = outputShape[2];
    _output = List.generate(
      1,
      (_) => List.generate(
        4 + numClasses,
        (_) => List<double>.filled(_numAnchors, 0.0),
      ),
    );

    // 4. Background isolate that runs the interpreter.
    IsolateInterpreter.create(address: _interpreter!.address).then((i) {
      _iso = i;
      debugPrint('[TFLite:$agentName] IsolateInterpreter ready');
    }).catchError((Object e) {
      debugPrint('[TFLite:$agentName] IsolateInterpreter failed: $e');
    });
  }

  @override
  void dispose() {
    _iso?.close();
    _interpreter?.close();
  }

  // ── Inference ──────────────────────────────────────────────────────────────

  @override
  Future<AgentResult> detect(File imageFile) async {
    if (_failed || _interpreter == null) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: 'Model not loaded',
      );
    }
    try {
      final bytes = await imageFile.readAsBytes();
      return await _runInferenceOnBytes(bytes);
    } catch (e) {
      return AgentResult(agent: agentName, detections: const [], error: e.toString());
    }
  }

  /// Accepts raw JPEG/PNG bytes directly.
  Future<AgentResult> detectFromBytes(Uint8List bytes) async {
    if (_failed || _interpreter == null) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: 'Model not loaded',
      );
    }
    try {
      return await _runInferenceOnBytes(bytes);
    } catch (e) {
      return AgentResult(agent: agentName, detections: const [], error: e.toString());
    }
  }

  /// Fast path for live camera: accepts a pre-built Float32List tensor
  /// [inputSize*inputSize*3] that was already prepared off-thread.
  Future<AgentResult> detectFromTensor(Float32List inputTensor) async {
    if (_failed || _interpreter == null) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: 'Model not loaded',
      );
    }
    try {
      return await _runInferenceOnTensor(inputTensor);
    } catch (e) {
      return AgentResult(agent: agentName, detections: const [], error: e.toString());
    }
  }

  Future<AgentResult> _runInferenceOnBytes(Uint8List rawBytes) async {
    // Decode + resize + tensor build in a background isolate (same maths as
    // before, just off the UI thread).
    final tensor = await compute(_bytesToTensor, _BytesArgs(rawBytes, inputSize));
    if (tensor == null) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: 'Cannot decode image bytes',
      );
    }
    return _runInferenceOnTensor(tensor);
  }

  /// Runs the interpreter on a pre-built Float32List — NO image decode needed.
  /// Calls are queued so the shared output buffer is never used concurrently.
  Future<AgentResult> _runInferenceOnTensor(Float32List inputTensor) {
    final run = _lock.then((_) async {
      final output = _output!;
      final inputs = [inputTensor.reshape([1, inputSize, inputSize, 3])];

      if (_iso != null) {
        await _iso!.runForMultipleInputs(inputs, {0: output});
      } else {
        // Isolate not ready yet: fall back to a direct call.
        _interpreter!.runForMultipleInputs(inputs, {0: output});
      }

      return _decodeOutput(output, _classNames.length, _numAnchors);
    });
    // Keep the chain alive even if a run throws.
    _lock = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Shared output decoder used by both inference paths.
  AgentResult _decodeOutput(
      List<List<List<double>>> output, int numClasses, int numAnchors) {
    final rawDetections = <Detection>[];
    final o = output[0];

    for (var anchor = 0; anchor < numAnchors; anchor++) {
      double bestScore = 0;
      int    bestClass = -1;

      for (var c = 0; c < numClasses; c++) {
        final score = o[4 + c][anchor];
        if (score > bestScore) { bestScore = score; bestClass = c; }
      }

      if (bestClass == -1) continue;
      final className = _classNames[bestClass];
      if (className == null) continue;
      if (bestScore < _thresholdFor(className)) continue;
      if (!agentClasses.contains(className)) continue;

      // NOTE: assumes normalised [0..1] coordinates. If your export outputs
      // pixels (0..inputSize), divide these four values by inputSize.
      final cx = o[0][anchor].clamp(0.0, 1.0);
      final cy = o[1][anchor].clamp(0.0, 1.0);
      final bw = o[2][anchor].clamp(0.0, 1.0);
      final bh = o[3][anchor].clamp(0.0, 1.0);

      rawDetections.add(Detection(
        agent: agentName,
        classCode: className,
        confidence: bestScore,
        box: BoundingBox(
          x: (cx - bw / 2).clamp(0.0, 1.0),
          y: (cy - bh / 2).clamp(0.0, 1.0),
          width:  bw,
          height: bh,
        ),
      ));
    }
    return AgentResult(
      agent: agentName,
      detections: applyClassAwareNms(rawDetections, iouThreshold: iouThreshold),
      isMock: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Background isolate helper: encoded image bytes -> flat float32 tensor
// ---------------------------------------------------------------------------

class _BytesArgs {
  _BytesArgs(this.bytes, this.size);
  final Uint8List bytes;
  final int size;
}

Float32List? _bytesToTensor(_BytesArgs a) {
  final decoded = img.decodeImage(a.bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(decoded, width: a.size, height: a.size);

  final out = Float32List(a.size * a.size * 3);
  var idx = 0;
  for (var y = 0; y < a.size; y++) {
    for (var x = 0; x < a.size; x++) {
      final p = resized.getPixel(x, y);
      out[idx++] = p.r / 255.0;
      out[idx++] = p.g / 255.0;
      out[idx++] = p.b / 255.0;
    }
  }
  return out;
}