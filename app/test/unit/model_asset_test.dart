import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/core/constants.dart';
import 'package:tariqmap/core/model_config.dart';

void main() {
  test('the default loader opens road_damage.tflite and RoadSense stays optional', () {
    expect(TariqMapConstants.useRoadSenseModel, isFalse);
    expect(ModelConfig.active.name, 'road_damage');
    expect(ModelConfig.active.assetPath, TariqMapConstants.legacyModelAsset);
    expect(ModelConfig.active.assetPath, 'assets/models/road_damage.tflite');

    final legacy = File(ModelConfig.active.assetPath);
    expect(legacy.existsSync(), isTrue, reason: 'default model asset must be on disk');
    final legacyHash = sha256.convert(legacy.readAsBytesSync()).toString();
    expect(legacyHash, ModelConfig.legacy.sha256Checksum);

    expect(ModelConfig.roadSense.assetPath, isNot(ModelConfig.active.assetPath));
    final roadSense = File(ModelConfig.roadSense.assetPath);
    expect(roadSense.existsSync(), isTrue, reason: 'USE_ROADSENSE_MODEL still needs this file');
    final roadSenseHash = sha256.convert(roadSense.readAsBytesSync()).toString();
    expect(roadSenseHash, ModelConfig.roadSense.sha256Checksum);
  });
}
