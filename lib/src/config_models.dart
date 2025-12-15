// lib/src/config_models.dart
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:blog_builder/src/image_processor.dart';

class ConfigModel {
  final String? title;
  final String? owner;
  final Map<String, String> metadata; // Keep original type here
  final String? baseUrl;
  final ImageOptimizationConfig imageOptimization;

  ConfigModel({
    this.title,
    required this.metadata,
    this.owner,
    this.baseUrl,
    ImageOptimizationConfig? imageOptimization,
  }) : imageOptimization = imageOptimization ?? ImageOptimizationConfig();

  factory ConfigModel.parse(File configFile) {
    final content = configFile.readAsStringSync();
    if (content.trim().isEmpty) {
      throw Exception("Config file is empty: ${configFile.path}");
    }

    dynamic cfgYaml;
    try {
      cfgYaml = loadYaml(content);
    } catch (e) {
      throw Exception("Failed to parse YAML in ${configFile.path}: $e");
    }

    if (cfgYaml == null || cfgYaml is! YamlMap) {
      throw Exception(
          "Invalid config file format. Expected a YAML map. File: ${configFile.path}");
    }
    final cfg = cfgYaml as YamlMap;

    var metadata = <String, String>{};
    try {
      if (cfg.containsKey("meta") && cfg["meta"] is YamlMap) {
        final metaMap = cfg["meta"] as YamlMap;
        for (final key in metaMap.keys) {
          // Ensure both key and value are strings
          metadata[key.toString()] = metaMap[key]?.toString() ?? '';
        }
      }
    } catch (err) {
      print("Warning: Could not parse 'meta' section in config: $err");
      // usually if meta is empty, ignore
    }

    print("Parsing config: ${configFile.path}");

    // Parse image optimization config
    ImageOptimizationConfig? imageOptConfig;
    if (cfg.containsKey("image_optimization")) {
      final imageOptMap = cfg["image_optimization"];
      if (imageOptMap is YamlMap) {
        imageOptConfig = ImageOptimizationConfig.fromMap(
            _yamlMapToMap(imageOptMap));
      }
    }

    return ConfigModel(
        title: cfg["title"]?.toString(), // Safe access
        metadata: metadata, // Store as Map initially
        owner: cfg["owner"]?.toString(),
        baseUrl: cfg["baseUrl"]?.toString(),
        imageOptimization: imageOptConfig,
        );
  }

  /// Helper to convert YamlMap to Map<String, dynamic>
  static Map<String, dynamic> _yamlMapToMap(YamlMap yamlMap) {
    final result = <String, dynamic>{};
    for (final key in yamlMap.keys) {
      final value = yamlMap[key];
      if (value is YamlMap) {
        result[key.toString()] = _yamlMapToMap(value);
      } else if (value is YamlList) {
        result[key.toString()] = value.toList();
      } else {
        result[key.toString()] = value;
      }
    }
    return result;
  }

  // Convert to a Map for template rendering, PASSING MAP DIRECTLY
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'owner': owner,
      // CHANGE: Pass metadata directly as a Map
      'metadata': metadata,
    };
  }
}
