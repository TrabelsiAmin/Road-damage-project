import 'detection_service.dart';

/// Web / non-IO stub. Never called on Android/iOS because of the
/// `dart.library.io` conditional import.
Future<DetectionAgentRunner> createTFLiteRunner(
  String name,
  String path,
  List<String> classes,
) async {
  throw UnsupportedError('TFLite is not available on this platform');
}
