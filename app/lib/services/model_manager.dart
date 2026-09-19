import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// URLs for each agent's TFLite model on GitHub Releases.
///
/// STATUS: REQUIRES MODEL
/// Replace these after a validated YOLOv8 → TFLite export. Placeholder
/// YOUR_ORG URLs are never fetched.
const _modelUrls = {
  'cracks':
      'https://github.com/YOUR_ORG/TariqMap/releases/latest/download/cracks.tflite',
  'pavement':
      'https://github.com/YOUR_ORG/TariqMap/releases/latest/download/pavement.tflite',
  'surface':
      'https://github.com/YOUR_ORG/TariqMap/releases/latest/download/surface.tflite',
};

/// Known SHA-256 checksums for each model file.
const _modelSha256 = {
  'cracks': 'REPLACE_AFTER_UPLOAD',
  'pavement': 'REPLACE_AFTER_UPLOAD',
  'surface': 'REPLACE_AFTER_UPLOAD',
};

bool _isPlaceholderUrl(String? url) =>
    url == null ||
    url.contains('YOUR_ORG') ||
    url.contains('REPLACE_AFTER');

bool _isPlaceholderChecksum(String? value) =>
    value == null || value == 'REPLACE_AFTER_UPLOAD';

/// Manages downloading, caching, and verification of TFLite model files.
///
/// Lookup order:
///   1. Previously downloaded + checksum-verified file
///   2. Bundled Flutter asset `assets/models/<agent>.tflite` (if present)
///   3. GitHub Release download (skipped while URLs are placeholders)
///   4. null → DetectionService falls back to mock and reports model pending
class ModelManager {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  final Map<String, String?> _cachedPaths = {};

  /// Returns the local file path for the given [agentName]'s model,
  /// or null if not available (web, asset pending, download failed).
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
        await file.delete();
      }

      final bundled = await _copyBundledAsset(agentName, file);
      if (bundled != null) {
        _cachedPaths[agentName] = bundled;
        return bundled;
      }

      final url = _modelUrls[agentName];
      if (_isPlaceholderUrl(url)) {
        debugPrint(
          '[ModelManager] $agentName TFLite asset is still pending. '
          'Train, export, then place $agentName.tflite in assets/models/ '
          'or publish a GitHub Release.',
        );
        _cachedPaths[agentName] = null;
        return null;
      }

      debugPrint('[ModelManager] Downloading $agentName model from $url');
      final downloaded =
          await _downloadWithProgress(url!, file, onProgress: onProgress);
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

  Future<String?> _copyBundledAsset(String agentName, File destination) async {
    try {
      final data = await rootBundle.load('assets/models/$agentName.tflite');
      await destination.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (!await _checksumValid(destination, agentName)) {
        await destination.delete();
        return null;
      }
      debugPrint('[ModelManager] Installed bundled asset for $agentName');
      return destination.path;
    } catch (_) {
      // Asset not listed / not present — expected until a real model is exported.
      return null;
    }
  }

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
    if (_isPlaceholderChecksum(expected)) return true;
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
        client.close();
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
      client.close();
      return true;
    } catch (e) {
      debugPrint('[ModelManager] Download error: $e');
      return false;
    }
  }
}
