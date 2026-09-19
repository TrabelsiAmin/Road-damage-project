import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../inference/nms.dart';
import '../inference/preprocessing.dart';
import '../models/observation.dart';
import 'detection_service.dart';

// ---------------------------------------------------------------------------
// Class index → RDD damage code mapping
// All three agents share a single 7-class label space.
// ---------------------------------------------------------------------------

const _classNames = <int, String>{
  0: 'D00', // Longitudinal crack
  1: 'D10', // Transverse crack
  2: 'D20', // Alligator cracking
  3: 'D40', // Pothole
  4: 'D50', // Faded pedestrian crossing
  5: 'D60', // Faded lane marking
  6: 'D90', // Rutting
};

// ---------------------------------------------------------------------------
// TFLite agent runner
// ---------------------------------------------------------------------------

/// On-device inference runner backed by a YOLOv8n TFLite model.
///
/// Expected model signature (Ultralytics YOLOv8n export):
///   Input:  [1, inputSize, inputSize, 3]  float32  — RGB normalised [0..1]
///   Output: [1, 4+numClasses, 8400]       float32  — (cx, cy, w, h, cls…)
///
/// Fails gracefully: if the interpreter cannot be loaded [failed] is true and
/// [detect] returns an empty result with an error string.
class TFLiteAgentRunner implements DetectionAgentRunner {
  TFLiteAgentRunner({
    required this.agentName,
    required this.agentClasses,
    required String modelPath,
    this.confidenceThreshold = 0.35,
    this.iouThreshold = 0.45,
    this.inputSize = 640,
  }) {
    _tryLoad(modelPath);
  }

  @override
  final String agentName;
  final List<String> agentClasses;
  final double confidenceThreshold;
  final double iouThreshold;
  final int inputSize;

  Interpreter? _interpreter;
  bool _failed = false;

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

  void dispose() => _interpreter?.close();

  // ── Inference ────────────────────────────────────────────────────────────

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
      return AgentResult(agent: agentName, detections: const [], error: 'Cannot decode image');
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

    // 3. Allocate output buffer [1, 4+numClasses, numAnchors].
    const numAnchors = 8400;
    final numClasses = _classNames.length; // 7
    final output = [
      List.generate(4 + numClasses, (_) => List.filled(numAnchors, 0.0))
    ];

    // 4. Run interpreter.
    interpreter.run(input, output);

    // 5. Decode detections from raw output.
    final rawDetections = <Detection>[];
    for (var anchor = 0; anchor < numAnchors; anchor++) {
      double bestScore = 0;
      int bestClass = -1;
      for (var c = 0; c < numClasses; c++) {
        final score = output[0][4 + c][anchor];
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestScore < confidenceThreshold) continue;
      final className = _classNames[bestClass];
      if (className == null || !agentClasses.contains(className)) continue;

      // YOLOv8 outputs cx, cy, w, h — already normalised to [0..1].
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
          width: bw,
          height: bh,
        ),
      ));
    }

    // 6. Non-maximum suppression.
    return AgentResult(
      agent: agentName,
      detections: applyNms(rawDetections, iouThreshold: iouThreshold),
      isMock: false,
    );
  }

  // ── NMS ──────────────────────────────────────────────────────────────────

}
