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
// Each class gets its own recall/precision balance:
//   - D40 (potholes) is safety-critical → higher threshold to avoid false alarms.
//   - D20/D50/D60 are visually subtle → lower threshold for better recall.
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
/// Fails gracefully: if the interpreter cannot be loaded [failed] is true and
/// [detect] returns an empty result with an error string.
///
/// Per-class confidence thresholds are applied during decoding so that
/// different damage classes can have individually tuned recall/precision.
/// Class-aware NMS is applied to avoid suppressing detections across classes.
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
  bool _failed = false;

  @override
  bool get isReady => _interpreter != null;
  bool get failed  => _failed;

  @override
  bool get isMock => false;

  void _tryLoad(String modelPath) {
    try {
      // Use up to 4 threads — capped so we don't starve the UI thread.
      final numThreads = (Platform.numberOfProcessors - 1).clamp(2, 4);
      final options = InterpreterOptions()..threads = numThreads;
      _interpreter = Interpreter.fromFile(File(modelPath), options: options);
      debugPrint('[TFLite:$agentName] Loaded: $modelPath (threads=$numThreads)');
    } catch (e) {
      debugPrint('[TFLite:$agentName] Load failed: $e');
      _failed = true;
    }
  }

  @override
  void dispose() => _interpreter?.close();

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

  /// Accepts raw JPEG/PNG bytes directly — avoids temp-file I/O for live frames.
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

  Future<AgentResult> _runInferenceOnBytes(Uint8List rawBytes) async {
    final interpreter = _interpreter!;

    // 1. Decode and resize to model input dimensions.
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: 'Cannot decode image bytes',
      );
    }
    final resized = img.copyResize(decoded, width: inputSize, height: inputSize);

    // 2. Build [1, H, W, 3] float32 input tensor using a typed flat buffer.
    //    Avoids allocating 1.2M Dart objects per frame.
    final pixels = inputSize * inputSize;
    final flat = Float32List(pixels * 3);
    var idx = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final p = resized.getPixel(x, y);
        flat[idx++] = p.rNormalized.toDouble();
        flat[idx++] = p.gNormalized.toDouble();
        flat[idx++] = p.bNormalized.toDouble();
      }
    }
    // Reshape as [1, H, W, 3] by wrapping in a List (TFLite Flutter accepts this)
    final input = flat.buffer.asFloat32List();

    // 3. Allocate output buffer.
    final outputShape = interpreter.getOutputTensor(0).shape;
    if (outputShape.length != 3 || outputShape[0] != 1) {
      throw StateError('Unexpected model output shape: $outputShape');
    }
    final numClasses = _classNames.length;
    final numAnchors = outputShape[2];
    if (outputShape[1] != 4 + numClasses) {
      throw StateError('Expected ${4 + numClasses} output channels, got $outputShape');
    }
    // Use nested lists because tflite_flutter's reshape creates disconnected copies
    final output = List.generate(
      1,
      (_) => List.generate(
        4 + numClasses,
        (_) => List.filled(numAnchors, 0.0),
      ),
    );

    // 4. Run interpreter with reshaped inputs.
    interpreter.runForMultipleInputs(
      [input.reshape([1, inputSize, inputSize, 3])],
      {0: output},
    );

    // 5. Decode detections with per-class confidence thresholds.
    final rawDetections = <Detection>[];
    for (var anchor = 0; anchor < numAnchors; anchor++) {
      double bestScore = 0;
      int    bestClass = -1;

      for (var c = 0; c < numClasses; c++) {
        final score = output[0][4 + c][anchor];
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }

      if (bestClass == -1) continue;

      final className = _classNames[bestClass];
      if (className == null) continue;

      if (bestScore < _thresholdFor(className)) continue;
      if (!agentClasses.contains(className)) continue;

      // YOLOv8 outputs cx, cy, w, h — normalised to [0..1].
      final cx = (output[0][0][anchor] as num).toDouble().clamp(0.0, 1.0);
      final cy = (output[0][1][anchor] as num).toDouble().clamp(0.0, 1.0);
      final bw = (output[0][2][anchor] as num).toDouble().clamp(0.0, 1.0);
      final bh = (output[0][3][anchor] as num).toDouble().clamp(0.0, 1.0);

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

    // 6. Class-aware NMS.
    return AgentResult(
      agent: agentName,
      detections: applyClassAwareNms(rawDetections, iouThreshold: iouThreshold),
      isMock: false,
    );
  }
}
