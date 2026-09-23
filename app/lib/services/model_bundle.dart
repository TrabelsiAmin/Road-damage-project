import 'dart:convert';
import 'package:flutter/services.dart';

class AgentManifest {
  const AgentManifest({required this.name, required this.classes, required this.file, required this.sha256});
  final String name;
  final List<String> classes;
  final String file;
  final String sha256;

  factory AgentManifest.fromJson(Map<String, dynamic> json) => AgentManifest(
        name: json['name'] as String,
        classes: (json['classes'] as List<dynamic>).cast<String>(),
        file: json['file'] as String,
        sha256: json['sha256'] as String,
      );
}

class ModelBundleManifest {
  const ModelBundleManifest({required this.bundleVersion, required this.inputSize, required this.confidenceThreshold, required this.iouThreshold, required this.agents});
  final String bundleVersion;
  final int inputSize;
  final double confidenceThreshold;
  final double iouThreshold;
  final List<AgentManifest> agents;

  factory ModelBundleManifest.fromJson(Map<String, dynamic> json) {
    final input = json['input'] as Map<String, dynamic>;
    final post = json['postprocess'] as Map<String, dynamic>;
    return ModelBundleManifest(
      bundleVersion: json['bundleVersion'] as String,
      inputSize: input['width'] as int,
      confidenceThreshold: (post['confidenceThreshold'] as num).toDouble(),
      iouThreshold: (post['iouThreshold'] as num).toDouble(),
      agents: (json['agents'] as List<dynamic>).map((item) => AgentManifest.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }
}

class ModelBundleLoader {
  Future<ModelBundleManifest> load() async {
    final raw = await rootBundle.loadString('assets/models/model-bundles.json');
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    final manifest = ModelBundleManifest.fromJson(parsed);
    if (manifest.agents.length != 1 || manifest.agents.first.name != 'road_damage') {
      throw StateError('A TariqMap RDD bundle must contain the road_damage agent.');
    }
    return manifest;
  }
}
