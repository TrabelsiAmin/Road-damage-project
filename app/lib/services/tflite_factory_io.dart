import 'tflite_agent_runner.dart';
import 'detection_service.dart';

/// Native (Android / iOS / desktop) factory — actually loads the interpreter.
Future<DetectionAgentRunner> createTFLiteRunner(
  String name,
  String path,
  List<String> classes,
) async {
  final runner = TFLiteAgentRunner(
    agentName: name,
    agentClasses: classes,
    modelPath: path,
  );
  if (runner.failed || !runner.isReady) {
    throw StateError('TFLite interpreter failed to load for $name at $path');
  }
  return runner;
}
