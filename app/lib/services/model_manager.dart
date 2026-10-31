import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/model_config.dart';

/// The bundled model assets for TariqMap.
final _bundledModels = <String, String>{
  'road_damage': ModelConfig.legacy.assetPath,
  'road_damage_roadsense': ModelConfig.roadSense.assetPath,
};

/// Known SHA-256 checksums for each model file.
const _modelSha256 = <String, String>{
  'road_damage': '830f99bd8c31c5d24138c16db7862dfb62293b96cc1dec241c36140bff8a813f',
  'road_damage_roadsense': '300798be883a7003a1a20f3d13757f9338a8cbec5e0ece9f990a2a5179286ccb',
};

/// Manages copying and verification of bundled TFLite model files.
///
/// On Android/iOS: copies the bundled model to app documents on first use and
/// validates SHA-256 integrity.
/// On web/desktop: returns null (mock fallback only on unsupported web).
class ModelManager {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  final Map<String, String?> _cachedPaths = {};
  final Map<String, String> _integrityErrors = {};

  String? integrityError(String agentName) => _integrityErrors[agentName];

  /// Returns the local file path for the given [agentName]'s model,
  /// or null if not available or if checksum failed.
  Future<String?> localModelPath(
    String agentName, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) return null;
    if (_cachedPaths.containsKey(agentName)) return _cachedPaths[agentName];

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${dir.path}/tariqmap_models');
      await modelsDir.create(recursive: true);

      final file = File('${modelsDir.path}/$agentName.tflite');

      if (await file.exists()) {
        if (await _checksumValid(file, agentName)) {
          _cachedPaths[agentName] = file.path;
          _integrityErrors.remove(agentName);
          return file.path;
        }
        // Corrupted / checksum failed — delete and re-copy
        await file.delete();
      }

      final asset = _bundledModels[agentName];
      if (asset == null) {
        _integrityErrors[agentName] = 'Asset for $agentName is not defined in bundle';
        return null;
      }

      debugPrint('[ModelManager] Copying bundled $agentName model from $asset');
      final data = await rootBundle.load(asset);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      onProgress?.call(1.0);

      if (!await _checksumValid(file, agentName)) {
        final err = 'Checksum mismatch for $agentName — model corrupted';
        debugPrint('[ModelManager] $err — deleting.');
        _integrityErrors[agentName] = err;
        await file.delete();
        return null;
      }

      _cachedPaths[agentName] = file.path;
      _integrityErrors.remove(agentName);
      return file.path;
    } catch (e) {
      final err = 'Error loading model $agentName: $e';
      debugPrint('[ModelManager] $err');
      _integrityErrors[agentName] = err;
      _cachedPaths[agentName] = null;
      return null;
    }
  }

  /// Deletes all cached model files (for settings/reset).
  Future<void> clearCache() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${dir.path}/tariqmap_models');
      if (await modelsDir.exists()) await modelsDir.delete(recursive: true);
      _cachedPaths.clear();
      _integrityErrors.clear();
    } catch (_) {}
  }

  Future<bool> _checksumValid(File file, String agentName) async {
    final expected = _modelSha256[agentName];
    if (expected == null || expected == 'REPLACE_AFTER_UPLOAD') return true;
    final bytes = await file.readAsBytes();
    final actual = sha256.convert(bytes).toString();
    final valid = actual == expected;
    if (!valid) {
      _integrityErrors[agentName] =
          'SHA-256 validation failed for $agentName. Expected: $expected, Got: $actual';
    }
    return valid;
  }
}
