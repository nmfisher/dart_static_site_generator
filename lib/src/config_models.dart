import 'dart:io';
import 'package:yaml/yaml.dart';


class ConfigModel {
  final String? title;
  final String? owner;
  final Map<String, String> metadata;

  ConfigModel({
    this.title,
    required this.metadata,
    this.owner,
  });

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
       throw Exception("Invalid config file format. Expected a YAML map. File: ${configFile.path}");
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

    return ConfigModel(
        title: cfg["title"]?.toString(), // Safe access
        metadata: metadata,
        owner: cfg["owner"]?.toString());
  }

   // Add a helper method to convert to a Map for template rendering if needed
   Map<String, dynamic> toMap() {
     return {
       'title': title,
       'owner': owner,
       'metadata': metadata,
     };
   }
}
