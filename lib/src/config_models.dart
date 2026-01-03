// lib/src/config_models.dart
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:blog_builder/src/image_processor.dart';

/// Configuration for RSS feed generation
class RssConfig {
  final bool enabled;
  final String? title;        // Override site title
  final String? description;  // Override site description
  final String fileName;      // Output filename (default: "feed.xml")
  final List<String> layouts; // Which layouts to include (empty = all)
  final int? itemLimit;       // Max items in feed (null = unlimited)

  RssConfig({
    this.enabled = false,
    this.title,
    this.description,
    this.fileName = 'feed.xml',
    this.layouts = const [],
    this.itemLimit,
  });

  factory RssConfig.parse(Map<String, dynamic>? configMap) {
    if (configMap == null) {
      return RssConfig();
    }

    // Parse layouts list
    List<String> layouts = [];
    if (configMap['layouts'] != null) {
      final layoutsValue = configMap['layouts'];
      if (layoutsValue is List) {
        layouts = layoutsValue.map((e) => e.toString()).toList();
      } else if (layoutsValue is String) {
        layouts = [layoutsValue];
      }
    }

    return RssConfig(
      enabled: configMap['enabled'] == true,
      title: configMap['title']?.toString(),
      description: configMap['description']?.toString(),
      fileName: configMap['file_name']?.toString() ?? 'feed.xml',
      layouts: layouts,
      itemLimit: configMap['item_limit'] is int
          ? configMap['item_limit'] as int
          : (int.tryParse(configMap['item_limit']?.toString() ?? '') ?? null),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'title': title,
      'description': description,
      'file_name': fileName,
      'layouts': layouts,
      'item_limit': itemLimit,
    };
  }
}

/// Configuration for AT Protocol comment system
class AtProtoConfig {
  final bool enabled;
  final String? serviceIdentifier;  // The bot account handle (for server-side posting)
  final String appViewUrl;          // AppView endpoint (read)
  final String? turnstileSiteKey;   // Cloudflare Turnstile site key for captcha

  AtProtoConfig({
    this.enabled = false,
    this.serviceIdentifier,
    this.appViewUrl = 'https://public.api.bsky.app',
    this.turnstileSiteKey,
  });

  factory AtProtoConfig.parse(Map<String, dynamic>? configMap) {
    if (configMap == null) {
      return AtProtoConfig();
    }

    return AtProtoConfig(
      enabled: configMap['enabled'] == true,
      serviceIdentifier: configMap['service_identifier']?.toString(),
      appViewUrl: configMap['app_view_url']?.toString() ?? 'https://public.api.bsky.app',
      turnstileSiteKey: configMap['turnstile_site_key']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'service_identifier': serviceIdentifier,
      'app_view_url': appViewUrl,
      'turnstile_site_key': turnstileSiteKey,
    };
  }
}

class ConfigModel {
  final String? title;
  final String? owner;
  final Map<String, String> metadata; // Keep original type here
  final String? baseUrl;
  final ImageOptimizationConfig imageOptimization;
  final bool fallbackMetaTags; // If true, use first paragraph/image for meta tags when not specified
  final RssConfig rss; // RSS feed configuration
  final AtProtoConfig atProto; // AT Protocol comment system configuration

  ConfigModel({
    this.title,
    required this.metadata,
    this.owner,
    this.baseUrl,
    ImageOptimizationConfig? imageOptimization,
    this.fallbackMetaTags = false,
    RssConfig? rss,
    AtProtoConfig? atProto,
  }) : imageOptimization = imageOptimization ?? ImageOptimizationConfig(),
       rss = rss ?? RssConfig(),
       atProto = atProto ?? AtProtoConfig();

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

    // Parse fallback meta tags option
    bool fallbackMetaTags = false;
    if (cfg.containsKey("fallback_meta_tags")) {
      fallbackMetaTags = cfg["fallback_meta_tags"] == true;
    }

    // Parse AT Protocol config
    AtProtoConfig? atProtoConfig;
    if (cfg.containsKey("at_proto")) {
      final atProtoMap = cfg["at_proto"];
      if (atProtoMap is YamlMap) {
        atProtoConfig = AtProtoConfig.parse(_yamlMapToMap(atProtoMap));
      }
    }

    // Parse RSS config
    RssConfig? rssConfig;
    if (cfg.containsKey("rss")) {
      final rssMap = cfg["rss"];
      if (rssMap is YamlMap) {
        rssConfig = RssConfig.parse(_yamlMapToMap(rssMap));
      }
    }

    return ConfigModel(
        title: cfg["title"]?.toString(), // Safe access
        metadata: metadata, // Store as Map initially
        owner: cfg["owner"]?.toString(),
        baseUrl: cfg["baseUrl"]?.toString(),
        imageOptimization: imageOptConfig,
        fallbackMetaTags: fallbackMetaTags,
        rss: rssConfig,
        atProto: atProtoConfig,
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
      'baseUrl': baseUrl,
      'rss': rss.toMap(),
      'at_proto': atProto.toMap(),
    };
  }
}
