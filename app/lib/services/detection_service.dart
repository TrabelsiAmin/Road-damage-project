import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../inference/inference_config.dart';
import '../models/observation.dart';
import 'model_manager.dart';
import 'tflite_factory_stub.dart'
    if (dart.library.io) 'tflite_factory_io.dart' as tflite_factory;

// ---------------------------------------------------------------------------
// Abstract runner interface
// ---------------------------------------------------------------------------

abstract class DetectionAgentRunner {
  String get agentName;
  bool get isReady;
  bool get isMock;
  Future<AgentResult> detect(File image);
  Future<AgentResult> detectBytes(Uint8List bytes);
  void dispose();
}

// ---------------------------------------------------------------------------
// Mock runner — visible, labeled, deterministic
// ---------------------------------------------------------------------------

/// Deterministic mock runner.
///
/// Must ONLY be instantiated in debug/demo mode.  The [isMock] flag is
/// always true, which causes the UI to show "DEMO MOCK INFERENCE" banners.
/// Video and live-camera pipelines refuse this runner unless [allowMock]
/// is explicitly set.
class MockAgentRunner implements DetectionAgentRunner {
  MockAgentRunner(this.agentName, this._mockBoxes);

  @override
  final String agentName;

  @override
  bool get isReady => true;

  @override
  bool get isMock => true;

  final List<_MockDetection> _mockBoxes;

  @override
  void dispose() {}

  @override
  Future<AgentResult> detect(File image) async {
    return detectBytes(Uint8List(0));
  }

  @override
  Future<AgentResult> detectBytes(Uint8List bytes) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (kDebugMode) debugPrint('[MOCK:$agentName] detect()');
    return AgentResult(
      agent: agentName,
      detections: _mockBoxes
          .map((m) => Detection(
                agent: agentName,
                classCode: m.classCode,
                confidence: m.confidence,
                box: m.box,
              ))
          .toList(),
      isMock: true,
      latencyMs: 40,
    );
  }
}

class _MockDetection {
  const _MockDetection(this.classCode, this.confidence, this.box);
  final String classCode;
  final double confidence;
  final BoundingBox box;
}

// ---------------------------------------------------------------------------
// Agent definition
// ---------------------------------------------------------------------------

class _AgentDef {
  const _AgentDef(this.name, this.classes);
  final String name;
  final List<String> classes;
}

final _agentDefs = TariqMapConstants.agentClasses.entries
    .map((e) => _AgentDef(e.key, e.value))
    .toList();

// ---------------------------------------------------------------------------
// Detection service
// ---------------------------------------------------------------------------

class DetectionService {
  DetectionService._({
    required List<DetectionAgentRunner> runners,
  }) : _runners = runners;

  final List<DetectionAgentRunner> _runners;

  /// True when ALL runners are mocks (no real TFLite models loaded).
  bool get usingMock => _runners.every((r) => r.isMock);

  /// True when at least one agent is mock but not all (partial degradation).
  bool get partialMock =>
      _runners.any((r) => r.isMock) && !_runners.every((r) => r.isMock);

  List<DetectionAgentRunner> get runners => List.unmodifiable(_runners);

  // ── Factory ────────────────────────────────────────────────────────────────

  /// Async factory — should always be called instead of the default constructor.
  ///
  /// On web: uses mock.
  /// On Android/iOS: attempts to load bundled TFLite models; falls back to mock
  /// per-agent if the file is unavailable. The UI must surface that fallback.
  static Future<DetectionService> create() async {
    await InferenceConfig.ensureLoaded();
    if (kIsWeb) {
      return DetectionService._(runners: _buildMockRunners());
    }

    final runners = <DetectionAgentRunner>[];

    for (final def in _agentDefs) {
      final path = await ModelManager.instance.localModelPath(def.name);
      if (path != null) {
        try {
          final runner = await tflite_factory.createTFLiteRunner(
            def.name,
            path,
            def.classes,
          );
          runners.add(runner);
          debugPrint('[DetectionService] TFLite loaded: ${def.name}');
          continue;
        } catch (e) {
          debugPrint('[DetectionService] TFLite failed for ${def.name}: $e');
        }
      }
      debugPrint(
        '[DetectionService] Model asset pending for ${def.name} — mock fallback',
      );
      runners.add(_mockForAgent(def.name, def.classes));
    }

    return DetectionService._(runners: runners);
  }

  // ── Detection ──────────────────────────────────────────────────────────────

  /// Runs all agents in parallel. If one agent throws, its result is returned
  /// as an empty AgentResult with an error string — other agents continue.
  ///
  /// When [allowMock] is false, mock runners return an empty result with
  /// `error: 'Model asset pending'` instead of invented boxes. Video and
  /// live-camera pipelines MUST pass `allowMock: false`.
  Future<List<AgentResult>> detectAll(
    File image, {
    bool allowMock = true,
  }) async {
    final bytes = await image.readAsBytes();
    return detectAllBytes(bytes, allowMock: allowMock);
  }

  Future<List<AgentResult>> detectAllBytes(
    Uint8List bytes, {
    bool allowMock = true,
  }) async {
    return Future.wait(_runners.map((runner) async {
      try {
        if (!allowMock && runner.isMock) {
          return AgentResult(
            agent: runner.agentName,
            detections: const [],
            error: 'Model asset pending — real TFLite weights not installed',
            isMock: true,
          );
        }
        return await runner.detectBytes(bytes);
      } catch (error) {
        debugPrint('[DetectionService] Agent ${runner.agentName} failed: $error');
        return AgentResult(
          agent: runner.agentName,
          detections: const [],
          error: error.toString(),
          isMock: runner.isMock,
        );
      }
    }));
  }

  void dispose() {
    for (final r in _runners) {
      r.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// Mock builders
// ---------------------------------------------------------------------------

List<DetectionAgentRunner> _buildMockRunners() => [
      MockAgentRunner('cracks', const [
        _MockDetection('D00', 0.91, BoundingBox(x: 0.05, y: 0.40, width: 0.55, height: 0.12)),
        _MockDetection('D10', 0.76, BoundingBox(x: 0.62, y: 0.55, width: 0.30, height: 0.10)),
      ]),
      MockAgentRunner('pavement', const [
        _MockDetection('D40', 0.88, BoundingBox(x: 0.20, y: 0.60, width: 0.25, height: 0.20)),
        _MockDetection('D20', 0.72, BoundingBox(x: 0.55, y: 0.30, width: 0.38, height: 0.28)),
      ]),
      MockAgentRunner('surface', const [
        _MockDetection('D60', 0.65, BoundingBox(x: 0.10, y: 0.10, width: 0.80, height: 0.15)),
      ]),
    ];

DetectionAgentRunner _mockForAgent(String name, List<String> classes) =>
    _buildMockRunners().firstWhere(
      (r) => r.agentName == name,
      orElse: () => MockAgentRunner(name, [
        _MockDetection(
          classes.first,
          0.75,
          const BoundingBox(x: 0.2, y: 0.3, width: 0.4, height: 0.3),
        ),
      ]),
    );
