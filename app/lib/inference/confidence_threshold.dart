/// Settings slider contract for the legacy detector.
///
/// The slider is one confidence score applied to every class after the user
/// saves it. Until that flag is saved, the per-class defaults stay in force
/// (D00/D10 0.35, D20 0.30, D40 0.40).
///
/// NMS uses IoU, not this value. 0.45 is not read from the slider.
const double confidenceSliderMin = 0.10;
const double confidenceSliderMax = 0.80;
const double nmsIouThreshold = 0.45;

/// The class floors used until the user saves the slider.
const legacyClassThresholds = <String, double>{
  'D00': 0.35,
  'D10': 0.35,
  'D20': 0.30,
  'D40': 0.40,
};

class ActiveThresholds {
  const ActiveThresholds({required this.global, required this.byClass});

  /// True only after a saved slider replaces every class.
  final bool global;
  final Map<String, double> byClass;
}

/// The map inference uses. A moved slider that has not been saved does not
/// change this result. Invalid stored numbers fall back to the class floors.
ActiveThresholds activeThresholds({
  required Map<String, double> classDefaults,
  required bool saved,
  required double? storedSlider,
}) {
  if (!saved) {
    return ActiveThresholds(
      global: false,
      byClass: Map<String, double>.from(classDefaults),
    );
  }
  final clamped = clampConfidenceThreshold(storedSlider);
  if (clamped == null) {
    return ActiveThresholds(
      global: false,
      byClass: Map<String, double>.from(classDefaults),
    );
  }
  return ActiveThresholds(
    global: true,
    byClass: resolveClassThresholds(classDefaults, clamped),
  );
}

/// Text for the settings screen. It names the same numbers [activeThresholds] returns.
String describeActiveThresholds(ActiveThresholds active) {
  final iou = (nmsIouThreshold * 100).toStringAsFixed(0);
  String percent(double value) => '${(value * 100).toStringAsFixed(0)}%';
  if (!active.global) {
    return 'Active: class-specific. '
        'D00 ${percent(active.byClass['D00'] ?? 0)}, '
        'D10 ${percent(active.byClass['D10'] ?? 0)}, '
        'D20 ${percent(active.byClass['D20'] ?? 0)}, '
        'D40 ${percent(active.byClass['D40'] ?? 0)}. '
        'NMS IoU $iou% is separate.';
  }
  final value =
      active.byClass.values.isEmpty ? 0.0 : active.byClass.values.first;
  return 'Active: global ${percent(value)} for every class on the next capture. '
      'NMS IoU $iou% is separate.';
}

/// Null, NaN, and infinity are rejected. Other numbers are clamped to the slider.
double? clampConfidenceThreshold(double? value) {
  if (value == null || value.isNaN || value.isInfinite) return null;
  if (value < confidenceSliderMin) return confidenceSliderMin;
  if (value > confidenceSliderMax) return confidenceSliderMax;
  return value;
}

/// [savedSlider] null keeps [classDefaults]. A saved value replaces every class.
Map<String, double> resolveClassThresholds(
  Map<String, double> classDefaults,
  double? savedSlider,
) {
  final clamped = clampConfidenceThreshold(savedSlider);
  if (clamped == null) {
    return Map<String, double>.from(classDefaults);
  }
  return {for (final key in classDefaults.keys) key: clamped};
}
