import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tariqmap/core/constants.dart';
import 'package:tariqmap/inference/inference_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InferenceConfig.resetForTest(InferenceConfig());
  });

  test('defaults match the published contract', () {
    final cfg = InferenceConfig();
    expect(cfg.confidenceThreshold, TariqMapConstants.defaultConfidenceThreshold);
    expect(cfg.iouThreshold, TariqMapConstants.defaultIouThreshold);
    expect(cfg.classAwareNms, isTrue);
    expect(cfg.maxDetections, TariqMapConstants.defaultMaxDetections);
    expect(cfg.liveFps, TariqMapConstants.defaultLiveFps);
  });

  test('cameraFrameSkip maps 5 fps to a 30 fps preview skip of 6', () {
    InferenceConfig.resetForTest(InferenceConfig(liveFps: 5));
    expect(InferenceConfig.instance.cameraFrameSkip, 6);
  });

  test('ensureLoaded reads persisted confidence and iou', () async {
    SharedPreferences.setMockInitialValues({
      InferenceConfig.confidenceKey: 0.55,
      InferenceConfig.iouKey: 0.6,
      InferenceConfig.classAwareKey: false,
      InferenceConfig.maxDetectionsKey: 10,
      InferenceConfig.liveFpsKey: 3,
    });
    InferenceConfig.markUnloadedForTest();
    final cfg = await InferenceConfig.ensureLoaded();
    expect(cfg.confidenceThreshold, closeTo(0.55, 1e-9));
    expect(cfg.iouThreshold, closeTo(0.6, 1e-9));
    expect(cfg.classAwareNms, isFalse);
    expect(cfg.maxDetections, 10);
    expect(cfg.liveFps, 3);
  });
}
