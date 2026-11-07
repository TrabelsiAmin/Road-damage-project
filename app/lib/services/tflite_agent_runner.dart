import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../inference/confidence_threshold.dart';
import '../inference/legacy_decoder.dart';
import '../inference/preprocessing.dart';
import '../models/observation.dart';
import 'detection_service.dart';

// ---------------------------------------------------------------------------
// Class index → Flutter contract for road_damage.tflite only.
//
// These four codes are what Android displays. They are NOT proven equal to
// the strings in test_images.py (Crack, Pothole, Rutting, Uneven-Surface).
// The TFLite file embeds "YOLOv8_Small_RDD" and does not embed a names list.
// Do not rename these labels until a labeled export or model metadata says so.
// ---------------------------------------------------------------------------

const _classNames = <int, String>{
  0: 'D00', // Longitudinal crack (Flutter contract, not independently proven)
  1: 'D10', // Transverse crack
  2: 'D20', // Alligator cracking
  3: 'D40', // Pothole
};

// ---------------------------------------------------------------------------
// Per-class confidence thresholds for this runner only.
//
// NOT the same table as training/config/augmentation.yaml
// (yaml: D20 0.28, D40 0.42; here: D20 0.30, D40 0.40).
// These stay the runtime values until Settings saves `confidence_threshold_set`.
// A saved slider replaces every class score. NMS IoU stays [iouThreshold] (0.45)
// and is not the slider.
// ---------------------------------------------------------------------------

