import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/inference/confidence_threshold.dart';

void main() {
  const defaults = {'D00': 0.35, 'D10': 0.35, 'D20': 0.30, 'D40': 0.40};

  test('an unsaved slider keeps the per-class defaults', () {
    final resolved = resolveClassThresholds(defaults, null);
    expect(resolved['D20'], 0.30);
    expect(resolved['D40'], 0.40);
    expect(resolved['D00'], 0.35);
  });

  test('the text names the same thresholds inference uses', () {
    final unsaved = activeThresholds(
      classDefaults: defaults,
      saved: false,
      storedSlider: 0.55,
    );
    expect(unsaved.global, isFalse);
    expect(unsaved.byClass['D40'], 0.40);
    expect(unsaved.byClass['D20'], 0.30);
    expect(describeActiveThresholds(unsaved), contains('class-specific'));
    expect(describeActiveThresholds(unsaved), contains('40%'));
    expect(describeActiveThresholds(unsaved), contains('30%'));

    final saved = activeThresholds(
      classDefaults: defaults,
      saved: true,
      storedSlider: 0.55,
    );
    expect(saved.global, isTrue);
    expect(saved.byClass.values.toSet(), {0.55});
    expect(describeActiveThresholds(saved), contains('global 55%'));
    expect(describeActiveThresholds(saved), contains('45%'));
    expect(nmsIouThreshold, 0.45);
  });

  test('a saved slider replaces every class confidence and clamps the range',
      () {
    final resolved = resolveClassThresholds(defaults, 0.55);
    expect(resolved.values.toSet(), {0.55});

    expect(clampConfidenceThreshold(2), 0.80);
    expect(clampConfidenceThreshold(-1), 0.10);
    expect(clampConfidenceThreshold(double.nan), isNull);
    final rejected = resolveClassThresholds(defaults, double.nan);
    expect(rejected['D40'], 0.40);
  });
}
