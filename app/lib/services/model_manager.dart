import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The four-class checkpoint from oracl4/RoadDamageDetection, exported for
/// phone-side inference.
const _bundledModels = {
  'road_damage': 'assets/models/road_damage.tflite',
};

/// Known SHA-256 checksums for each model file.
/// Update these after uploading your real model weights.
const _modelSha256 = <String, String>{
  'road_damage': '830f99bd8c31c5d24138c16db7862dfb62293b96cc1dec241c36140bff8a813f',
};

/// Manages copying and verification of bundled TFLite model files.
///
/// On Android/iOS: copies the bundled model to app documents on first use.
/// On web/desktop: always returns null (mock fallback is used).
class ModelManager {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  final Map<String, String?> _cachedPaths = {};

  /// Returns the local file path for the given [agentName]'s model,
  /// or null if not available (web, download failed, etc.).
  ///
  /// [onProgress] receives a value 0.0–1.0 during download.
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
          return file.path;
        }
        // Corrupted — delete and re-download.
        await file.delete();
      }

      final asset = _bundledModels[agentName];
      if (asset == null) return null;

      debugPrint('[ModelManager] Copying bundled $agentName model');
      final data = await rootBundle.load(asset);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      onProgress?.call(1.0);

      if (!await _checksumValid(file, agentName)) {
        debugPrint('[ModelManager] Checksum mismatch for $agentName — deleting.');
        await file.delete();
        return null;
      }

      _cachedPaths[agentName] = file.path;
      return file.path;
    } catch (e) {
      debugPrint('[ModelManager] Error loading model $agentName: $e');
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
    } catch (_) {}
  }

  Future<bool> _checksumValid(File file, String agentName) async {
    final expected = _modelSha256[agentName];
    // Skip validation if placeholder is still set (dev mode).
    if (expected == null || expected == 'REPLACE_AFTER_UPLOAD') return true;
    final bytes = await file.readAsBytes();
    final actual = sha256.convert(bytes).toString();
    return actual == expected;
  }

}
