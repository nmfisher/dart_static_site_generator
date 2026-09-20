import 'package:yaml/yaml.dart';

/// Per-locale string tables exposed to templates as `site.strings`
/// (ticket 005).
///
/// Config:
///
/// ```yaml
/// strings:
///   en: strings/en.yaml
///   zh: strings/zh.yaml
/// ```
///
/// Each YAML file becomes a nested map (`nav: {shop: SHOP}` is reachable as
/// `site.strings.nav.shop`). A template referencing a key that the locale's
/// table does not define fails the build with the key name (fail loud).
class StringTables {
  /// Locale code -> nested string table.
  final Map<String, Map<String, dynamic>> tables;

  StringTables(this.tables);

  bool get isEmpty => tables.isEmpty;

  /// The table visible on a page of [locale], falling back to the default
  /// locale's table when the page's locale has none.
  Map<String, dynamic>? forLocale(String? locale, String defaultLocale) {
    if (isEmpty) return null;
    return tables[locale] ?? tables[defaultLocale];
  }

  /// Loads every configured table from [inputDir]. Missing files and
  /// non-map YAML are build errors.
  static StringTables load(
      Map<String, String> paths, String Function(String path) read) {
    final tables = <String, Map<String, dynamic>>{};
    for (final entry in paths.entries) {
      String content;
      try {
        content = read(entry.value);
      } catch (e) {
        throw FormatException(
            'strings table for "${entry.key}" cannot be read at '
            '${entry.value}: $e');
      }
      dynamic parsed;
      try {
        parsed = loadYaml(content);
      } catch (e) {
        throw FormatException(
            'strings table for "${entry.key}" is not valid YAML '
            '(${entry.value}): $e');
      }
      if (parsed is! YamlMap) {
        throw FormatException(
            'strings table for "${entry.key}" must be a YAML map '
            '(${entry.value})');
      }
      tables[entry.key] = _convert(parsed);
    }
    return StringTables(tables);
  }

  /// Keys referenced as `site.strings.<key>` in [source] but missing from at
  /// least one loaded table. Returns human-readable errors naming the key.
  static List<String> validateSource(
      String source, String templateName, StringTables tables) {
    final issues = <String>[];
    final matches = RegExp(r'site\.strings\.([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*)')
        .allMatches(source);
    if (matches.isEmpty) return issues;
    for (final match in matches) {
      final segments = match.group(1)!.split('.');
      for (final entry in tables.tables.entries) {
        dynamic node = entry.value;
        for (final segment in segments) {
          if ((node is Map) && node.containsKey(segment)) {
            node = node[segment];
          } else {
            issues.add(
                'Missing string key "site.strings.${segments.join(".")}" '
                '(template $templateName, locale ${entry.key})');
            break;
          }
        }
      }
    }
    return issues;
  }

  static Map<String, dynamic> _convert(YamlMap map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final value = entry.value;
      result[entry.key.toString()] =
          value is YamlMap ? _convert(value) : value;
    }
    return result;
  }
}
