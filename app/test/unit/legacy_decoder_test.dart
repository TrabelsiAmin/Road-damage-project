import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/inference/legacy_decoder.dart';

void main() {
  const names = {0: 'D00', 1: 'D10', 2: 'D20', 3: 'D40'};
  const classes = ['D00', 'D10', 'D20', 'D40'];
  const thresholds = {'D00': 0.35, 'D10': 0.35, 'D20': 0.30, 'D40': 0.40};

  List<List<List<double>>> buffer({
    required int anchors,
    required void Function(List<List<double>> channels, int anchor) fill,
  }) {
    final channels = List.generate(8, (_) => List<double>.filled(anchors, 0));
    for (var a = 0; a < anchors; a++) {
      fill(channels, a);
    }
    return [channels];
  }

  test('measured legacy shape is accepted and RoadSense shape is rejected', () {
    expect(isLegacyRoadDamageOutputShape(const [1, 8, 8400]), isTrue);
    expect(isLegacyRoadDamageOutputShape(const [1, 9, 8400]), isFalse);
    expect(isLegacyRoadDamageOutputShape(const [1, 8400, 8]), isFalse);
  });

  test('center-format box on channel-major [1,8,anchors] becomes top-left', () {
    final output = buffer(anchors: 1, fill: (ch, a) {
      ch[0][a] = 0.50; // cx
      ch[1][a] = 0.40; // cy
      ch[2][a] = 0.20; // w
      ch[3][a] = 0.10; // h
      ch[6][a] = 0.62; // D20
    });

    final dets = decodeLegacyYoloOutput(
      output: output,
      classNames: names,
      agentClasses: classes,
      classThresholds: thresholds,
    );

    expect(dets, hasLength(1));
    expect(dets.single.classCode, 'D20');
    expect(dets.single.confidence, closeTo(0.62, 1e-9));
    expect(dets.single.box.x, closeTo(0.40, 1e-9));
    expect(dets.single.box.y, closeTo(0.35, 1e-9));
    expect(dets.single.box.width, closeTo(0.20, 1e-9));
    expect(dets.single.box.height, closeTo(0.10, 1e-9));
  });

  test('D40 at 0.38 is dropped by the 0.40 threshold; 0.41 is kept', () {
    final low = buffer(anchors: 1, fill: (ch, a) => ch[7][a] = 0.38);
    final high = buffer(anchors: 1, fill: (ch, a) {
      ch[0][a] = 0.5;
      ch[1][a] = 0.5;
      ch[2][a] = 0.2;
      ch[3][a] = 0.2;
      ch[7][a] = 0.41;
    });

    expect(
      decodeLegacyYoloOutput(
        output: low,
        classNames: names,
        agentClasses: classes,
        classThresholds: thresholds,
      ),
      isEmpty,
    );
    final kept = decodeLegacyYoloOutput(
      output: high,
      classNames: names,
      agentClasses: classes,
      classThresholds: thresholds,
    );
    expect(kept.single.classCode, 'D40');
  });

  test('scores at or below zero do not emit a box', () {
    final output = buffer(anchors: 1, fill: (ch, a) {
      for (var c = 4; c < 8; c++) {
        ch[c][a] = -0.2;
      }
    });
    expect(
      decodeLegacyYoloOutput(
        output: output,
        classNames: names,
        agentClasses: classes,
        classThresholds: thresholds,
      ),
      isEmpty,
    );
  });

  test('onlyD40 drops a stronger crack on another anchor', () {
    final output = buffer(anchors: 2, fill: (ch, a) {
      ch[0][a] = 0.5;
      ch[1][a] = 0.5;
      ch[2][a] = 0.1;
      ch[3][a] = 0.1;
      if (a == 0) ch[6][a] = 0.9; // D20
      if (a == 1) ch[7][a] = 0.5; // D40
    });
    final dets = decodeLegacyYoloOutput(
      output: output,
      classNames: names,
      agentClasses: classes,
      classThresholds: thresholds,
      onlyD40: true,
    );
    expect(dets, hasLength(1));
    expect(dets.single.classCode, 'D40');
  });
}
