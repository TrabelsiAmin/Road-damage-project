import 'dart:io';
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
      final options = InterpreterOptions()..threads = 2;
      _interpreter = Interpreter.fromFile(File(modelPath), options: options);
      debugPrint('[TFLite:$agentName] Loaded: $modelPath');
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
      return await _runInference(imageFile);
    } catch (e) {
      return AgentResult(agent: agentName, detections: const [], error: e.toString());
    }
  }

  Future<AgentResult> _runInference(File imageFile) async {
    final interpreter = _interpreter!;

    // 1. Decode and resize to model input dimensions.
    final rawBytes = await imageFile.readAsBytes();
    final decoded   = img.decodeImage(rawBytes);
    if (decoded == null) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: 'Cannot decode image: ${imageFile.path}',
      );
    }
    final resized = img.copyResize(decoded, width: inputSize, height: inputSize);

    // 2. Build [1, H, W, 3] float32 input tensor (RGB, [0..1]).
    final input = [
      List.generate(inputSize, (y) =>
        List.generate(inputSize, (x) => [
          resized.getPixel(x, y).rNormalized,
          resized.getPixel(x, y).gNormalized,
          resized.getPixel(x, y).bNormalized,
        ]))
    ];

    // 3. Allocate output buffer from the exported tensor shape.
    final outputShape = interpreter.getOutputTensor(0).shape;
    if (outputShape.length != 3 || outputShape[0] != 1) {
      throw StateError('Unexpected model output shape: $outputShape');
    }
    final numClasses = _classNames.length;
    final numAnchors = outputShape[2];
    if (outputShape[1] != 4 + numClasses) {
      throw StateError('Expected ${4 + numClasses} output channels, got $outputShape');
    }
    final output = [
      List.generate(4 + numClasses, (_) => List.filled(numAnchors, 0.0))
    ];

    // 4. Run interpreter.
    interpreter.run(input, output);

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

      // Filter by this class's specific threshold (not a single global cutoff)
      if (bestScore < _thresholdFor(className)) continue;

      // Only include classes this agent is responsible for
      if (!agentClasses.contains(className)) continue;

      // YOLOv8 outputs cx, cy, w, h — normalised to [0..1].
      final cx = output[0][0][anchor].clamp(0.0, 1.0);
      final cy = output[0][1][anchor].clamp(0.0, 1.0);
      final bw = output[0][2][anchor].clamp(0.0, 1.0);
      final bh = output[0][3][anchor].clamp(0.0, 1.0);

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

    // 6. Class-aware NMS: suppresses duplicates within each class independently,
    //    preventing a pothole box from suppressing a nearby crack box.
    return AgentResult(
      agent: agentName,
      detections: applyClassAwareNms(rawDetections, iouThreshold: iouThreshold),
      isMock: false,
    );
  }
}
