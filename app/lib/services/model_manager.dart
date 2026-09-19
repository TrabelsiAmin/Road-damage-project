import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// URLs for each agent's TFLite model on GitHub Releases.
/// Replace with your actual release asset URLs after uploading the models.
const _modelUrls = {
  'cracks':   'https://github.com/YOUR_ORG/TariqMap/releases/latest/download/cracks.tflite',
  'pavement': 'https://github.com/YOUR_ORG/TariqMap/releases/latest/download/pavement.tflite',
  'surface':  'https://github.com/YOUR_ORG/TariqMap/releases/latest/download/surface.tflite',
};

/// Known SHA-256 checksums for each model file.
/// Update these after uploading your real model weights.
const _modelSha256 = {
  'cracks':   'REPLACE_AFTER_UPLOAD',
  'pavement': 'REPLACE_AFTER_UPLOAD',
  'surface':  'REPLACE_AFTER_UPLOAD',
};

/// Manages downloading, caching, and verification of TFLite model files.
///
/// On Android/iOS: downloads models to app documents directory on first use.
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

      final url = _modelUrls[agentName];
      if (url == null) return null;

      debugPrint('[ModelManager] Downloading $agentName model from $url');
      final downloaded = await _downloadWithProgress(url, file, onProgress: onProgress);
      if (!downloaded) return null;

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

  Future<bool> _downloadWithProgress(
    String url,
    File destination, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        debugPrint('[ModelManager] HTTP ${response.statusCode} for $url');
        return false;
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = destination.openWrite();
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      });
      await sink.close();
      return true;
    } catch (e) {
      debugPrint('[ModelManager] Download error: $e');
      return false;
    }
  }
}
