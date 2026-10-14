import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/constants.dart';
import '../inference/preprocessing.dart';
import '../inference/roadsense_decoder.dart';
import '../models/observation.dart';
import 'detection_service.dart';

/// On-device inference runner for RoadSense YOLOv12s TFLite model.
///
/// Signature:
///   Input:  [1, 3, 640, 640] float32 NCHW  — RGB normalized [0..1] with 114 letterbox
///   Output: [1, 9, 8400]     float32       — (cx, cy, w, h, D00, D10, D20, D40, Repair)
///
/// Classes retained:
///   - D00, D10, D20 (cracks)
///   - D40 and Repair are ignored for damage observations.
///   - Repair detections are retained in [lastRepairDetections] to filter false potholes.
class RoadSenseAgentRunner implements DetectionAgentRunner {
  RoadSenseAgentRunner({
    this.agentName = 'road_damage_roadsense',
    this.agentClasses = const ['D00', 'D10', 'D20'],
    required String modelPath,
    this.iouThreshold = TariqMapConstants.defaultIouThreshold,
    this.inputSize = 640,
    this.d00Threshold = TariqMapConstants.roadSenseD00Threshold,
    this.d10Threshold = TariqMapConstants.roadSenseD10Threshold,
    this.d20Threshold = TariqMapConstants.roadSenseD20Threshold,
    this.repairThreshold = TariqMapConstants.roadSenseRepairThreshold,
  }) {
    _tryLoad(modelPath);
  }

  @override
  final String agentName;

  final List<String> agentClasses;

  final double iouThreshold;
  final int inputSize;
  final double d00Threshold;
  final double d10Threshold;
  final double d20Threshold;
  final double repairThreshold;

  Interpreter? _interpreter;
  bool _failed = false;
  String? _loadError;

  List<Detection> _lastRepairDetections = const [];
  Duration? _lastInferenceDuration;

  @override
  bool get isReady => _interpreter != null && !_failed;

  bool get failed => _failed;
  String? get loadError => _loadError;

  @override
  bool get isMock => false;

  /// Most recent Repair detections (used by hybrid pipeline to filter false potholes).
  List<Detection> get lastRepairDetections => _lastRepairDetections;

  /// Last measured inference execution duration.
  Duration? get lastInferenceDuration => _lastInferenceDuration;

  void _tryLoad(String modelPath) {
    try {
      final file = File(modelPath);
      if (!file.existsSync()) {
        throw StateError('Model file not found at: $modelPath');
      }

      final numThreads = (Platform.numberOfProcessors - 1).clamp(2, 4);
      final options = InterpreterOptions()..threads = numThreads;
      final interpreter = Interpreter.fromFile(file, options: options);

      // Verify tensor signatures at load
      final inTensors = interpreter.getInputTensors();
      final outTensors = interpreter.getOutputTensors();

      if (inTensors.isEmpty || outTensors.isEmpty) {
        throw StateError('Model has no input or output tensors');
      }

      final inShape = inTensors[0].shape;
      final outShape = outTensors[0].shape;

      debugPrint('[RoadSense] Loaded $modelPath (threads=$numThreads)');
      debugPrint('[RoadSense] Input shape: $inShape, Output shape: $outShape');

      // Validate shape: [1, 3, 640, 640] and [1, 9, 8400]
      if (inShape.length != 4 || inShape[0] != 1 || inShape[1] != 3 ||
          inShape[2] != inputSize || inShape[3] != inputSize) {
        throw StateError('Expected input shape [1, 3, $inputSize, $inputSize], got $inShape');
      }

      if (outShape.length != 3 || outShape[0] != 1 || outShape[1] != 9 || outShape[2] != 8400) {
        throw StateError('Expected output shape [1, 9, 8400], got $outShape');
      }

      _interpreter = interpreter;
    } catch (e) {
      debugPrint('[RoadSense] Load failed: $e');
      _failed = true;
      _loadError = e.toString();
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
  }

  @override
  Future<AgentResult> detect(File imageFile) async {
    if (_failed || _interpreter == null) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: _loadError ?? 'Model not loaded',
      );
    }
    try {
      final bytes = await imageFile.readAsBytes();
      return await detectFromBytes(bytes);
    } catch (e) {
      return AgentResult(agent: agentName, detections: const [], error: e.toString());
    }
  }

  /// Runs RoadSense inference on raw image bytes.
  Future<AgentResult> detectFromBytes(Uint8List rawBytes) async {
    if (_failed || _interpreter == null) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: _loadError ?? 'Model not loaded',
      );
    }

    final decoded = decodeAndOrient(rawBytes);

    // Letterbox preprocessing: resize keeping aspect ratio, pad to 640x640 with 114
    final letterbox = letterboxProcess(decoded, inputSize: inputSize);

    // Convert to NCHW [1, 3, 640, 640] Float32List
    final inputTensor = imageToNchwFloat32(letterbox.image);

    return runOnTensor(inputTensor, letterbox);
  }

  /// Runs inference on a pre-built NCHW Float32List tensor with letterbox metadata.
  AgentResult runOnTensor(Float32List inputTensor, LetterboxResult letterbox) {
    final interpreter = _interpreter!;

    // Allocate output buffer [1, 9, 8400]
    final output = List.generate(
      1,
      (_) => List.generate(9, (_) => List.filled(8400, 0.0)),
    );

    final sw = Stopwatch()..start();
    interpreter.runForMultipleInputs(
      [inputTensor.reshape([1, 3, inputSize, inputSize])],
      {0: output},
    );
    sw.stop();
    _lastInferenceDuration = sw.elapsed;

    if (kDebugMode) {
      debugPrint('[RoadSense] Inference time: ${sw.elapsedMilliseconds} ms');
    }

    final decoded = RoadSenseDecoder.decode(
      output: output,
      letterbox: letterbox,
      agentName: agentName,
      d00Threshold: d00Threshold,
      d10Threshold: d10Threshold,
      d20Threshold: d20Threshold,
      repairThreshold: repairThreshold,
      iouThreshold: iouThreshold,
    );

    _lastRepairDetections = decoded.repairDetections;

    return AgentResult(
      agent: agentName,
      detections: decoded.crackDetections,
      isMock: false,
      latencyMs: sw.elapsedMilliseconds,
    );
  }
}