const _classThresholds = <String, double>{
  'D00': 0.35,
  'D10': 0.35,
  'D20': 0.30,
  'D40': 0.40,
};

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
    this.inputSize = 640,
    this.d40ThresholdOverride,
    this.onlyD40 = false,
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

  /// Optional custom confidence threshold for D40 pothole class.
  final double? d40ThresholdOverride;

  /// When true, decodes and retains only D40 pothole detections.
  final bool onlyD40;

  Interpreter? _interpreter;
  bool _failed = false;
  String? _loadError;
  Duration? _lastInferenceDuration;

  @override
  bool get isReady => _interpreter != null && !_failed;
  bool get failed => _failed;
  String? get loadError => _loadError;

  @override
  bool get isMock => false;

  /// Last measured inference execution duration.
  Duration? get lastInferenceDuration => _lastInferenceDuration;

  void _tryLoad(String modelPath) {
    try {
      final file = File(modelPath);
      if (!file.existsSync()) {
        throw StateError('Model file not found: $modelPath');
      }

      // Use up to 4 threads — capped so we don't starve the UI thread.
      final numThreads = (Platform.numberOfProcessors - 1).clamp(2, 4);
      final options = InterpreterOptions()..threads = numThreads;
      final interpreter = Interpreter.fromFile(file, options: options);

      // Verify tensor shapes at load: [1, 640, 640, 3] and [1, 8, 8400]
      final inTensors = interpreter.getInputTensors();
      final outTensors = interpreter.getOutputTensors();
      if (inTensors.isEmpty || outTensors.isEmpty) {
        throw StateError('Model has no input or output tensors');
      }

      final inShape = inTensors[0].shape;
      final outShape = outTensors[0].shape;
      debugPrint('[TFLite:$agentName] Input: $inShape, Output: $outShape');

      if (inShape.length != 4 ||
          inShape[0] != 1 ||
          inShape[1] != inputSize ||
          inShape[2] != inputSize ||
          inShape[3] != 3) {
        throw StateError(
            'Expected input shape [1, $inputSize, $inputSize, 3], got $inShape');
      }

      if (!isLegacyRoadDamageOutputShape(List<int>.from(outShape))) {
        throw StateError('Expected output shape [1, 8, 8400], got $outShape');
      }

      _interpreter = interpreter;
      debugPrint(
          '[TFLite:$agentName] Loaded: $modelPath (threads=$numThreads)');
    } catch (e) {
      debugPrint('[TFLite:$agentName] Load failed: $e');
      _failed = true;
      _loadError = e.toString();
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
      return AgentResult(
          agent: agentName, detections: const [], error: e.toString());
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
      return AgentResult(
          agent: agentName, detections: const [], error: e.toString());
    }
  }

  Future<AgentResult> _runInferenceOnBytes(Uint8List rawBytes) async {
    final interpreter = _interpreter!;

    // 1. Decode, apply EXIF once, then stretch. Orientation 1 is not rewritten.
    img.Image decoded;
    try {
      decoded = decodeAndOrient(rawBytes);
    } catch (_) {
      return AgentResult(
        agent: agentName,
        detections: const [],
        error: 'Cannot decode image bytes',
      );
    }
    // Stretch, not letterbox. See [stretchToModelInput]. Do not swap in the
    // RoadSense letterbox: that model is NCHW [1, 3, 640, 640] → [1, 9, 8400].
    final resized = stretchToModelInput(decoded, inputSize: inputSize);

    // 2. Build [1, H, W, 3] float32 tensor — fast integer pixel loop.
    //    Uses getPixelLinear for speed over setPixel boxing.
    final pixels = inputSize * inputSize;
    final flat = Float32List(pixels * 3);
    var idx = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        flat[idx++] = pixel.r / 255.0;
        flat[idx++] = pixel.g / 255.0;
        flat[idx++] = pixel.b / 255.0;
      }
    }
    final input = flat;

    // 3. Allocate output buffer.
    final outputShape = interpreter.getOutputTensor(0).shape;
    if (outputShape.length != 3 || outputShape[0] != 1) {
      throw StateError('Unexpected model output shape: $outputShape');
    }
    final numClasses = _classNames.length;
    final numAnchors = outputShape[2];
    if (outputShape[1] != 4 + numClasses) {
      throw StateError(
          'Expected ${4 + numClasses} output channels, got $outputShape');
    }
    // Use nested lists because tflite_flutter's reshape creates disconnected copies
    final output = List.generate(
      1,
      (_) => List.generate(
        4 + numClasses,
        (_) => List.filled(numAnchors, 0.0),
      ),
    );

    // 4. Run interpreter with reshaped inputs and measure duration.
    final sw = Stopwatch()..start();
    interpreter.runForMultipleInputs(
      [
        input.reshape([1, inputSize, inputSize, 3])
      ],
      {0: output},
    );
    sw.stop();
    _lastInferenceDuration = sw.elapsed;
    if (kDebugMode) {
      debugPrint(
          '[TFLite:$agentName] Inference time: ${sw.elapsedMilliseconds} ms');
    }

    // 5. Shared decode logic. The slider is read here so a saved value applies
    //    on the next capture without reloading the interpreter.
    await _loadConfidenceThreshold();
    return _decodeOutput(output, numClasses, numAnchors,
        latencyMs: sw.elapsedMilliseconds);
  }

  /// Shared output decoder used by inference.
  ///
  /// [numClasses] and [numAnchors] are kept so callers still pass the shape
  /// they checked. Decoding itself reads [output] as `[1, 4+C, anchors]`.
  AgentResult _decodeOutput(
      List<dynamic> output, int numClasses, int numAnchors,
      {int? latencyMs}) {
    if (numClasses != _classNames.length) {
      throw StateError(
          'Legacy decoder is fixed at ${_classNames.length} classes, got $numClasses');
    }
    if (numAnchors != (output[0][0] as List).length) {
      throw StateError('Anchor count $numAnchors does not match output buffer');
    }
    return AgentResult(
      agent: agentName,
      detections: decodeLegacyYoloOutput(
        output: output,
        classNames: _classNames,
        agentClasses: agentClasses,
        classThresholds: _activeThresholds,
        iouThreshold: iouThreshold,
        d40ThresholdOverride: _sliderActive ? null : d40ThresholdOverride,
        onlyD40: onlyD40,
        agentName: agentName,
      ),
      isMock: false,
      latencyMs: latencyMs,
    );
  }

  Map<String, double> _activeThresholds = _classThresholds;
  bool _sliderActive = false;

  /// Reads the saved slider. A missing flag keeps the per-class defaults.
  /// Invalid stored numbers are rejected by [clampConfidenceThreshold].
  Future<void> _loadConfidenceThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final active = activeThresholds(
        classDefaults: _classThresholds,
        saved: prefs.getBool('confidence_threshold_set') ?? false,
        storedSlider: prefs.getDouble('confidence_threshold'),
      );
      _sliderActive = active.global;
      _activeThresholds = active.byClass;
    } catch (_) {
      _sliderActive = false;
      _activeThresholds = _classThresholds;
    }
  }
}
