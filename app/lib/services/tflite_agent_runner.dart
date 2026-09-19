import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/constants.dart';
import '../inference/nms.dart';
import '../inference/preprocessing.dart';
import '../inference/yolo_decoder.dart';
import '../models/observation.dart';
import 'detection_service.dart';

// ---------------------------------------------------------------------------
// Class index → RDD damage code mapping
// All three agents share a single 7-class label space.
// Indexes MUST match training/config/source-class-map.json.
// ---------------------------------------------------------------------------

const classNames = <int, String>{
  0: 'D00', // Longitudinal crack
  1: 'D10', // Transverse crack
  2: 'D20', // Alligator cracking
  3: 'D40', // Pothole
  4: 'D50', // Faded pedestrian crossing
  5: 'D60', // Faded lane marking
  6: 'D90', // Rutting (absent from RDD2022 — kept for taxonomy)
};

// ---------------------------------------------------------------------------
// TFLite agent runner
// ---------------------------------------------------------------------------

/// On-device inference runner backed by a YOLOv8 TFLite model.
///
/// Pipeline:
///   image → EXIF orient → letterbox 640 → float32 RGB [0..1]
///        → interpreter → YOLO decode → inverse letterbox
///        → original-image coordinates → NMS
///
/// Expected model signature (Ultralytics YOLOv8 export):
///   Input:  [1, inputSize, inputSize, 3]  float32  NHWC RGB
///   Output: [1, 4+numClasses, anchors]    or [1, anchors, 4+numClasses]
class TFLiteAgentRunner implements DetectionAgentRunner {
  TFLiteAgentRunner({
    required this.agentName,
    required this.agentClasses,
    required String modelPath,
    this.confidenceThreshold = TariqMapConstants.defaultConfidenceThreshold,
    this.iouThreshold = TariqMapConstants.defaultIouThreshold,
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
  List<int> _inputShape = const [1, 640, 640, 3];
  List<int> _outputShape = const [1, 11, 8400];

  @override
  bool get isReady => _interpreter != null && !_failed;

  bool get failed => _failed;

  @override
  bool get isMock => false;

  void _tryLoad(String modelPath) {
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = Interpreter.fromFile(File(modelPath), options: options);
      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;
    if (_inputShape.length == 4 && _inputShape[1] == 3) {
        debugPrint(
          '[TFLite:$agentName] WARNING: input looks NCHW $_inputShape; '
          'runner feeds NHWC. Do not deploy this file.',
        );
      }
      debugPrint(
        '[TFLite:$agentName] Loaded $modelPath '
        'in=$_inputShape out=$_outputShape',
      );
    } catch (e) {
      debugPrint('[TFLite:$agentName] Load failed: $e');
      _failed = true;
    }
  }

  @override
  void dispose() => _interpreter?.close();

  @override
  Future<AgentResult> detect(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return detectBytes(bytes);
    } catch (e) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: e.toString(),
        isMock: false,
      );
    }
  }

  @override
  Future<AgentResult> detectBytes(Uint8List bytes) async {
    if (_failed || _interpreter == null) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: 'Model not loaded',
        isMock: false,
      );
    }
    final sw = Stopwatch()..start();
    try {
      final result = await _runInference(bytes);
      sw.stop();
      return AgentResult(
        agent: result.agent,
        detections: result.detections,
        error: result.error,
        isMock: false,
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: e.toString(),
        isMock: false,
        latencyMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<AgentResult> _runInference(Uint8List bytes) async {
    final interpreter = _interpreter!;
    final pre = await preprocessImageBytes(bytes, inputSize: inputSize);

    final input = pre.tensor;
    final output = _allocateOutput();
    interpreter.run(input, output);

    final squeezed = squeezeYoloOutput(output);
    final candidates = decodeYoloOutput(
      output: squeezed,
      letterbox: pre.letterbox,
      numClasses: classNames.length,
      confidenceThreshold: confidenceThreshold,
    );

    final raw = <Detection>[];
    for (final c in candidates) {
      final className = classNames[c.classIndex];
      if (className == null || !agentClasses.contains(className)) continue;
      raw.add(Detection(
        agent: agentName,
        classCode: className,
        confidence: c.score,
        box: c.box,
        timestamp: DateTime.now().toUtc(),
      ));
    }

    return AgentResult(
      agent: agentName,
      detections: applyClassAwareNms(raw, iouThreshold: iouThreshold),
      isMock: false,
    );
  }

  dynamic _allocateOutput() {
    // Allocate a nested List matching the interpreter output shape.
    List<dynamic> build(List<int> shape) {
      if (shape.length == 1) {
        return List<double>.filled(shape.first, 0.0);
      }
      return List.generate(shape.first, (_) => build(shape.sublist(1)));
    }

    return build(_outputShape);
  }
}
