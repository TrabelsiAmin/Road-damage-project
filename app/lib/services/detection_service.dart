import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/observation.dart';
import 'model_manager.dart';

// ---------------------------------------------------------------------------
// Abstract runner interface
// ---------------------------------------------------------------------------

abstract class DetectionAgentRunner {
  String get agentName;
  bool   get isReady;
  bool   get isMock;
  Future<AgentResult> detect(File image);
  void dispose();
}

// ---------------------------------------------------------------------------
// Mock runner — visible, labeled, deterministic
// ---------------------------------------------------------------------------

/// Deterministic mock runner.
///
/// Must ONLY be instantiated in debug/demo mode.  The [isMock] flag is
/// always true, which causes the UI to show "DEMO MOCK INFERENCE" banners.
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
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (kDebugMode) debugPrint('[MOCK:$agentName] detect() on ${image.path}');
    return AgentResult(
      agent: agentName,
      detections: _mockBoxes.map((m) => Detection(
        agent: agentName,
        classCode: m.classCode,
        confidence: m.confidence,
        box: m.box,
      )).toList(),
      isMock: true,
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

const _agentDefs = <_AgentDef>[
  _AgentDef('road_damage', ['D00', 'D10', 'D20', 'D40']),
];

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
  /// per-agent if the file is unavailable.
  static Future<DetectionService> create() async {
    if (kIsWeb) {
      return DetectionService._(runners: _buildMockRunners());
    }

    final runners = <DetectionAgentRunner>[];

    for (final def in _agentDefs) {
      final path = await ModelManager.instance.localModelPath(def.name);
      if (path != null) {
        try {
          final runner = await _createTFLiteRunner(def.name, path, def.classes);
          runners.add(runner);
          debugPrint('[DetectionService] TFLite loaded: ${def.name}');
          continue;
        } catch (e) {
          debugPrint('[DetectionService] TFLite failed for ${def.name}: $e');
        }
      }
      debugPrint('[DetectionService] Using mock for ${def.name}');
      runners.add(_mockForAgent(def.name, def.classes));
    }

    return DetectionService._(runners: runners);
  }

  // ── Detection ──────────────────────────────────────────────────────────────

  /// Runs all three agents in parallel. If one agent throws, its result is
  /// returned as an empty AgentResult with an error string — other agents
  /// continue unaffected.
  Future<List<AgentResult>> detectAll(File image) async {
    return Future.wait(_runners.map((runner) async {
      try {
        return await runner.detect(image);
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

// ---------------------------------------------------------------------------
// TFLite runner factory (lazily imported to keep web build clean)
// ---------------------------------------------------------------------------

Future<DetectionAgentRunner> _createTFLiteRunner(
    String name, String path, List<String> classes) async {
  // Throws UnsupportedError on web — guarded by kIsWeb above.
  return _tfliteRunnerFactory(name, path, classes);
}

Future<DetectionAgentRunner> _tfliteRunnerFactory(
    String name, String path, List<String> classes) async {
  // On native this is replaced by the conditional import in tflite_agent_runner.dart.
  // The function is never called on web (kIsWeb guard above), so this stub is safe.
  throw UnsupportedError('TFLite not available on this platform');
}
